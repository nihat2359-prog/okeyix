// Opt in only against the hard-coded localhost synthetic test database.
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile, execFileSync, spawnSync } from 'node:child_process';
import { promisify } from 'node:util';
import { readFileSync } from 'node:fs';
const pg = process.env.REENGAGEMENT_PSQL || 'C:/Program Files/PostgreSQL/16/bin/psql.exe';
const args = ['-X','-q','-A','-t','-h','127.0.0.1','-p','55447','-U','postgres',
  '-d','okeyix_reengagement_test','-v','ON_ERROR_STOP=1'];
const sql = (input) => execFileSync(pg,args,{ input,encoding:'utf8' }).trim();
const attempt = (input) => spawnSync(pg,args,{ input,encoding:'utf8' });
const signature = 'public.okeyix_reengagement_test_worker(text,uuid,uuid,uuid,text,jsonb)';
const migration = readFileSync(new URL('../supabase/migrations/20261028000300_reengagement_test_push.sql',import.meta.url),'utf8');
const guard = migration.match(/DO \$\$ DECLARE missing text; BEGIN[\s\S]*?END \$\$;/)[0];
const enabled = process.env.REENGAGEMENT_LOCAL_PG === '1';
const asyncExec = promisify(execFile);
const parallelSql = async (input) => (await asyncExec(pg,[...args,'-c',input])).stdout.trim();

test('repeat install fails closed without replacing function or history', { skip: !enabled }, () => {
  assert.equal(sql('SELECT current_database();'),'okeyix_reengagement_test');
  const original = sql(`SELECT pg_get_functiondef('${signature}'::regprocedure);`);
  const result = attempt(migration);
  assert.notEqual(result.status,0);
  assert.match(result.stderr,/TEST_PUSH_ALREADY_INSTALLED_REVIEW_REQUIRED_NO_CHANGES/);
  assert.equal(sql(`SELECT pg_get_functiondef('${signature}'::regprocedure);`),original);
});
test('unexpected deployed column type aborts before installing anything', { skip: !enabled }, () => {
  const result = attempt(`BEGIN;
    ALTER SCHEMA okeyix_reengagement_test_private RENAME TO reengagement_fixture_hidden;
    ALTER FUNCTION ${signature} RENAME TO reengagement_fixture_hidden_worker;
    ALTER TABLE public.user_devices ALTER COLUMN push_token TYPE varchar;
    ${guard}
    ROLLBACK;`);
  assert.notEqual(result.status,0);
  assert.match(result.stderr,/TEST_PUSH_SCHEMA_MISMATCH: public.user_devices.push_token expected text/);
  // Connection close rolled back all temporary DDL changes.
  assert.equal(sql(`SELECT to_regprocedure('${signature}') IS NOT NULL;`),'t');
});
test('rollback refuses an outstanding dispatch; otherwise removes only test RPC', { skip: !enabled }, () => {
  const rollback = readFileSync(new URL('../docs/reengagement_test_rollback.sql',import.meta.url),'utf8');
  const original = sql(`SELECT pg_get_functiondef('${signature}'::regprocedure);`);
  const id = '00000000-0000-0000-0000-000000000077';
  try {
    sql(`INSERT INTO okeyix_reengagement_test_private.tickets
      (id,user_id,device_id,token_hash,status,test_consent_confirmed,approved_at,expires_at,dispatched_at,receipt_hash)
      VALUES('${id}','${id}','${id}',repeat('a',64),'dispatching',true,
        statement_timestamp(),statement_timestamp()+interval '14 minutes',statement_timestamp(),repeat('b',64));`);
    const blocked = attempt(rollback);
    assert.notEqual(blocked.status,0);
    assert.match(blocked.stderr,/TEST_DISPATCH_IN_PROGRESS_STOP_AND_INSPECT_BEFORE_ROLLBACK/);
    assert.equal(sql(`SELECT to_regprocedure('${signature}') IS NOT NULL;`),'t');
    sql(`DELETE FROM okeyix_reengagement_test_private.tickets WHERE id='${id}';`);
    sql(rollback);
    assert.equal(sql(`SELECT to_regprocedure('${signature}') IS NULL;`),'t');
    assert.equal(sql("SELECT to_regclass('okeyix_reengagement_test_private.tickets') IS NOT NULL;"),'t');
    assert.equal(sql("SELECT to_regclass('public.user_devices') IS NOT NULL;"),'t');
  } finally {
    // Restore ONLY this local test function and its ACL for subsequent local tests.
    sql(`DELETE FROM okeyix_reengagement_test_private.tickets WHERE id='${id}';`);
    sql(original);
    sql(`REVOKE ALL ON FUNCTION ${signature} FROM PUBLIC,anon,authenticated;
      GRANT EXECUTE ON FUNCTION ${signature} TO service_role;`);
  }
});
test('eight simultaneous test consumers and finishers consume and finish once', { skip: !enabled }, async () => {
  assert.equal(sql('SELECT current_database();'),'okeyix_reengagement_test');
  const id = '00000000-0000-0000-0000-000000000088';
  const previousHash = sql('SELECT quote_nullable(rpc_secret_hash) FROM okeyix_reengagement_test_private.authorization;');
  const capability = 'offline-concurrent-manual-rpc-capability';
  const call = (action,result="'{}'::jsonb") => `SELECT public.okeyix_reengagement_test_worker(
    '${action}','${id}','${id}','${id}','${capability}',${result});`;
  try {
    sql(`INSERT INTO auth.users(id) VALUES('${id}');
      INSERT INTO public.users(id) VALUES('${id}');
      INSERT INTO public.profiles(id,last_seen_at) VALUES('${id}',clock_timestamp());
      INSERT INTO public.user_devices(id,user_id,platform,push_token) VALUES('${id}','${id}','ios','synthetic-parallel-token');
      UPDATE okeyix_reengagement_test_private.authorization SET rpc_secret_hash=encode(sha256(convert_to('${capability}','UTF8')),'hex');
      INSERT INTO okeyix_reengagement_test_private.tickets
        (id,user_id,device_id,token_hash,status,test_consent_confirmed,approved_at,expires_at)
      VALUES('${id}','${id}','${id}',encode(sha256(convert_to('synthetic-parallel-token','UTF8')),'hex'),
        'approved',true,statement_timestamp(),statement_timestamp()+interval '14 minutes');`);
    const permits = (await Promise.all(Array.from({length:8},()=>parallelSql(call('consume')))))
      .map(JSON.parse).filter((value)=>value.token);
    assert.equal(permits.length,1);
    assert.match(permits[0].receipt,/^[a-f0-9]{64}$/);
    const result = `jsonb_build_object('status','accepted','code','FCM_ACCEPTED','http_status',200,'receipt','${permits[0].receipt}')`;
    const finished = (await Promise.all(Array.from({length:8},()=>parallelSql(call('finish',result)))))
      .map(JSON.parse).filter((value)=>value.recorded);
    assert.equal(finished.length,1);
    assert.equal(sql(`SELECT status FROM okeyix_reengagement_test_private.tickets WHERE id='${id}';`),'accepted');
  } finally {
    sql(`BEGIN;
      DELETE FROM okeyix_reengagement_test_private.tickets WHERE id='${id}';
      DELETE FROM public.user_devices WHERE id='${id}';
      DELETE FROM public.profiles WHERE id='${id}';
      DELETE FROM public.users WHERE id='${id}';
      DELETE FROM auth.users WHERE id='${id}';
      UPDATE okeyix_reengagement_test_private.authorization SET rpc_secret_hash=${previousHash};
      COMMIT;`);
  }
});

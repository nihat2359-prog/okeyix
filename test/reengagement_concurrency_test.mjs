// Explicitly opt in: REENGAGEMENT_LOCAL_PG=1 node --test test/reengagement_concurrency_test.mjs
// Hard-coded localhost + synthetic database. No network calls to Supabase/FCM.
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile, execFileSync } from 'node:child_process';
import { promisify } from 'node:util';

const pg = process.env.REENGAGEMENT_PSQL || 'C:/Program Files/PostgreSQL/16/bin/psql.exe';
const args = ['-X', '-q', '-A', '-t', '-h', '127.0.0.1', '-p', '55447', '-U', 'postgres',
  '-d', 'okeyix_reengagement_test', '-v', 'ON_ERROR_STOP=1'];
const sync = (sql) => execFileSync(pg, args, { input: sql, encoding: 'utf8' }).trim();
const asyncExec = promisify(execFile);
const query = async (sql) => (await asyncExec(pg, [...args, '-c', sql])).stdout.trim();

test('eight concurrent workers reserve once, and authorize once', {
  skip: process.env.REENGAGEMENT_LOCAL_PG !== '1',
}, async () => {
  assert.equal(sync('SELECT current_database();'), 'okeyix_reengagement_test');
  const original = sync("SELECT pg_get_functiondef('public.okeyix_reengagement_worker(text,uuid,jsonb)'::regprocedure);");
  const user = '00000000-0000-0000-0000-000000000002';
  const device = '00000000-0000-0000-0000-000000000022';
  try {
    sync(original.replace('v_now timestamptz:=clock_timestamp()',
      "v_now timestamptz:='2026-10-28 12:00+03'::timestamptz"));
    sync(`
      INSERT INTO auth.users(id) VALUES('${user}');
      INSERT INTO public.users(id) VALUES('${user}');
      INSERT INTO public.profiles(id,last_seen_at) VALUES('${user}','2026-10-26 12:00+03');
      INSERT INTO public.user_devices(id,user_id,device_id,platform,push_token,last_seen)
        VALUES('${device}','${user}','concurrency-fixture','ios','fake-concurrency-token','2026-10-26 12:00+03');
      INSERT INTO okeyix_reengagement_private.permissions VALUES('${user}','${device}',
        encode(sha256(convert_to('fake-concurrency-token','UTF8')),'hex'),true,'granted',
        '2026-10-26 12:00+03','2026-11-01 12:00+03','Offline concurrency fixture');
      UPDATE okeyix_reengagement_private.settings SET enabled=true,dry_run=false;
    `);
    const claims = await Promise.all(Array.from({ length: 8 }, () => query("SELECT public.okeyix_reengagement_worker('claim');")));
    const ids = claims.map((v) => JSON.parse(v).id).filter(Boolean);
    assert.equal(ids.length, 1);
    const authorized = await Promise.all(Array.from({ length: 8 }, () => query(
      `SELECT public.okeyix_reengagement_worker('authorize','${ids[0]}');`)));
    assert.equal(authorized.map((v) => JSON.parse(v).token).filter(Boolean).length, 1);
    assert.equal(sync(`SELECT count(*) FROM okeyix_reengagement_private.deliveries WHERE user_id='${user}';`), '1');
  } finally {
    sync(original);
    sync(`BEGIN;
      UPDATE okeyix_reengagement_private.settings SET enabled=false,dry_run=true;
      DELETE FROM okeyix_reengagement_private.deliveries WHERE user_id='${user}';
      DELETE FROM okeyix_reengagement_private.permissions WHERE user_id='${user}';
      DELETE FROM public.user_devices WHERE user_id='${user}';
      DELETE FROM public.profiles WHERE id='${user}';
      DELETE FROM public.users WHERE id='${user}';
      DELETE FROM auth.users WHERE id='${user}';
      COMMIT;
    `);
  }
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { execFile, execFileSync } from 'node:child_process';
import { promisify } from 'node:util';
const psql = 'C:/Program Files/PostgreSQL/16/bin/psql.exe';
const args = ['-X', '-q', '-A', '-t', '-h', '127.0.0.1', '-p', '56507', '-U', 'postgres', '-d', 'okeyix_reengagement_test', '-v', 'ON_ERROR_STOP=1'];
const sync = (sql) => execFileSync(psql, [...args, '-c', sql], { encoding: 'utf8' }).trim();
const run = promisify(execFile);
const query = async (sql) => JSON.parse((await run(psql, [...args, '-c', sql])).stdout.trim());

test('eight concurrent campaign workers claim and finalize each token only once', {
  skip: process.env.REENGAGEMENT_CAMPAIGN_LOCAL !== '1',
}, async () => {
  assert.equal(sync('SELECT current_database()'), 'okeyix_reengagement_test');
  const original = sync("SELECT pg_get_functiondef('public.okeyix_renewal_worker(text,uuid,jsonb)'::regprocedure)");
  sync(original.replace('v_now timestamptz:=clock_timestamp()',
    "v_now timestamptz:=date_trunc('day',clock_timestamp() AT TIME ZONE 'Europe/Istanbul') AT TIME ZONE 'Europe/Istanbul'+interval '12 hours'"));
  sync(`
    INSERT INTO auth.users(id) SELECT ('20000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid FROM generate_series(1,5) i;
    INSERT INTO public.users(id) SELECT id FROM auth.users;
    INSERT INTO public.profiles(id,last_seen_at) SELECT id,now() FROM auth.users;
    INSERT INTO public.user_devices(id,user_id,device_id,platform,push_token,last_seen,created_at)
      SELECT id,id,'concurrent-'||id,'ios','fake-concurrent-'||id,now(),now() FROM auth.users;
    SELECT okeyix_reengagement_private.prepare_campaign('offline-concurrency','Offline','Offline');
    UPDATE okeyix_reengagement_private.campaigns SET status='running';
  `);
  const claims = await Promise.all(Array.from({ length: 8 }, () => query("SELECT public.okeyix_renewal_worker('claim_batch')")));
  const batches = claims.filter((c) => c.items?.length);
  assert.equal(batches.length, 1);
  assert.equal(batches[0].items.length, 5);
  assert.equal(new Set(batches[0].items.map((i) => i.token)).size, 5);
  const batch = batches[0];
  const result = JSON.stringify({ batch_id: batch.batch_id, results: batch.items.map((i) => ({ id: i.id, status: 'accepted', code: 'FCM_ACCEPTED', http_status: 200 })) });
  const finishes = await Promise.all(Array.from({ length: 8 }, () => query(
    `SELECT public.okeyix_renewal_worker('finish_batch','${batch.campaign_id}','${result}'::jsonb)`)));
  assert.equal(finishes.filter((r) => r.recorded).length, 1);
  assert.equal(sync("SELECT count(*) FROM okeyix_reengagement_private.campaign_deliveries WHERE status='accepted'"), '5');
  assert.equal(sync("SELECT status FROM okeyix_reengagement_private.campaigns"), 'completed');
});

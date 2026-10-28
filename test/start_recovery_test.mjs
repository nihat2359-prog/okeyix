// Runs only against an isolated, synthetic localhost database, then removes it.
// START_RECOVERY_LOCAL_PG=1 node --test test/start_recovery_test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, execFile, spawnSync } from 'node:child_process';
import { promisify } from 'node:util';
import { readFileSync } from 'node:fs';

const pg = 'C:/Program Files/PostgreSQL/16/bin/psql.exe';
const db = `okeyix_start_recovery_test_${process.pid}`;
const args = ['-X', '-q', '-A', '-t', '-h', '127.0.0.1', '-p', '55449', '-U', 'postgres', '-v', 'ON_ERROR_STOP=1'];
const sql = (query, database = db) => execFileSync(pg, [...args, '-d', database], { input: query, encoding: 'utf8' }).trim();
const asyncExec = promisify(execFile);
const migration = readFileSync(new URL('../supabase/migrations/20261028000500_stale_start_recovery.sql', import.meta.url), 'utf8');
const fixture = readFileSync(new URL('./sql/start_recovery_fixture.sql', import.meta.url), 'utf8');
const id = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
function seed({ status = 'start', fresh = false, hand = '[]', recentStart = false, online = false, botOnly = false } = {}) {
  sql(`TRUNCATE public.tables,public.users,public.profiles,public.test_leaves CASCADE;
    INSERT INTO public.users VALUES('${id(1)}',false),('${id(2)}',true);
    INSERT INTO public.profiles VALUES('${id(1)}',now()-interval '${fresh ? '20 seconds' : '10 minutes'}',${online}),('${id(2)}',now()-interval '1 day',false);
    INSERT INTO public.tables VALUES('${id(3)}','${status}',2,now());
    INSERT INTO public.table_players(table_id,user_id,hand) VALUES('${id(3)}','${id(2)}','[]');
    ${botOnly ? '' : `INSERT INTO public.table_players(table_id,user_id,hand) VALUES('${id(3)}','${id(1)}','${hand}');`}
    ${recentStart ? '' : "UPDATE okeyix_start_private.pending SET entered_at=now()-interval '5 minutes';"}`);
}
const state = () => JSON.parse(sql(`SELECT jsonb_build_object(
  'status',(SELECT status FROM public.tables LIMIT 1),
  'seated',(SELECT count(*) FROM public.table_players),
  'leaves',(SELECT count(*) FROM public.test_leaves),
  'bot',(SELECT count(*) FROM public.table_players WHERE user_id='${id(2)}'),
  'pending',(SELECT count(*) FROM okeyix_start_private.pending));`));

test('stale start server recovery', { skip: process.env.START_RECOVERY_LOCAL_PG !== '1' }, async (t) => {
  sql(`CREATE DATABASE ${db};`, 'postgres');
  try {
    sql(fixture);
    sql(migration);
    await t.test('stale human leaves through existing RPC, bot remains, table reopens', () => {
      seed({ online: true }); // stale online flag after abrupt app termination
      assert.deepEqual(JSON.parse(sql('SELECT public.run_okey_watchdog();')), { original: true });
      assert.deepEqual(state(), { status: 'waiting', seated: 1, leaves: 1, bot: 1, pending: 0 });
      sql('SELECT public.run_okey_watchdog();');
      assert.equal(state().leaves, 1);
    });
    for (const options of [{ fresh: true }, { fresh: true, online: true }, { recentStart: true }, { hand: '[{"id":1}]' }, { status: 'playing' }, { botOnly: true }]) {
      await t.test(`preserves protected table ${JSON.stringify(options)}`, () => {
        seed(options);
        const before = state();
        sql('SELECT public.run_okey_watchdog();');
        assert.deepEqual(state(), before);
      });
    }
    await t.test('starting alias is also recovered', () => {
      seed({ status: 'starting' });
      sql('SELECT public.run_okey_watchdog();');
      assert.equal(state().status, 'waiting');
    });
    await t.test('missing presence does not justify eviction', () => {
      seed();
      sql(`UPDATE public.profiles SET last_seen_at=NULL WHERE id='${id(1)}';`);
      sql('SELECT public.run_okey_watchdog();');
      assert.equal(state().leaves, 0);
    });
    await t.test('failed leave rolls back that table and preserves watchdog result', () => {
      seed();
      assert.deepEqual(JSON.parse(sql("SET test.fail_leave='true'; SELECT public.run_okey_watchdog();")), { original: true });
      assert.equal(state().status, 'start');
      assert.equal(state().seated, 2);
      assert.equal(state().leaves, 0);
    });
    await t.test('new attempt receives a new grace period', () => {
      seed();
      sql(`UPDATE public.tables SET status='waiting'; UPDATE public.tables SET status='start';`);
      sql('SELECT public.run_okey_watchdog();');
      assert.equal(state().leaves, 0);
    });
    await t.test('existing leave may remove the entire table', () => {
      seed();
      sql("SET test.delete_table='true'; SELECT public.run_okey_watchdog();");
      assert.equal(state().status, null);
      assert.equal(state().seated, 0);
      assert.equal(state().pending, 0);
    });
    await t.test('one failed table does not prevent another from recovering', () => {
      seed();
      sql(`INSERT INTO public.users VALUES('${id(4)}',false);
        INSERT INTO public.profiles VALUES('${id(4)}',now()-interval '10 minutes',false);
        INSERT INTO public.tables VALUES('${id(5)}','start',2,now());
        INSERT INTO public.table_players(table_id,user_id) VALUES('${id(5)}','${id(4)}');
        UPDATE okeyix_start_private.pending SET entered_at=now()-interval '5 minutes';`);
      const result = JSON.parse(sql(`SET test.fail_user='${id(1)}'; SELECT okeyix_start_private.recover();`));
      assert.deepEqual(result, { recovered_tables: 1, removed_players: 1, errors: 1 });
      assert.equal(sql(`SELECT status FROM public.tables WHERE id='${id(3)}';`), 'start');
      assert.equal(sql(`SELECT status FROM public.tables WHERE id='${id(5)}';`), 'waiting');
    });
    await t.test('clients cannot call recovery', () => {
      const result = spawnSync(pg, [...args, '-d', db], { input: 'SET ROLE authenticated; SELECT okeyix_start_private.recover();', encoding: 'utf8' });
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /permission denied/);
    });
    await t.test('concurrent watchdog calls remove the human only once', async () => {
      seed();
      await Promise.all(Array.from({ length: 8 }, () => asyncExec(pg, [...args, '-d', db, '-c', 'SELECT public.run_okey_watchdog();'])));
      assert.deepEqual(state(), { status: 'waiting', seated: 1, leaves: 1, bot: 1, pending: 0 });
    });
    await t.test('repeat installation fails without changing existing functions', () => {
      const result = spawnSync(pg, [...args, '-d', db], { input: migration, encoding: 'utf8' });
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /START_RECOVERY_ALREADY_INSTALLED/);
      seed();
      sql('SELECT public.run_okey_watchdog();');
      assert.equal(state().leaves, 1);
    });
  } finally {
    sql(`DROP DATABASE ${db};`, 'postgres');
  }
});

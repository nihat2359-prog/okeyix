// Local synthetic database only. START_RECOVERY_LOCAL_PG=1 node --test test/prepare_closed_draw_test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
const pg = 'C:/Program Files/PostgreSQL/16/bin/psql.exe';
const db = `okeyix_start_recovery_test_prepare_${process.pid}`;
const args = ['-X','-q','-A','-t','-h','127.0.0.1','-p','55449','-U','postgres','-v','ON_ERROR_STOP=1'];
const sql = (q, database=db) => execFileSync(pg,[...args,'-d',database],{input:q,encoding:'utf8'}).trim();
const fixture = readFileSync(new URL('./sql/start_recovery_fixture.sql',import.meta.url),'utf8');
const migration = readFileSync(new URL('../supabase/migrations/20261028000600_prepare_closed_draw.sql',import.meta.url),'utf8');
test('prepared draw is authorized, private and does not mutate the hand or deck', {skip:process.env.START_RECOVERY_LOCAL_PG!=='1'}, () => {
  sql(`CREATE DATABASE ${db};`,'postgres');
  try {
    sql(fixture);
    sql(`CREATE SCHEMA auth;
      CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$ SELECT nullif(current_setting('test.uid',true),'')::uuid; $$;
      ALTER TABLE public.tables ADD COLUMN deck jsonb, ADD COLUMN round_count integer, ADD COLUMN current_turn integer, ADD COLUMN turn_started_at timestamptz;
      INSERT INTO public.users VALUES('00000000-0000-0000-0000-000000000001',false);
      INSERT INTO public.tables(id,status,deck,round_count,current_turn,turn_started_at)
        VALUES('00000000-0000-0000-0000-000000000003','playing','[{"id":"indicator"},{"id":"next"}]',1,0,now());
      ALTER TABLE public.table_players ADD COLUMN seat_index integer;
      INSERT INTO public.table_players(table_id,user_id,hand,seat_index)
        SELECT '00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000001',
          jsonb_agg(jsonb_build_object('id','old-'||n)),0 FROM generate_series(1,14) n;`);
    sql(migration);
    const call = (user) => `SET ROLE authenticated; SET test.uid='${user}'; SELECT public.okeyix_prepare_closed_draw('00000000-0000-0000-0000-000000000003');`;
    const member = '00000000-0000-0000-0000-000000000001';
    const before = sql('SELECT md5(row_to_json(t)::text) FROM public.tables t; SELECT md5(row_to_json(p)::text) FROM public.table_players p;');
    assert.equal(JSON.parse(sql(call(member))).tile.id,'next');
    assert.equal(JSON.parse(sql(call(member))).tile.id,'next');
    assert.equal(sql('SELECT md5(row_to_json(t)::text) FROM public.tables t; SELECT md5(row_to_json(p)::text) FROM public.table_players p;'),before);
    assert.equal(sql(call('00000000-0000-0000-0000-000000000002')),'');
    sql('UPDATE public.tables SET current_turn=1;');
    assert.equal(sql(call(member)),'');
    const denied = spawnSync(pg,[...args,'-d',db],{input:"SET ROLE anon; SELECT public.okeyix_prepare_closed_draw('00000000-0000-0000-0000-000000000003');",encoding:'utf8'});
    assert.notEqual(denied.status,0);
    assert.match(denied.stderr,/permission denied/);
  } finally { sql(`DROP DATABASE ${db};`,'postgres'); }
});

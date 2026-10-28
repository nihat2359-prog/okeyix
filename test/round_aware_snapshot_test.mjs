// Local synthetic PostgreSQL only. START_RECOVERY_LOCAL_PG=1 node --test test/round_aware_snapshot_test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
const pg = 'C:/Program Files/PostgreSQL/16/bin/psql.exe';
const db = `okeyix_start_recovery_test_snapshot_${process.pid}`;
const args = ['-X','-q','-A','-t','-h','127.0.0.1','-p','55449','-U','postgres','-v','ON_ERROR_STOP=1'];
const sql = (q, database=db) => execFileSync(pg,[...args,'-d',database],{input:q,encoding:'utf8'}).trim();
const fixture = readFileSync(new URL('./sql/start_recovery_fixture.sql',import.meta.url),'utf8');
const migration = readFileSync(new URL('../supabase/migrations/20261028000700_round_aware_game_snapshot.sql',import.meta.url),'utf8');
test('snapshot supplies the missing authoritative round without changing hands or game state', {skip:process.env.START_RECOVERY_LOCAL_PG!=='1'}, () => {
  sql(`CREATE DATABASE ${db};`,'postgres');
  try {
    sql(fixture);
    sql(`CREATE SCHEMA auth;
      CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$ SELECT nullif(current_setting('test.uid',true),'')::uuid; $$;
      ALTER TABLE public.tables ADD COLUMN round_count integer, ADD COLUMN current_turn integer, ADD COLUMN turn_started_at timestamptz;
      INSERT INTO public.users VALUES('00000000-0000-0000-0000-000000000001',false);
      INSERT INTO public.tables(id,status,round_count,current_turn,turn_started_at)
        VALUES('00000000-0000-0000-0000-000000000003','playing',2,1,now());
      INSERT INTO public.table_players(table_id,user_id,hand)
        VALUES('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000001','[{"id":"same-tile"}]');
      CREATE FUNCTION public.get_full_table_state(p_table_id uuid) RETURNS jsonb LANGUAGE sql AS $$
        SELECT jsonb_build_object('table',to_jsonb(t)-'round_count','league',NULL,
          'players',(SELECT jsonb_agg(to_jsonb(p)) FROM public.table_players p WHERE p.table_id=t.id))
        FROM public.tables t WHERE t.id=p_table_id;
      $$;`);
    sql(migration);
    const table = '00000000-0000-0000-0000-000000000003';
    const member = '00000000-0000-0000-0000-000000000001';
    const source = JSON.parse(sql(`SELECT public.get_full_table_state('${table}');`));
    assert.equal(source.table.round_count,undefined);
    const before = sql('SELECT md5(row_to_json(t)::text) FROM public.tables t; SELECT md5(row_to_json(p)::text) FROM public.table_players p;');
    const result = JSON.parse(sql(`SET ROLE authenticated; SET test.uid='${member}'; SELECT public.okeyix_full_table_state('${table}');`));
    assert.equal(result.table.round_count,2);
    assert.deepEqual(result.players,source.players);
    assert.equal(result.table.current_turn,1);
    assert.equal(sql('SELECT md5(row_to_json(t)::text) FROM public.tables t; SELECT md5(row_to_json(p)::text) FROM public.table_players p;'),before);
    for (const prefix of ["SET ROLE anon;", "SET ROLE authenticated; SET test.uid='00000000-0000-0000-0000-000000000002';", "SET ROLE authenticated;"]) {
      const denied = spawnSync(pg,[...args,'-d',db],{input:`${prefix} SELECT public.okeyix_full_table_state('${table}');`,encoding:'utf8'});
      assert.notEqual(denied.status,0);
      assert.match(denied.stderr,/permission denied|GAME_CALLER_NOT_SEATED/);
    }
  } finally { sql(`DROP DATABASE ${db};`,'postgres'); }
});

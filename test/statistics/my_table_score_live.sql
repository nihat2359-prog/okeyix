-- LOCAL ONLY. Run after migrations 004 and 005. Test rows are rolled back.
\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
  IF current_database() NOT LIKE 'okeyix_stat_test_%'
    OR inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet
  THEN RAISE EXCEPTION 'LOCAL_TEST_DATABASE_REQUIRED'; END IF;
END $$;
CREATE FUNCTION pg_temp.score_check(t uuid,w integer,l integer) RETURNS void LANGUAGE plpgsql AS $$
DECLARE s jsonb;
BEGIN
  s:=public.okeyix_my_table_score(t);
  IF (s->>'wins')::int<>w OR (s->>'losses')::int<>l THEN
    RAISE EXCEPTION 'SCORE_MISMATCH expected %,%, got %',w,l,s;
  END IF;
END $$;

DO $$
DECLARE e bigint; t uuid:='00000000-0000-4000-8000-000000008100';
  me uuid:='00000000-0000-4000-8000-000000008001';
  opponent uuid:='00000000-0000-4000-8000-000000008002';
BEGIN
  -- Typed server receipts; no history/session has been projected yet.
  INSERT INTO okeyix_stat_private.events(table_id,round_no,seed,kind,league_id,entry_coin,occurred_at,reason)
  VALUES(t,1,'first-seed','begin','standard',100,now(),'test') RETURNING id INTO e;
  INSERT INTO okeyix_stat_private.event_players(event_id,user_id,seat_index,is_bot,coin_entry)
  VALUES(e,me,0,false,100),(e,opponent,1,true,100);
  INSERT INTO okeyix_stat_private.events(table_id,round_no,seed,kind,occurred_at,winner_user_id,reason)
  VALUES(t,1,'first-seed','complete',now(),me,'test') RETURNING id INTO e;
  INSERT INTO okeyix_stat_private.event_players(event_id,user_id,seat_index,is_bot)
  VALUES(e,me,0,false),(e,opponent,1,true);
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000008001',true);
SET LOCAL ROLE authenticated;
SELECT pg_temp.score_check('00000000-0000-4000-8000-000000008100',1,0);
SELECT pg_temp.score_check('00000000-0000-4000-8000-000000008200',0,0);
DO $$ BEGIN
  BEGIN PERFORM count(*) FROM okeyix_stat_private.events; RAISE EXCEPTION 'PRIVATE_TABLE_EXPOSED';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
-- Project begin only: the open permanent round must not hide a queued completion.
SELECT okeyix_stat_private.project_event(id) FROM okeyix_stat_private.events
WHERE table_id='00000000-0000-4000-8000-000000008100' AND kind='begin';
SET LOCAL ROLE authenticated;
SELECT pg_temp.score_check('00000000-0000-4000-8000-000000008100',1,0);
RESET ROLE;
-- Project complete but leave its processed marker pending: still exactly ONE win.
SELECT okeyix_stat_private.project_event(id) FROM okeyix_stat_private.events
WHERE table_id='00000000-0000-4000-8000-000000008100' AND kind='complete';
SET LOCAL ROLE authenticated;
SELECT pg_temp.score_check('00000000-0000-4000-8000-000000008100',1,0);
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000008002',true);
SELECT pg_temp.score_check('00000000-0000-4000-8000-000000008100',0,1);
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000008003',true);
SELECT pg_temp.score_check('00000000-0000-4000-8000-000000008100',0,0);
RESET ROLE;
UPDATE okeyix_stat_private.events SET processed_at=now()
WHERE table_id='00000000-0000-4000-8000-000000008100';
-- Starting another hand (or aborting it) must not count as a loss.
INSERT INTO okeyix_stat_private.events(table_id,round_no,seed,kind,occurred_at,reason)
VALUES('00000000-0000-4000-8000-000000008100',2,'next-seed','begin',now(),'test'),
('00000000-0000-4000-8000-000000008100',2,'next-seed','abort',now(),'test');
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000008001',true);
SET LOCAL ROLE authenticated;
SELECT pg_temp.score_check('00000000-0000-4000-8000-000000008100',1,0);
RESET ROLE;
-- A projected win and a new queued loss must coexist without resetting history.
INSERT INTO okeyix_stat_private.events(table_id,round_no,seed,kind,occurred_at,winner_user_id,reason)
VALUES('00000000-0000-4000-8000-000000008100',3,'third-seed','complete',now(),
  '00000000-0000-4000-8000-000000008002','test');
INSERT INTO okeyix_stat_private.event_players(event_id,user_id,seat_index,is_bot)
SELECT e.id,p.user_id,p.seat_index,p.is_bot FROM okeyix_stat_private.events e
CROSS JOIN (VALUES ('00000000-0000-4000-8000-000000008001'::uuid,0,false),
  ('00000000-0000-4000-8000-000000008002'::uuid,1,true)) p(user_id,seat_index,is_bot)
WHERE e.table_id='00000000-0000-4000-8000-000000008100' AND e.round_no=3;
SET LOCAL ROLE authenticated;
SELECT pg_temp.score_check('00000000-0000-4000-8000-000000008100',1,1);
SELECT set_config('request.jwt.claim.sub','',true);
DO $$ BEGIN
  BEGIN PERFORM public.okeyix_my_table_score(gen_random_uuid()); RAISE EXCEPTION 'MISSING_AUTH_ACCEPTED';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
DO $$ BEGIN
  IF has_function_privilege('anon','public.okeyix_my_table_score(uuid)','EXECUTE')
    OR has_function_privilege('service_role','public.okeyix_my_table_score(uuid)','EXECUTE')
    OR has_schema_privilege('authenticated','okeyix_stat_private','USAGE')
  THEN RAISE EXCEPTION 'SCORE_PRIVILEGES_BROADENED'; END IF;
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT 'live score before/after projection, deduplication and user isolation passed' AS result;
ROLLBACK;

-- LOCAL isolated fixture only; requires migration 008. Never run on production.
\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
  IF current_database() NOT LIKE 'okeyix_stat_test_%'
    OR inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet
  THEN RAISE EXCEPTION 'LOCAL_TEST_DATABASE_REQUIRED'; END IF;
END $$;
INSERT INTO public.users(id,username,is_bot,wins,losses) VALUES
('00000000-0000-4000-8000-000000008001','Profile fixture',false,500,200),
('00000000-0000-4000-8000-000000008002','Profile bot fixture',true,0,0),
('00000000-0000-4000-8000-000000008003','Empty profile fixture',false,0,0);
CREATE FUNCTION pg_temp.check_profile(target uuid,w int,l int,n int,o int,d int,b int)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE x jsonb;
BEGIN
  x:=public.okeyix_profile_statistics(target);
  IF (x-ARRAY['career_wins','career_losses','previous_wins'])<>jsonb_build_object('wins',w,'losses',l,'normal_wins',n,
    'okey_wins',o,'double_wins',d,'okey_double_wins',b)
  THEN RAISE EXCEPTION 'PROFILE_COUNTS_MISMATCH: %',x; END IF;
  IF (x->>'previous_wins')::bigint IS DISTINCT FROM
    (CASE WHEN target='00000000-0000-4000-8000-000000008001'::uuid THEN 500 ELSE 0 END)
    OR (x->>'career_wins')::bigint<>(x->>'previous_wins')::bigint+w
  THEN RAISE EXCEPTION 'CAREER_BREAKDOWN_MISMATCH'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000008003',true);
SET LOCAL ROLE authenticated;
SELECT pg_temp.check_profile('00000000-0000-4000-8000-000000008001',0,0,0,0,0,0);
DO $$ BEGIN
  BEGIN PERFORM public.okeyix_profile_statistics(NULL); RAISE EXCEPTION 'NULL_ACCEPTED';
    EXCEPTION WHEN null_value_not_allowed THEN NULL; END;
  BEGIN PERFORM public.okeyix_profile_statistics('00000000-0000-4000-8000-000000008099');
    RAISE EXCEPTION 'MISSING_ACCEPTED'; EXCEPTION WHEN no_data_found THEN NULL; END;
END $$;
RESET ROLE;
DO $$ DECLARE e bigint; i int;
  t uuid:='00000000-0000-4000-8000-000000008100';
  a uuid:='00000000-0000-4000-8000-000000008001';
  b uuid:='00000000-0000-4000-8000-000000008002';
BEGIN
  FOR i IN 1..7 LOOP
    INSERT INTO okeyix_stat_private.events(table_id,round_no,seed,kind,league_id,entry_coin,occurred_at,reason)
    VALUES(t,i,'profile-'||i,'begin','standard',100,now(),'test') RETURNING id INTO e;
    INSERT INTO okeyix_stat_private.event_players(event_id,user_id,seat_index,is_bot,coin_entry)
    VALUES(e,a,0,false,100),(e,b,1,true,100);
    IF i<=5 THEN
      INSERT INTO okeyix_stat_private.events(table_id,round_no,seed,kind,occurred_at,
        winner_user_id,is_okey,is_double,reason)
      VALUES(t,i,'profile-'||i,'complete',now(),CASE WHEN i=5 THEN b ELSE a END,
        i IN (2,4),i IN (3,4),'test') RETURNING id INTO e;
      INSERT INTO okeyix_stat_private.event_players(event_id,user_id,seat_index,is_bot)
      VALUES(e,a,0,false),(e,b,1,true);
    ELSIF i=6 THEN
      INSERT INTO okeyix_stat_private.events(table_id,round_no,seed,kind,occurred_at,reason)
      VALUES(t,i,'profile-'||i,'abort',now(),'test');
    END IF;
  END LOOP;
END $$;
-- Simulate the existing writer's counters; the statistics reader never updates them.
UPDATE public.users SET wins=504,losses=201 WHERE id='00000000-0000-4000-8000-000000008001';
UPDATE public.users SET wins=1,losses=4 WHERE id='00000000-0000-4000-8000-000000008002';
-- Another authenticated player can read only aggregates, before cron.
SET LOCAL ROLE authenticated;
SELECT pg_temp.check_profile('00000000-0000-4000-8000-000000008001',4,1,1,2,2,1);
SELECT pg_temp.check_profile('00000000-0000-4000-8000-000000008002',1,4,1,0,0,0);
RESET ROLE;
SELECT okeyix_stat_private.process_events(100);
DO $$ BEGIN
  IF EXISTS(SELECT 1 FROM okeyix_stat_private.events
    WHERE table_id='00000000-0000-4000-8000-000000008100' AND processed_at IS NULL)
  THEN RAISE EXCEPTION 'UNPROCESSED_FIXTURE'; END IF;
END $$;
SET LOCAL ROLE authenticated;
SELECT pg_temp.check_profile('00000000-0000-4000-8000-000000008001',4,1,1,2,2,1);
SELECT pg_temp.check_profile('00000000-0000-4000-8000-000000008003',0,0,0,0,0,0);
-- Source table does not exist; history remains readable after cleanup.
DO $$ BEGIN
  BEGIN PERFORM count(*) FROM okeyix_stat_private.events; RAISE EXCEPTION 'PRIVATE_ACCESS';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
SELECT set_config('request.jwt.claim.sub','',true);
DO $$ BEGIN
  BEGIN PERFORM public.okeyix_profile_statistics('00000000-0000-4000-8000-000000008001');
    RAISE EXCEPTION 'NO_AUTH_ACCEPTED'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
DO $$ BEGIN
  IF has_function_privilege('anon','public.okeyix_profile_statistics(uuid)','EXECUTE')
    OR has_function_privilege('service_role','public.okeyix_profile_statistics(uuid)','EXECUTE')
    OR has_schema_privilege('authenticated','okeyix_stat_private','USAGE')
  THEN RAISE EXCEPTION 'PROFILE_PRIVILEGES_WRONG'; END IF;
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
-- Missing or conflicting counters must not fabricate a negative/zero old history.
UPDATE public.users SET wins=NULL WHERE id='00000000-0000-4000-8000-000000008001';
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000008003',true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  IF public.okeyix_profile_statistics('00000000-0000-4000-8000-000000008001')->'previous_wins'<>'null'::jsonb
  THEN RAISE EXCEPTION 'UNKNOWN_COUNTER_FABRICATED'; END IF;
END $$;
RESET ROLE;
UPDATE public.users SET wins=1 WHERE id='00000000-0000-4000-8000-000000008001';
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  IF public.okeyix_profile_statistics('00000000-0000-4000-8000-000000008001')->'previous_wins'<>'null'::jsonb
  THEN RAISE EXCEPTION 'NEGATIVE_HISTORY_FABRICATED'; END IF;
END $$;
RESET ROLE;
SELECT 'profile aggregates, overlap, bot, empty, abort, pending/projected parity and privacy passed' AS result;
ROLLBACK;

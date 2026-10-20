-- Isolated LOCAL fixture only. Never run on production. Requires migration 010.
\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
  IF current_database() NOT LIKE 'okeyix_stat_test_%' OR inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet
  THEN RAISE EXCEPTION 'LOCAL_TEST_DATABASE_REQUIRED'; END IF;
END $$;
CREATE TABLE IF NOT EXISTS public.leagues(id text PRIMARY KEY,name text,min_rating integer,max_rating integer);
INSERT INTO public.leagues VALUES('comparison-low','Fixture low',0,1999),('comparison-high','Fixture high',2000,NULL);
INSERT INTO public.users(id,username,is_bot,wins,losses) VALUES
('00000000-0000-4000-8000-000000009001','Alpha',false,9999,8888),
('00000000-0000-4000-8000-000000009002','Beta',false,7777,6666),
('00000000-0000-4000-8000-000000009003','Other bot',true,0,0),
('00000000-0000-4000-8000-000000009004','Never met',false,0,0);
INSERT INTO public.profiles(id,username,rating) VALUES
('00000000-0000-4000-8000-000000009001','Alpha',1500),
('00000000-0000-4000-8000-000000009002','Beta',2500);
CREATE FUNCTION pg_temp.check_comparison() RETURNS void LANGUAGE plpgsql AS $$
DECLARE x jsonb;
BEGIN
  x:=public.okeyix_compare_player('00000000-0000-4000-8000-000000009002');
  IF (x->>'left_wins')::int<>2 OR (x->>'right_wins')::int<>1
    OR x->>'scope'<>'head_to_head'
    OR (x->'left_player'->>'wins')::int<>2 OR (x->'left_player'->>'losses')::int<>1
    OR (x->'right_player'->>'wins')::int<>1 OR (x->'right_player'->>'losses')::int<>2
    OR (x->'left_player'->>'normal_wins')::int<>1
    OR (x->'left_player'->>'okey_wins')::int<>1
    OR (x->'left_player'->>'double_wins')::int<>1
    OR (x->'left_player'->>'okey_double_wins')::int<>1
    OR x->'left_player'->>'league'<>'Fixture low'
    OR x->'right_player'->>'league'<>'Fixture high'
    OR (x->'left_player') ? 'career_wins'
  THEN RAISE EXCEPTION 'COMPARISON_MISMATCH: %',x; END IF;
END $$;
DO $$ DECLARE i int; e bigint; a uuid:='00000000-0000-4000-8000-000000009001';
  b uuid:='00000000-0000-4000-8000-000000009002'; c uuid:='00000000-0000-4000-8000-000000009003';
  t uuid:='00000000-0000-4000-8000-000000009100'; first_player uuid; second_player uuid; winner uuid;
BEGIN
  FOR i IN 1..7 LOOP
    first_player:=CASE WHEN i=4 THEN b ELSE a END;
    second_player:=CASE WHEN i IN (3,4,6) THEN c ELSE b END;
    winner:=CASE WHEN i=2 THEN b WHEN i=6 THEN c ELSE first_player END;
    INSERT INTO okeyix_stat_private.events(table_id,round_no,seed,kind,league_id,entry_coin,occurred_at,reason)
    VALUES(t,i,'compare-'||i,'begin','fixture',100,now(),'test') RETURNING id INTO e;
    INSERT INTO okeyix_stat_private.event_players(event_id,user_id,seat_index,is_bot)
    VALUES(e,first_player,0,false),(e,second_player,1,second_player=c);
    IF i=7 THEN
      INSERT INTO okeyix_stat_private.events(table_id,round_no,seed,kind,occurred_at,reason)
      VALUES(t,i,'compare-'||i,'abort',now(),'test');
    ELSE
      INSERT INTO okeyix_stat_private.events(table_id,round_no,seed,kind,occurred_at,winner_user_id,is_okey,is_double,reason)
      VALUES(t,i,'compare-'||i,'complete',now(),winner,i IN (2,4,5),i IN (3,4,5),'test') RETURNING id INTO e;
      INSERT INTO okeyix_stat_private.event_players(event_id,user_id,seat_index,is_bot)
      VALUES(e,first_player,0,false),(e,second_player,1,second_player=c);
    END IF;
  END LOOP;
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000009001',true);
SET LOCAL ROLE authenticated;
SELECT pg_temp.check_comparison();
DO $$ DECLARE x jsonb;
BEGIN
  x:=public.okeyix_compare_player('00000000-0000-4000-8000-000000009004');
  IF (x->>'left_wins')::int<>0 OR (x->>'right_wins')::int<>0
    OR (x->'left_player'->>'wins')::int<>0 OR (x->'right_player'->>'wins')::int<>0
    OR (x->'left_player'->>'normal_wins')::int<>0
  THEN RAISE EXCEPTION 'EMPTY_COMPARISON_MISMATCH'; END IF;
  x:=public.okeyix_compare_player('00000000-0000-4000-8000-000000009003');
  IF (x->>'left_wins')::int<>1 OR (x->>'right_wins')::int<>1
    OR (x->'right_player'->>'wins')::int<>1 OR (x->'right_player'->>'losses')::int<>1
  THEN RAISE EXCEPTION 'BOT_TIE_MISMATCH'; END IF;
  BEGIN PERFORM public.okeyix_compare_player(auth.uid()); RAISE EXCEPTION 'SELF_ALLOWED';
    EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN PERFORM public.okeyix_compare_player(NULL); RAISE EXCEPTION 'NULL_ALLOWED';
    EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
END $$;
RESET ROLE;
SELECT okeyix_stat_private.process_events(100);
DO $$ BEGIN
  IF EXISTS(SELECT 1 FROM okeyix_stat_private.events WHERE table_id='00000000-0000-4000-8000-000000009100' AND processed_at IS NULL)
  THEN RAISE EXCEPTION 'FIXTURE_PROJECTION_FAILED'; END IF;
END $$;
SET LOCAL ROLE authenticated;
SELECT pg_temp.check_comparison();
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000009002',true);
DO $$ DECLARE x jsonb;
BEGIN
  x:=public.okeyix_compare_player('00000000-0000-4000-8000-000000009001');
  IF (x->>'left_wins')::int<>1 OR (x->>'right_wins')::int<>2 THEN RAISE EXCEPTION 'REVERSE_MISMATCH'; END IF;
  BEGIN PERFORM count(*) FROM okeyix_stat_private.events; RAISE EXCEPTION 'PRIVATE_READ_ALLOWED';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
SELECT set_config('request.jwt.claim.sub','',true);
DO $$ BEGIN
  BEGIN PERFORM public.okeyix_compare_player('00000000-0000-4000-8000-000000009001');
    RAISE EXCEPTION 'NO_AUTH_ALLOWED'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
DO $$ BEGIN
  IF has_function_privilege('anon','public.okeyix_compare_player(uuid)','EXECUTE')
    OR has_function_privilege('service_role','public.okeyix_compare_player(uuid)','EXECUTE')
  THEN RAISE EXCEPTION 'PRIVILEGES_WRONG'; END IF;
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT 'comparison opponents, legacy exclusion, pending/projected parity, flags, bots, league, empty and auth passed' AS result;
ROLLBACK;

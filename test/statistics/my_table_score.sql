-- LOCAL fixture only. Install migration 004 (and optionally 005) first. All test rows are rolled back.
\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
  IF current_database() NOT LIKE 'okeyix_stat_test_%' OR inet_server_addr()<>'127.0.0.1'::inet
    THEN RAISE EXCEPTION 'LOCAL_TEST_DATABASE_REQUIRED'; END IF;
END $$;
DO $$
DECLARE s uuid; r uuid; t uuid; w uuid; i integer; j integer;
  me uuid:='00000000-0000-4000-8000-000000009001';
  other_user uuid:='00000000-0000-4000-8000-000000009002';
BEGIN
  FOR j IN 1..2 LOOP
    t:=CASE WHEN j=1 THEN '00000000-0000-4000-8000-000000009100'::uuid
      ELSE '00000000-0000-4000-8000-000000009200'::uuid END;
    INSERT INTO public.okeyix_stat_sessions(table_id,league_id,entry_coin,started_at)
    VALUES(t,'standard',100,now()) RETURNING id INTO s;
    FOR i IN 1..4 LOOP
      INSERT INTO public.okeyix_stat_rounds(session_id,source_start_key,round_no,started_at)
      VALUES(s,t::text||':'||i,i,now()) RETURNING id INTO r;
      INSERT INTO public.okeyix_stat_players(round_id,user_id,round_started_at,seat_index,is_bot)
      VALUES(r,me,now(),0,false),(r,other_user,now(),1,true);
      IF i<=3 THEN
        w:=CASE WHEN j=1 AND i<=2 THEN me ELSE other_user END;
        UPDATE public.okeyix_stat_players SET outcome=CASE WHEN user_id=w THEN 'win' ELSE 'loss' END WHERE round_id=r;
        UPDATE public.okeyix_stat_rounds SET status='completed',winner_user_id=w,finished_at=now() WHERE id=r;
      ELSE
        UPDATE public.okeyix_stat_players SET outcome='aborted' WHERE round_id=r;
        UPDATE public.okeyix_stat_rounds SET status='aborted',finished_at=now() WHERE id=r;
      END IF;
    END LOOP;
  END LOOP;
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000009001',true);
SELECT set_config('request.jwt.claim.role','authenticated',true);
SET LOCAL ROLE authenticated;
DO $$ DECLARE score jsonb;
BEGIN
  score:=public.okeyix_my_table_score('00000000-0000-4000-8000-000000009100');
  IF (score->>'wins')::int<>2 OR (score->>'losses')::int<>1 THEN RAISE EXCEPTION 'OWN_SCORE_WRONG'; END IF;
  score:=public.okeyix_my_table_score('00000000-0000-4000-8000-000000009200');
  IF (score->>'wins')::int<>0 OR (score->>'losses')::int<>3 THEN RAISE EXCEPTION 'TABLES_MIXED'; END IF;
  score:=public.okeyix_my_table_score(gen_random_uuid());
  IF (score->>'wins')::int<>0 OR (score->>'losses')::int<>0 THEN RAISE EXCEPTION 'EMPTY_SCORE_WRONG'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000009002',true);
DO $$ DECLARE score jsonb;
BEGIN
  score:=public.okeyix_my_table_score('00000000-0000-4000-8000-000000009100');
  IF (score->>'wins')::int<>1 OR (score->>'losses')::int<>2 THEN RAISE EXCEPTION 'OTHER_USER_SCORE_LEAK'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000009003',true);
DO $$ DECLARE score jsonb;
BEGIN
  score:=public.okeyix_my_table_score('00000000-0000-4000-8000-000000009100');
  IF (score->>'wins')::int<>0 OR (score->>'losses')::int<>0 THEN RAISE EXCEPTION 'NONPARTICIPANT_SCORE_LEAK'; END IF;
END $$;
RESET ROLE;
DO $$ BEGIN
  IF has_function_privilege('anon','public.okeyix_my_table_score(uuid)','EXECUTE')
    OR NOT (SELECT pg_get_userbyid(proowner)='postgres'
      AND proconfig @> ARRAY['search_path=pg_catalog, pg_temp']
      FROM pg_proc WHERE oid='public.okeyix_my_table_score(uuid)'::regprocedure)
    THEN RAISE EXCEPTION 'SCORE_PERMISSIONS_WRONG'; END IF;
END $$;
SELECT 'own score, session separation, aborted filtering, RLS and empty defaults passed' AS result;
ROLLBACK;

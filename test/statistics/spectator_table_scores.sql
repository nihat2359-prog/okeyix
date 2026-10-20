-- LOCAL fixture only; requires migration 006. No production data, ends ROLLBACK.
\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
  IF current_database() NOT LIKE 'okeyix_stat_test_%' OR inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet
    THEN RAISE EXCEPTION 'LOCAL_TEST_DATABASE_REQUIRED'; END IF;
END $$;
INSERT INTO public.users(id,username,is_bot) VALUES
('00000000-0000-4000-8000-000000007001','Local player',false),
('00000000-0000-4000-8000-000000007002','Local bot',true),
('00000000-0000-4000-8000-000000007003','Local viewer',false),
('00000000-0000-4000-8000-000000007004','Replacement',false);
INSERT INTO public.tables(id,league_id,created_by,max_players,entry_coin,min_rounds) VALUES
('00000000-0000-4000-8000-000000007100','standard','00000000-0000-4000-8000-000000007001',2,100,1),
('00000000-0000-4000-8000-000000007200','standard','00000000-0000-4000-8000-000000007001',2,100,1);
INSERT INTO public.table_players(table_id,user_id,seat_index) VALUES
('00000000-0000-4000-8000-000000007100','00000000-0000-4000-8000-000000007001',0),
('00000000-0000-4000-8000-000000007100','00000000-0000-4000-8000-000000007002',1);
INSERT INTO public.table_spectators(table_id,user_id) VALUES
('00000000-0000-4000-8000-000000007100','00000000-0000-4000-8000-000000007003');
CREATE FUNCTION pg_temp.check_scores(w0 int,l0 int,w1 int,l1 int) RETURNS void LANGUAGE plpgsql AS $$
DECLARE x jsonb;
BEGIN
  x:=public.okeyix_spectator_table_scores('00000000-0000-4000-8000-000000007100')->'players';
  IF jsonb_array_length(x)<>2 OR (x->0->>'seat_index')::int<>0 OR (x->1->>'seat_index')::int<>1
    OR (x->0->>'wins')::int<>w0 OR (x->0->>'losses')::int<>l0
    OR (x->1->>'wins')::int<>w1 OR (x->1->>'losses')::int<>l1
  THEN RAISE EXCEPTION 'SPECTATOR_SCORE_MISMATCH'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000007003',true);
SET LOCAL ROLE authenticated;
SELECT pg_temp.check_scores(0,0,0,0);
DO $$ BEGIN
  BEGIN PERFORM public.okeyix_spectator_table_scores('00000000-0000-4000-8000-000000007200');
    RAISE EXCEPTION 'OTHER_TABLE_ACCESS'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
UPDATE public.tables SET spectators_enabled=false WHERE id='00000000-0000-4000-8000-000000007100';
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  BEGIN PERFORM public.okeyix_spectator_table_scores('00000000-0000-4000-8000-000000007100');
    RAISE EXCEPTION 'DISABLED_SPECTATOR_ACCESS'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
UPDATE public.tables SET spectators_enabled=true WHERE id='00000000-0000-4000-8000-000000007100';
-- Confirmed server events are visible BEFORE any cron projection.
DO $$ DECLARE t uuid:='00000000-0000-4000-8000-000000007100'; e bigint; i int;
  a uuid:='00000000-0000-4000-8000-000000007001'; b uuid:='00000000-0000-4000-8000-000000007002';
BEGIN
  FOR i IN 1..3 LOOP
    INSERT INTO okeyix_stat_private.events(table_id,round_no,seed,kind,league_id,entry_coin,occurred_at,reason)
    VALUES(t,i,'spectator-'||i,'begin','standard',100,now(),'test') RETURNING id INTO e;
    INSERT INTO okeyix_stat_private.event_players(event_id,user_id,seat_index,is_bot,coin_entry)
    VALUES(e,a,0,false,100),(e,b,1,true,100);
    INSERT INTO okeyix_stat_private.events(table_id,round_no,seed,kind,occurred_at,winner_user_id,reason)
    VALUES(t,i,'spectator-'||i,'complete',now(),CASE WHEN i=3 THEN b ELSE a END,'test') RETURNING id INTO e;
    INSERT INTO okeyix_stat_private.event_players(event_id,user_id,seat_index,is_bot)
    VALUES(e,a,0,false),(e,b,1,true);
  END LOOP;
END $$;
SET LOCAL ROLE authenticated;
SELECT pg_temp.check_scores(2,1,1,2);
RESET ROLE;
SELECT okeyix_stat_private.process_events(100);
SET LOCAL ROLE authenticated;
SELECT pg_temp.check_scores(2,1,1,2);
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000007004',true);
DO $$ BEGIN
  BEGIN PERFORM public.okeyix_spectator_table_scores('00000000-0000-4000-8000-000000007100');
    RAISE EXCEPTION 'OUTSIDER_ACCESS'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
UPDATE public.table_players SET user_id='00000000-0000-4000-8000-000000007004'
WHERE table_id='00000000-0000-4000-8000-000000007100' AND seat_index=1;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000007003',true);
SET LOCAL ROLE authenticated;
SELECT pg_temp.check_scores(2,1,0,0);
DO $$ BEGIN
  BEGIN PERFORM count(*) FROM okeyix_stat_private.events; RAISE EXCEPTION 'PRIVATE_ACCESS';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
DO $$ BEGIN
  IF has_function_privilege('anon','public.okeyix_spectator_table_scores(uuid)','EXECUTE')
    OR has_schema_privilege('authenticated','okeyix_stat_private','USAGE')
  THEN RAISE EXCEPTION 'SPECTATOR_PRIVILEGES_WRONG'; END IF;
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT 'spectator membership, live scores, deduplication, seat replacement and privacy passed' AS result;
ROLLBACK;

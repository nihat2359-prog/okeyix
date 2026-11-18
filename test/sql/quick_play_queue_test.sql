\set ON_ERROR_STOP on
CREATE FUNCTION pg_temp.as_user(i integer) RETURNS void LANGUAGE sql AS $$
 SELECT set_config('request.jwt.claim.sub',('00000000-0000-0000-0000-'||lpad(i::text,12,'0')),false);
$$;
CREATE FUNCTION pg_temp.check_that(ok boolean,message text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION '%',message; END IF; END $$;

BEGIN;
TRUNCATE okeyix_match_private.requests,okeyix_quick_private.requests,public.table_players,public.tables;
DO $$ DECLARE r jsonb; tid uuid; BEGIN
 PERFORM pg_temp.as_user(1);
 INSERT INTO public.tables(league_id,max_players,entry_coin,status,created_by)
 VALUES('standard',2,1000,'waiting',auth.uid()) RETURNING id INTO tid;
 INSERT INTO public.table_players(table_id,user_id,seat_index) VALUES(tid,auth.uid(),0);
 PERFORM pg_temp.as_user(2);
 r:=public.okeyix_quick_play_v2('10000000-0000-0000-0000-000000000002','start');
 PERFORM pg_temp.check_that(r->>'state'='ready' AND (r->>'table_id')::uuid=tid AND NOT (r->>'bot')::boolean,'INSTANT_HUMAN_JOIN');
END $$;
ROLLBACK;

BEGIN;
TRUNCATE okeyix_match_private.requests,okeyix_quick_private.requests,public.table_players,public.tables;
DO $$ DECLARE a jsonb; b jsonb; c jsonb; BEGIN
 PERFORM pg_temp.as_user(1);
 a:=public.okeyix_quick_play_v2('10000000-0000-0000-0000-000000000001','start');
 PERFORM pg_temp.check_that(a->>'state'='waiting' AND (a->>'remaining_ms')::int<=10000,'INITIAL_WAIT');
 PERFORM pg_temp.check_that(NOT EXISTS(SELECT 1 FROM public.tables) AND NOT EXISTS(SELECT 1 FROM public.table_players),'WAIT_HAS_NO_SEAT');
 -- Repeated start preserves its deadline; another request cannot double-enqueue.
 a:=public.okeyix_quick_play_v2('10000000-0000-0000-0000-000000000001','start');
 BEGIN
  PERFORM public.okeyix_quick_play_v2('20000000-0000-0000-0000-000000000001','start');
  RAISE EXCEPTION 'DOUBLE_REQUEST_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'QUICK_PLAY_ALREADY_WAITING' THEN RAISE; END IF; END;
 PERFORM pg_temp.as_user(2);
 b:=public.okeyix_quick_play_v2('10000000-0000-0000-0000-000000000002','start');
 PERFORM pg_temp.check_that(b->>'state'='ready' AND NOT (b->>'bot')::boolean,'SECOND_HUMAN_MATCH');
 PERFORM pg_temp.as_user(1);
 c:=public.okeyix_quick_play_v2('10000000-0000-0000-0000-000000000001','refresh');
 PERFORM pg_temp.check_that(c->>'table_id'=b->>'table_id' AND (c->>'is_creator')::boolean,'SAME_ATOMIC_TABLE');
 a:=public.okeyix_quick_play_v2('10000000-0000-0000-0000-000000000001','cancel');
 PERFORM pg_temp.check_that(a=c,'COMMITTED_MATCH_WINS_CANCEL');
 PERFORM pg_temp.check_that((SELECT count(*) FROM public.tables)=1 AND (SELECT count(*) FROM public.table_players)=2,'EXACTLY_TWO_SEATS');
 PERFORM pg_temp.check_that(NOT EXISTS(SELECT 1 FROM public.profiles WHERE coins<>20000000),'NO_QUEUE_DEBIT');
END $$;
ROLLBACK;

BEGIN;
TRUNCATE okeyix_match_private.requests,okeyix_quick_private.requests,public.table_players,public.tables;
DO $$ DECLARE r jsonb; started timestamptz:=clock_timestamp(); BEGIN
 PERFORM pg_temp.as_user(1);
 r:=public.okeyix_quick_play_v2('10000000-0000-0000-0000-000000000001','start');
 FOR i IN 1..10 LOOP
  PERFORM pg_sleep(1);
  r:=public.okeyix_quick_play_v2('10000000-0000-0000-0000-000000000001','refresh');
  IF i<10 THEN PERFORM pg_temp.check_that(r->>'state'='waiting','BOT_TOO_EARLY'); END IF;
 END LOOP;
 PERFORM pg_temp.check_that(r->>'state'='ready' AND (r->>'bot')::boolean AND clock_timestamp()-started>=interval '10 seconds','BOT_AFTER_REAL_DEADLINE');
 PERFORM pg_temp.check_that((SELECT count(*) FROM public.tables)=1,'ONE_BOT_TABLE');
 PERFORM pg_temp.check_that(public.okeyix_quick_play_v2('10000000-0000-0000-0000-000000000001','refresh')=r,'BOT_RETRY_IDEMPOTENT');
 PERFORM pg_temp.check_that(NOT EXISTS(SELECT 1 FROM public.profiles WHERE coins<>20000000),'NO_NEW_FEE_PATH');
END $$;
ROLLBACK;

BEGIN;
TRUNCATE okeyix_match_private.requests,okeyix_quick_private.requests,public.table_players,public.tables;
DO $$ DECLARE r jsonb; BEGIN
 PERFORM pg_temp.as_user(1);
 r:=public.okeyix_quick_play_v2('10000000-0000-0000-0000-000000000001','cancel');
 PERFORM pg_temp.check_that(public.okeyix_quick_play_v2('10000000-0000-0000-0000-000000000001','start')=r,'CANCEL_BEFORE_START');
 r:=public.okeyix_quick_play_v2('20000000-0000-0000-0000-000000000001','start');
 r:=public.okeyix_quick_play_v2('20000000-0000-0000-0000-000000000001','cancel');
 PERFORM pg_temp.check_that(r->>'state'='cancelled' AND NOT EXISTS(SELECT 1 FROM public.tables),'CANCEL_NO_GHOST_SEAT');
 r:=public.okeyix_quick_play_v2('30000000-0000-0000-0000-000000000001','start');
 UPDATE okeyix_match_private.requests SET lease_until=clock_timestamp()-interval '1 second' WHERE state='waiting';
 r:=public.okeyix_quick_play_v2('30000000-0000-0000-0000-000000000001','refresh');
 PERFORM pg_temp.check_that(r->>'state'='cancelled' AND NOT EXISTS(SELECT 1 FROM public.tables),'DISCONNECT_EXPIRES_WITHOUT_SEATS');
END $$;
ROLLBACK;

BEGIN;
TRUNCATE okeyix_match_private.requests,okeyix_quick_private.requests,public.table_players,public.tables;
DO $$ DECLARE r jsonb; BEGIN
 PERFORM pg_temp.as_user(1);
 UPDATE public.profiles SET rating=90 WHERE id=auth.uid();
 r:=public.okeyix_quick_play_v2('30000000-0000-0000-0000-000000000001','start');
 UPDATE okeyix_match_private.requests SET wait_until=clock_timestamp()-interval '1 second' WHERE user_id=auth.uid();
 r:=public.okeyix_quick_play_v2('30000000-0000-0000-0000-000000000001','refresh');
 PERFORM pg_temp.check_that(r->>'code'='HUMAN_ONLY_LEAGUE' AND NOT EXISTS(SELECT 1 FROM public.tables),'GOLD_NO_BOT');
 UPDATE public.profiles SET rating=200 WHERE id=auth.uid();
 r:=public.okeyix_quick_play_v2('10000000-0000-0000-0000-000000000001','start');
 UPDATE okeyix_match_private.requests SET wait_until=clock_timestamp()-interval '1 second' WHERE user_id=auth.uid();
 r:=public.okeyix_quick_play_v2('10000000-0000-0000-0000-000000000001','refresh');
 PERFORM pg_temp.check_that(r->>'state'='error' AND r->>'code'='HUMAN_ONLY_LEAGUE' AND NOT EXISTS(SELECT 1 FROM public.tables),'UPPER_LEAGUE_NO_BOT');
 -- Humans can still pair in an upper league, using its actual fixture rules.
 r:=public.okeyix_quick_play_v2('20000000-0000-0000-0000-000000000001','start');
 PERFORM pg_temp.as_user(2);
 UPDATE public.profiles SET rating=200 WHERE id=auth.uid();
 r:=public.okeyix_quick_play_v2('20000000-0000-0000-0000-000000000002','start');
 PERFORM pg_temp.check_that(r->>'state'='ready' AND r->>'league_id'='elite' AND NOT (r->>'bot')::boolean,'UPPER_LEAGUE_HUMANS_ALLOWED');
END $$;
ROLLBACK;

BEGIN;
TRUNCATE okeyix_match_private.requests,okeyix_quick_private.requests,public.table_players,public.tables;
DO $$ DECLARE r jsonb; BEGIN
 PERFORM pg_temp.as_user(1);
 r:=public.okeyix_quick_play_v2('10000000-0000-0000-0000-000000000001','start');
 -- A final affordable human candidate overrides bot fallback at the deadline.
 UPDATE okeyix_match_private.requests SET wait_until=clock_timestamp()-interval '1 second' WHERE user_id=auth.uid();
 PERFORM pg_temp.as_user(2);
 UPDATE public.profiles SET rating=0,coins=1000 WHERE id=auth.uid();
 r:=public.okeyix_quick_play_v2('10000000-0000-0000-0000-000000000002','start');
 PERFORM pg_temp.as_user(1);
 r:=public.okeyix_quick_play_v2('10000000-0000-0000-0000-000000000001','refresh');
 PERFORM pg_temp.check_that(r->>'state'='ready' AND NOT (r->>'bot')::boolean AND r->>'league_id'='standard','FINAL_HUMAN_CHECK_AND_BOTH_ACCESS');
END $$;
ROLLBACK;

BEGIN;
TRUNCATE okeyix_match_private.requests,okeyix_quick_private.requests,public.table_players,public.tables;
DO $$ DECLARE r jsonb; BEGIN
 PERFORM pg_temp.as_user(1);
 r:=public.okeyix_quick_play_v2('10000000-0000-0000-0000-000000000001','start');
 UPDATE public.profiles SET coins=999 WHERE id=auth.uid();
 PERFORM pg_temp.as_user(2);
 r:=public.okeyix_quick_play_v2('10000000-0000-0000-0000-000000000002','start');
 PERFORM pg_temp.check_that(r->>'state'='waiting' AND NOT EXISTS(SELECT 1 FROM public.tables),'RECHECK_PEER_BALANCE');
 -- Once the first waiter's balance is restored the same live request can pair.
 UPDATE public.profiles SET coins=20000000 WHERE id='00000000-0000-0000-0000-000000000001';
 r:=public.okeyix_quick_play_v2('10000000-0000-0000-0000-000000000002','refresh');
 PERFORM pg_temp.check_that(r->>'state'='ready' AND NOT (r->>'bot')::boolean,'PAIR_AFTER_RECHECK');
END $$;
ROLLBACK;

SELECT pg_temp.check_that(NOT has_schema_privilege('authenticated','okeyix_match_private','USAGE'),'QUEUE_PRIVATE');
SELECT pg_temp.check_that(has_function_privilege('authenticated','public.okeyix_quick_play_v2(uuid,text)','EXECUTE'),'AUTH_RPC_ALLOWED');
SELECT pg_temp.check_that(NOT has_function_privilege('anon','public.okeyix_quick_play_v2(uuid,text)','EXECUTE'),'ANON_RPC_DENIED');
SELECT 'QUICK_PLAY_QUEUE_TESTS_PASSED';

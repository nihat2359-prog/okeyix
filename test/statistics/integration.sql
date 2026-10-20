-- LOCAL ONLY. prepare_fixture.ps1 + migrations 001/002 must already be installed.
-- Deterministic solver stubs isolate orchestration; NOT a game-rule validation test.
\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
  IF current_database() NOT LIKE 'okeyix_stat_test_%'
    OR inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet
  THEN RAISE EXCEPTION 'LOCAL_TEST_DATABASE_REQUIRED'; END IF;
END $$;
CREATE FUNCTION pg_temp.reject_capture() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'injected local capture failure'; END $$;
CREATE FUNCTION pg_temp.check_it(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS NOT TRUE THEN RAISE EXCEPTION 'FAILED: %',label; END IF; END $$;
CREATE FUNCTION pg_temp.reject_projection() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.source_start_key LIKE current_setting('test.reject_table')||':%'
    THEN RAISE EXCEPTION 'injected local projection failure'; END IF;
  RETURN NEW;
END $$;
CREATE FUNCTION pg_temp.make_table(bot boolean DEFAULT false,n integer DEFAULT 2) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE t uuid:=gen_random_uuid(); u uuid; creator uuid; i integer;
BEGIN
  creator:=gen_random_uuid();
  INSERT INTO public.tables(id,league_id,created_by,max_players,entry_coin,min_rounds)
  VALUES(t,'standard',creator,n,100,1);
  FOR i IN 0..n-1 LOOP
    u:=CASE WHEN i=0 THEN creator ELSE gen_random_uuid() END;
    INSERT INTO public.users(id,is_bot) VALUES(u,bot AND i=1);
    INSERT INTO public.profiles(id,username,coins,rating) VALUES(u,'Local Test',10000,1200);
    INSERT INTO public.table_players(table_id,user_id,seat_index) VALUES(t,u,i);
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub',creator::text,true);
  PERFORM set_config('request.jwt.claim.role','authenticated',true);
  RETURN t;
END $$;
CREATE FUNCTION pg_temp.deal(t uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  -- The original engine's fixed-name temp table lives until COMMIT. Test multiple
  -- independent RPC transactions in one rollback fixture without changing it.
  DROP TABLE IF EXISTS pg_temp._tmp_shuffled_tiles;
  r:=public.start_game(t);
  RETURN r;
END $$;
CREATE FUNCTION pg_temp.finish_hand(t uuid,u uuid,okey boolean DEFAULT false,doubles boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_hand jsonb; slots jsonb; last_tile jsonb;
BEGIN
  SELECT jsonb_agg(jsonb_build_object('id','fixture-'||i,'is_joker',okey AND i=15,'is_fake_joker',false))
  INTO v_hand FROM generate_series(1,15) i;
  SELECT jsonb_agg(CASE WHEN i<=14 THEN jsonb_build_object('tile',v_hand->(i-1)) ELSE '{}'::jsonb END)
  INTO slots FROM generate_series(1,26) i;
  last_tile:=v_hand->14;
  UPDATE public.table_players SET hand=v_hand,is_double_mode=doubles WHERE table_id=t AND user_id=u;
  RETURN public.game_finish(t,u,slots,last_tile);
END $$;

DO $tests$
DECLARE
  t uuid; u uuid; v uuid; other_table uuid; r jsonb; first_id bigint; start_id bigint; complete_id bigint;
  balance bigint; before_count bigint; key_round uuid; c integer; e record; sample jsonb;
BEGIN
  PERFORM pg_temp.check_it(NOT has_function_privilege('anon','public.start_game(uuid)','EXECUTE'),
    'anon cannot start game');
  PERFORM pg_temp.check_it(NOT has_table_privilege('service_role','public.okeyix_stat_players','INSERT'),
    'service role cannot write permanent results directly');
  -- Normal human finish: exact source payments, no duplicate begin or payout.
  t:=pg_temp.make_table(); u:=auth.uid();
  PERFORM pg_temp.deal(t);
  r:=public.start_game(t);
  PERFORM pg_temp.check_it((r->>'already_playing')::boolean,'already playing');
  PERFORM pg_temp.check_it((SELECT count(*)=1 FROM okeyix_stat_private.events WHERE table_id=t),'single begin');
  PERFORM pg_temp.check_it((SELECT bool_and(coins=9900) FROM public.profiles WHERE id IN
    (SELECT user_id FROM public.table_players WHERE table_id=t)),'source entry unchanged');
  r:=pg_temp.finish_hand(t,u);
  PERFORM pg_temp.check_it((r->>'ok')::boolean,'normal finish');
  SELECT coins INTO balance FROM public.profiles WHERE id=u;
  BEGIN PERFORM pg_temp.finish_hand(t,u); RAISE EXCEPTION 'duplicate finish accepted';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'TABLE_NOT_PLAYING' THEN RAISE; END IF; END;
  PERFORM pg_temp.check_it((SELECT coins=balance FROM public.profiles WHERE id=u),'no double payout');
  c:=okeyix_stat_private.process_events(100);
  PERFORM pg_temp.check_it(c=2,'ordered begin and complete in same worker batch');
  SELECT id INTO key_round FROM public.okeyix_stat_rounds WHERE session_id=
    (SELECT id FROM public.okeyix_stat_sessions WHERE table_id=t);
  PERFORM pg_temp.check_it((SELECT status='completed' AND NOT is_okey_finish AND NOT is_double_finish
    FROM public.okeyix_stat_rounds WHERE id=key_round),'normal flags');
  PERFORM pg_temp.check_it((SELECT coin_entry=100 AND coin_reward=180 AND coin_net=80 AND rating_delta=8 AND outcome='win'
    FROM public.okeyix_stat_players WHERE round_id=key_round AND user_id=u),'actual winner receipt');
  PERFORM pg_temp.check_it((SELECT coin_reward=0 AND coin_net=-100 AND rating_delta=0 AND outcome='loss'
    FROM public.okeyix_stat_players WHERE round_id=key_round AND user_id<>u),'actual loser receipt');
  SELECT count(*) INTO before_count FROM public.wallet_transactions;
  FOR e IN SELECT id FROM okeyix_stat_private.events WHERE table_id=t ORDER BY id LOOP
    PERFORM okeyix_stat_private.project_event(e.id);
  END LOOP;
  PERFORM pg_temp.check_it((SELECT count(*)=before_count FROM public.wallet_transactions),'replay cannot pay');
  PERFORM pg_temp.check_it((SELECT wins=1 FROM public.users WHERE id=u),'legacy wins not doubled');
  PERFORM pg_temp.check_it((SELECT coins=balance FROM public.profiles WHERE id=u),'projector cannot pay');
  SELECT id INTO complete_id FROM okeyix_stat_private.events WHERE table_id=t AND kind='complete';
  BEGIN
    UPDATE okeyix_stat_private.event_players SET coin_refund=NULL WHERE event_id=complete_id AND user_id=u;
    PERFORM okeyix_stat_private.project_event(complete_id); RAISE EXCEPTION 'NULL/zero replay accepted';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'STAT_FINISH_REPLAY_CONFLICT' THEN RAISE; END IF; END;
  BEGIN
    UPDATE okeyix_stat_private.events SET winner_user_id=gen_random_uuid() WHERE id=complete_id;
    PERFORM okeyix_stat_private.project_event(complete_id); RAISE EXCEPTION 'nonparticipant winner accepted';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'STAT_PARTICIPANTS_CONFLICT' THEN RAISE; END IF; END;

  -- Full begin replay validates seat/bot/amount, not merely player IDs.
  SELECT id INTO start_id FROM okeyix_stat_private.events WHERE table_id=t AND kind='begin';
  SELECT jsonb_agg(to_jsonb(p)-'event_id') INTO sample FROM okeyix_stat_private.event_players p WHERE event_id=start_id;
  SELECT * INTO e FROM okeyix_stat_private.events WHERE id=start_id;
  PERFORM okeyix_stat_private.put_event(e.table_id,e.round_no,e.seed,e.kind,e.league_id,e.entry_coin,
    e.occurred_at,e.winner_user_id,e.is_okey,e.is_double,e.reason,sample);
  BEGIN
    PERFORM okeyix_stat_private.put_event(e.table_id,e.round_no,e.seed,e.kind,e.league_id,e.entry_coin,
      e.occurred_at,e.winner_user_id,e.is_okey,e.is_double,e.reason,
      jsonb_set(sample,'{0,is_bot}',to_jsonb(NOT (sample->0->>'is_bot')::boolean)));
    RAISE EXCEPTION 'bot conflict accepted';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'STAT_EVENT_PLAYERS_REPLAY_CONFLICT' THEN RAISE; END IF; END;
  BEGIN
    PERFORM okeyix_stat_private.put_event(e.table_id,e.round_no,e.seed,e.kind,e.league_id,e.entry_coin,
      e.occurred_at,e.winner_user_id,e.is_okey,e.is_double,e.reason,jsonb_set(sample,'{0,seat_index}','9'::jsonb));
    RAISE EXCEPTION 'seat conflict accepted';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'STAT_EVENT_PLAYERS_REPLAY_CONFLICT' THEN RAISE; END IF; END;

  -- Both finish flags must survive simultaneously; winner may be a real bot.
  t:=pg_temp.make_table(true); u:=auth.uid();
  SELECT user_id INTO v FROM public.table_players WHERE table_id=t AND seat_index=1;
  PERFORM pg_temp.deal(t);
  UPDATE public.tables SET current_turn=1 WHERE id=t;
  PERFORM pg_temp.finish_hand(t,v,true,true);
  PERFORM okeyix_stat_private.process_events();
  PERFORM pg_temp.check_it((SELECT r.is_okey_finish AND r.is_double_finish AND p.is_bot AND p.outcome='win'
    FROM public.okeyix_stat_sessions s JOIN public.okeyix_stat_rounds r ON r.session_id=s.id
    JOIN public.okeyix_stat_players p ON p.round_id=r.id AND p.user_id=v WHERE s.table_id=t),'bot combined finish');
  FOR c IN 1..2 LOOP
    t:=pg_temp.make_table(true); u:=auth.uid(); PERFORM pg_temp.deal(t);
    PERFORM pg_temp.finish_hand(t,u,c=1,c=2); PERFORM okeyix_stat_private.process_events();
    PERFORM pg_temp.check_it((SELECT r.is_okey_finish=(c=1) AND r.is_double_finish=(c=2)
      FROM public.okeyix_stat_sessions s JOIN public.okeyix_stat_rounds r ON r.session_id=s.id WHERE s.table_id=t),
      'individual okey/double flags');
  END LOOP;
  t:=pg_temp.make_table(); u:=auth.uid(); PERFORM pg_temp.deal(t);
  PERFORM set_config('test.finish_valid','false',true);
  r:=pg_temp.finish_hand(t,u);
  PERFORM pg_temp.check_it(NOT (r->>'ok')::boolean AND (SELECT status='playing' FROM public.tables WHERE id=t),
    'invalid solver result leaves hand playing');
  PERFORM pg_temp.check_it(NOT EXISTS(SELECT 1 FROM okeyix_stat_private.events WHERE table_id=t AND kind='complete'),
    'invalid finish has no result receipt');
  PERFORM set_config('test.finish_valid','true',true);
  PERFORM pg_temp.finish_hand(t,u); PERFORM okeyix_stat_private.process_events();
  -- The old discard-with-finish RPC remains a separate, unchanged payment engine.
  t:=pg_temp.make_table(); u:=auth.uid(); PERFORM pg_temp.deal(t);
  SELECT user_id INTO v FROM public.table_players WHERE table_id=t AND user_id<>u;
  UPDATE public.profiles SET rating=501 WHERE id=v;
  SELECT hand->14 INTO sample FROM public.table_players WHERE table_id=t AND user_id=u;
  SELECT coins INTO balance FROM public.profiles WHERE id=u;
  r:=public.game_discard(t,u,sample,true,(SELECT jsonb_agg('{}'::jsonb) FROM generate_series(1,26)),true);
  PERFORM okeyix_stat_private.process_events();
  PERFORM pg_temp.check_it((SELECT p.coin_reward=(SELECT coins-balance FROM public.profiles WHERE id=u)
    AND p.outcome='win' FROM public.okeyix_stat_sessions s JOIN public.okeyix_stat_rounds r ON r.session_id=s.id
    JOIN public.okeyix_stat_players p ON p.round_id=r.id AND p.user_id=u WHERE s.table_id=t),
    'legacy finish records its own actual payment');
  PERFORM pg_temp.check_it((SELECT p.rating_delta=-1
    FROM public.okeyix_stat_sessions s JOIN public.okeyix_stat_rounds r ON r.session_id=s.id
    JOIN public.okeyix_stat_players p ON p.round_id=r.id AND p.user_id=v WHERE s.table_id=t),
    'legacy rating clamp records actual loss');
  -- A missing profile/unknown baseline must NOT become nominal entry/reward.
  t:=pg_temp.make_table(); u:=auth.uid();
  UPDATE public.profiles SET coins=NULL,rating=NULL WHERE id=u;
  PERFORM pg_temp.deal(t);
  PERFORM pg_temp.finish_hand(t,u);
  PERFORM okeyix_stat_private.process_events();
  PERFORM pg_temp.check_it((SELECT p.coin_entry IS NULL AND p.coin_reward=180 AND p.rating_delta IS NULL AND p.coin_net IS NULL
    FROM public.okeyix_stat_sessions s JOIN public.okeyix_stat_rounds r ON r.session_id=s.id
    JOIN public.okeyix_stat_players p ON p.round_id=r.id AND p.user_id=u WHERE s.table_id=t),'null entry/net/rating preserved');
  t:=pg_temp.make_table(); u:=auth.uid();
  DELETE FROM public.profiles WHERE id=u;
  PERFORM pg_temp.deal(t); PERFORM pg_temp.finish_hand(t,u); PERFORM okeyix_stat_private.process_events();
  PERFORM pg_temp.check_it((SELECT p.coin_entry IS NULL AND p.coin_reward IS NULL AND p.coin_net IS NULL
    FROM public.okeyix_stat_sessions s JOIN public.okeyix_stat_rounds r ON r.session_id=s.id
    JOIN public.okeyix_stat_players p ON p.round_id=r.id AND p.user_id=u WHERE s.table_id=t),'missing profile not assumed paid');

  -- Low-coin eviction during success must retain the original loser in statistics.
  t:=pg_temp.make_table(); u:=auth.uid(); PERFORM pg_temp.deal(t);
  SELECT user_id INTO v FROM public.table_players WHERE table_id=t AND user_id<>u;
  UPDATE public.profiles SET coins=0 WHERE id=v;
  PERFORM pg_temp.finish_hand(t,u); PERFORM okeyix_stat_private.process_events();
  PERFORM pg_temp.check_it(NOT EXISTS(SELECT 1 FROM public.table_players WHERE table_id=t AND user_id=v),'source evicts poor player');
  PERFORM pg_temp.check_it((SELECT count(*)=2 FROM public.okeyix_stat_players p JOIN public.okeyix_stat_rounds r ON r.id=p.round_id
    JOIN public.okeyix_stat_sessions s ON s.id=r.session_id WHERE s.table_id=t),'eviction retains original participants');

  -- Departure: abort without awarding a win/loss or fabricating a refund.
  t:=pg_temp.make_table(); u:=auth.uid(); PERFORM pg_temp.deal(t); PERFORM public.leave_table(t,u);
  PERFORM public.leave_table(t,u);
  PERFORM okeyix_stat_private.process_events();
  PERFORM pg_temp.check_it((SELECT r.status='aborted' AND p.outcome='aborted' AND p.coin_entry=100 AND p.coin_reward IS NULL
    FROM public.okeyix_stat_sessions s JOIN public.okeyix_stat_rounds r ON r.session_id=s.id
    JOIN public.okeyix_stat_players p ON p.round_id=r.id AND p.user_id=u WHERE s.table_id=t),'departure aborted');

  -- Third timeout resets the hand; first timeout remains a normal turn.
  t:=pg_temp.make_table(true); u:=auth.uid(); PERFORM pg_temp.deal(t);
  UPDATE public.tables SET turn_started_at=now()-interval '30 seconds' WHERE id=t;
  r:=public.game_timeout_move(t,u);
  PERFORM pg_temp.check_it((SELECT status='playing' FROM public.tables WHERE id=t),'normal timeout continues');
  UPDATE public.tables SET current_turn=0,turn_started_at=now()-interval '30 seconds' WHERE id=t;
  UPDATE public.table_players SET consecutive_timeouts=2 WHERE table_id=t AND user_id=u;
  r:=public.game_timeout_move(t,u);
  PERFORM pg_temp.check_it(r->>'action'='table_waiting_bot_only','third timeout engine reset');
  PERFORM okeyix_stat_private.process_events();
  PERFORM pg_temp.check_it((SELECT status='aborted' FROM public.okeyix_stat_rounds WHERE session_id=
    (SELECT id FROM public.okeyix_stat_sessions WHERE table_id=t)),'timeout aborted');

  -- A replaced unresolved hand never blocks the next real deal.
  t:=pg_temp.make_table(); u:=auth.uid(); PERFORM pg_temp.deal(t);
  UPDATE public.tables SET status='waiting' WHERE id=t;
  PERFORM pg_temp.deal(t);
  PERFORM okeyix_stat_private.process_events();
  PERFORM pg_temp.check_it((SELECT count(*) FILTER(WHERE status='aborted')=1 AND count(*) FILTER(WHERE status='started')=1
    FROM public.okeyix_stat_rounds WHERE session_id=(SELECT id FROM public.okeyix_stat_sessions WHERE table_id=t)),
    'new deal closes unresolved previous hand');

  -- Four-player source tables remain supported; do not impose a new two-player rule.
  t:=pg_temp.make_table(false,4); u:=auth.uid(); PERFORM pg_temp.deal(t);
  PERFORM pg_temp.finish_hand(t,u); PERFORM okeyix_stat_private.process_events();
  PERFORM pg_temp.check_it((SELECT count(*)=4 FROM public.okeyix_stat_players p JOIN public.okeyix_stat_rounds r ON r.id=p.round_id
    JOIN public.okeyix_stat_sessions s ON s.id=r.session_id WHERE s.table_id=t),'four player inventory');

  -- Table deletion before projection: receipts survive, session closes, hand aborts.
  t:=pg_temp.make_table(); PERFORM pg_temp.deal(t);
  DELETE FROM public.table_players WHERE table_id=t;
  DELETE FROM public.tables WHERE id=t;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  PERFORM okeyix_stat_private.process_events();
  PERFORM pg_temp.check_it((SELECT s.ended_at IS NOT NULL AND r.status='aborted'
    FROM public.okeyix_stat_sessions s JOIN public.okeyix_stat_rounds r ON r.session_id=s.id WHERE s.table_id=t),
    'deleted table retained and closed');

  -- Projector failure leaves game paid and retryable, and does not stop other tables.
  t:=pg_temp.make_table(); PERFORM pg_temp.deal(t);
  SELECT id INTO first_id FROM okeyix_stat_private.events WHERE table_id=t AND kind='begin';
  PERFORM set_config('test.reject_table',t::text,true);
  other_table:=pg_temp.make_table(); PERFORM pg_temp.deal(other_table);
  CREATE TRIGGER test_projection_failure BEFORE INSERT ON public.okeyix_stat_rounds
    FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_projection();
  PERFORM okeyix_stat_private.process_events();
  DROP TRIGGER test_projection_failure ON public.okeyix_stat_rounds;
  PERFORM pg_temp.check_it((SELECT attempts=1 AND processed_at IS NULL AND error_code IS NOT NULL
    FROM okeyix_stat_private.events WHERE id=first_id),'retry retained');
  PERFORM pg_temp.check_it((SELECT status='playing' FROM public.tables WHERE id=t),'projection failure leaves game running');
  PERFORM pg_temp.check_it(EXISTS(SELECT 1 FROM public.okeyix_stat_sessions WHERE table_id=other_table),
    'poison event does not block other tables');
  UPDATE okeyix_stat_private.events SET retry_at=now() WHERE id=first_id;
  PERFORM okeyix_stat_private.process_events();
  PERFORM pg_temp.check_it((SELECT processed_at IS NOT NULL FROM okeyix_stat_private.events WHERE id=first_id),'retry recovers');
  PERFORM pg_temp.check_it(NOT EXISTS(SELECT 1 FROM okeyix_stat_private.events WHERE processed_at IS NULL),'queue drained');

  -- Capturing the durable receipt is atomic with the charge (minimal fail-closed boundary).
  t:=pg_temp.make_table(); u:=auth.uid();
  CREATE TRIGGER test_capture_failure BEFORE INSERT ON okeyix_stat_private.events
    FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_capture();
  BEGIN PERFORM pg_temp.deal(t); RAISE EXCEPTION 'capture failure ignored';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'injected local capture failure' THEN RAISE; END IF; END;
  DROP TRIGGER test_capture_failure ON okeyix_stat_private.events;
  PERFORM pg_temp.check_it((SELECT coins=10000 FROM public.profiles WHERE id=u),'failed capture rolls back charge');
  PERFORM pg_temp.check_it((SELECT status='start' AND round_count=0 FROM public.tables WHERE id=t),'failed capture rolls back deal');
END $tests$;
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

-- Execute with REAL API database roles, not only mocked JWT strings.
DO $$ DECLARE t uuid; u uuid; other uuid; before_n bigint;
BEGIN
  t:=pg_temp.make_table(); u:=auth.uid();
  SELECT user_id INTO other FROM public.table_players WHERE table_id=t AND user_id<>u;
  DROP TABLE IF EXISTS pg_temp._tmp_shuffled_tiles;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM pg_temp.deal(t);
  BEGIN
    PERFORM okeyix_stat_private.process_events(); RAISE EXCEPTION 'private writer exposed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    INSERT INTO public.okeyix_stat_sessions(table_id,league_id,entry_coin,started_at) VALUES(gen_random_uuid(),'standard',100,now());
    RAISE EXCEPTION 'direct write exposed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.leave_table(t,other); RAISE EXCEPTION 'other human removed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM public.game_discard(t,other,'{}'::jsonb,NULL,NULL,false);
    RAISE EXCEPTION 'null flag authorization bypass';
  EXCEPTION WHEN null_value_not_allowed THEN NULL; END;
  PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
  BEGIN
    PERFORM public.start_game(t); RAISE EXCEPTION 'outsider accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  EXECUTE 'SET LOCAL ROLE postgres';
  PERFORM set_config('request.jwt.claim.sub',u::text,true);
  PERFORM okeyix_stat_private.process_events();
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM pg_temp.check_it((SELECT count(*)=1 FROM public.okeyix_stat_players),'own-history RLS');
  EXECUTE 'SET LOCAL ROLE postgres';
END $$;

SELECT 'statistics integration assertions passed' AS result;
ROLLBACK;

-- LOCAL ONLY: synthetic data, rollback; never run on production.
\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN IF current_database() NOT LIKE 'okeyix_stat_test_%' OR inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet THEN RAISE EXCEPTION 'LOCAL_ONLY'; END IF; END $$;
CREATE FUNCTION pg_temp.check_it(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS NOT TRUE THEN RAISE EXCEPTION 'FAILED: %',label; END IF; END $$;
CREATE FUNCTION pg_temp.reject_gift_wallet() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'injected wallet failure'; END $$;
DO $tests$
DECLARE u uuid:=gen_random_uuid(); v uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid(); t uuid:=gen_random_uuid();
  req uuid:=gen_random_uuid(); answer jsonb; replay jsonb; before_balance integer; before_wallet bigint; seq bigint;
BEGIN
  INSERT INTO public.users(id,username) VALUES(u,'Gift '||u::text),(v,'Gift '||v::text),(outsider,'Viewer '||outsider::text);
  INSERT INTO public.profiles(id,username,coins,rating) VALUES(u,u::text,100000,1200),(v,v::text,22222,1200),(outsider,outsider::text,99999,1200);
  INSERT INTO public.tables(id,created_by,league_id,entry_coin,min_rounds,max_players,status,spectators_enabled)
    VALUES(t,u,'test',100,1,2,'playing',true);
  INSERT INTO public.table_players(table_id,user_id,seat_index) VALUES(t,u,0),(t,v,1);
  PERFORM set_config('test.gift_table',t::text,true);
  PERFORM set_config('test.gift_viewer',outsider::text,true);
  PERFORM set_config('request.jwt.claim.sub',u::text,true);
  answer:=public.okeyix_buy_table_gift(t,v,'cay',req);
  seq:=(answer->'event'->>'seq')::bigint;
  PERFORM pg_temp.check_it(answer->>'balance'='99000','sender debited server price');
  PERFORM pg_temp.check_it((SELECT coins=22222 FROM public.profiles WHERE id=v),'receiver receives no coins');
  replay:=public.okeyix_buy_table_gift(t,v,'cay',req);
  PERFORM pg_temp.check_it(replay->>'replayed'='true' AND (replay->'event'->>'seq')::bigint=seq,'same request same receipt');
  PERFORM pg_temp.check_it((SELECT count(*)=1 FROM public.wallet_transactions WHERE user_id=u),'one debit only');
  BEGIN PERFORM public.okeyix_buy_table_gift(t,u,'cay',req); RAISE EXCEPTION 'conflict accepted';
    EXCEPTION WHEN SQLSTATE '22023' THEN NULL; END;
  answer:=public.okeyix_buy_table_gift(t,u,'kahve',gen_random_uuid());
  PERFORM pg_temp.check_it((SELECT gift_id='kahve' FROM public.okeyix_table_last_gifts WHERE table_id=t AND user_id=u),'self gift retained');
  PERFORM public.okeyix_buy_table_gift(t,v,'pasta',gen_random_uuid());
  PERFORM pg_temp.check_it((SELECT gift_id='pasta' AND purchase_seq>seq FROM public.okeyix_table_last_gifts WHERE table_id=t AND user_id=v),'new gift replaces old without timeout');
  UPDATE public.okeyix_gift_catalog SET price=1300 WHERE id='cay';
  SELECT coins INTO before_balance FROM public.profiles WHERE id=u;
  answer:=public.okeyix_buy_table_gift(t,v,'cay',gen_random_uuid());
  PERFORM pg_temp.check_it((answer->>'balance')::integer=before_balance-1300,'central server price used');
  UPDATE public.profiles SET coins=0 WHERE id=u;
  SELECT count(*) INTO before_wallet FROM public.wallet_transactions WHERE user_id=u;
  BEGIN PERFORM public.okeyix_buy_table_gift(t,v,'cay',gen_random_uuid()); RAISE EXCEPTION 'insufficient accepted';
    EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'GIFT_INSUFFICIENT_COINS' THEN RAISE; END IF; END;
  PERFORM pg_temp.check_it((SELECT count(*)=before_wallet FROM public.wallet_transactions WHERE user_id=u),'no insufficient purchase');
  UPDATE public.profiles SET coins=100000 WHERE id=u;
  CREATE TRIGGER gift_wallet_failure BEFORE INSERT ON public.wallet_transactions FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_gift_wallet();
  BEGIN PERFORM public.okeyix_buy_table_gift(t,v,'cay',gen_random_uuid());
    EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'injected wallet failure' THEN RAISE; END IF; END;
  DROP TRIGGER gift_wallet_failure ON public.wallet_transactions;
  PERFORM pg_temp.check_it((SELECT coins=100000 FROM public.profiles WHERE id=u),'wallet failure rolls back debit');
  PERFORM set_config('request.jwt.claim.sub',outsider::text,true);
  BEGIN PERFORM public.okeyix_buy_table_gift(t,v,'cay',gen_random_uuid()); RAISE EXCEPTION 'spectator purchased';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM pg_temp.check_it(jsonb_array_length(public.okeyix_table_gift_snapshot(t)->'last_gifts')=2,'late spectator snapshot contains both gifts');
  PERFORM set_config('request.jwt.claim.sub',v::text,true);
  PERFORM public.okeyix_buy_table_gift(t,u,'limon',gen_random_uuid());
  PERFORM pg_temp.check_it((SELECT gift_id='limon' FROM public.okeyix_table_last_gifts WHERE table_id=t AND user_id=u),'reverse direction purchase');
  DELETE FROM public.table_players WHERE table_id=t AND user_id=v;
  PERFORM pg_temp.check_it(NOT EXISTS(SELECT 1 FROM public.okeyix_table_last_gifts WHERE table_id=t AND user_id=v),'membership end clears gift');
  INSERT INTO public.table_players(table_id,user_id,seat_index) VALUES(t,v,1);
  PERFORM pg_temp.check_it(NOT EXISTS(SELECT 1 FROM public.okeyix_table_last_gifts WHERE table_id=t AND user_id=v),'rejoining cannot inherit old occupancy gift');
  PERFORM pg_temp.check_it((SELECT wins IS NULL AND losses IS NULL AND rating=1000 FROM public.users WHERE id=u),'career system unchanged');
END $tests$;
SELECT set_config('request.jwt.claim.sub',current_setting('test.gift_viewer'),true);
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  IF (SELECT count(*) FROM public.okeyix_table_last_gifts WHERE table_id=current_setting('test.gift_table')::uuid)<>1 THEN RAISE EXCEPTION 'spectator read policy failed'; END IF;
  BEGIN UPDATE public.okeyix_gift_catalog SET price=1; RAISE EXCEPTION 'client changed prices'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
UPDATE public.tables SET spectators_enabled=false WHERE id=current_setting('test.gift_table')::uuid;
SET LOCAL ROLE authenticated;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM public.okeyix_table_last_gifts WHERE table_id=current_setting('test.gift_table')::uuid) THEN RAISE EXCEPTION 'private spectator data leaked'; END IF; END $$;
RESET ROLE;
DELETE FROM public.tables WHERE id=current_setting('test.gift_table')::uuid;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM public.okeyix_table_last_gifts WHERE table_id=current_setting('test.gift_table')::uuid) THEN RAISE EXCEPTION 'table state not cleared'; END IF;
 IF (SELECT count(*) FROM public.okeyix_table_gift_purchases WHERE table_id=current_setting('test.gift_table')::uuid)<>5 THEN RAISE EXCEPTION 'purchase history lost'; END IF;
END $$;
SELECT 'gift server validation, atomic debit, idempotency, self/reverse gifts, spectator RLS and session cleanup passed' AS result;
ROLLBACK;

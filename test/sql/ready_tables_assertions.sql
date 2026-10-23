DO $$ DECLARE r jsonb; n integer; bot uuid; target_table uuid; BEGIN
  -- Report-only calls must not open seats or charge balances.
  r:=public.run_standard_bot_table_maintainer(3,false);
  IF (SELECT count(*) FROM public.tables)<>1 THEN RAISE EXCEPTION 'DRY_RUN_WROTE'; END IF;
  PERFORM public.run_okey_watchdog();
  IF (SELECT count(*) FROM public.tables)<>1 THEN RAISE EXCEPTION 'UNCONFIGURED_INSTALL_ACTIVE'; END IF;
  BEGIN
    UPDATE okeyix_ready_private.policy SET owner_id=md5('human')::uuid,enabled=true;
    RAISE EXCEPTION 'REAL_OWNER_ACCEPTED';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'READY_TABLES_DEDICATED_OWNER_REQUIRED' THEN RAISE; END IF;
  END;
  UPDATE okeyix_ready_private.policy SET owner_id=md5('system-owner')::uuid,enabled=true;
  IF NOT (SELECT is_bot FROM public.users WHERE id=md5('system-owner')::uuid)
    OR (SELECT is_online FROM public.profiles WHERE id=md5('system-owner')::uuid) THEN
    RAISE EXCEPTION 'SYSTEM_OWNER_VISIBLE_AS_HUMAN'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='public.tables'::regclass
    AND attname='created_by' AND attnotnull) THEN RAISE EXCEPTION 'NOT_NULL_REMOVED'; END IF;
  -- Existing watchdog is now the automatic entrypoint.
  r:=public.run_okey_watchdog();
  IF (SELECT count(*) FROM okeyix_ready_private.managed)<>8 THEN RAISE EXCEPTION 'EXPECTED_EIGHT_BOT_TABLES %',r; END IF;
  IF EXISTS(SELECT 1 FROM public.tables t WHERE t.league_id IN ('gold','elite')) THEN
    RAISE EXCEPTION 'HIGH_LEAGUE_TABLE_CREATED'; END IF;
  IF EXISTS(SELECT 1 FROM public.tables t JOIN okeyix_ready_private.managed m ON m.table_id=t.id
    JOIN public.leagues l ON l.id=t.league_id WHERE t.created_by<>md5('system-owner')::uuid OR t.entry_coin<>l.min_coin
      OR t.max_players<>2 OR (SELECT count(*) FROM public.table_players p WHERE p.table_id=t.id)<>1) THEN
    RAISE EXCEPTION 'WRONG_READY_TABLE'; END IF;
  PERFORM public.run_okey_watchdog();
  IF (SELECT count(*) FROM public.tables)<>9 THEN RAISE EXCEPTION 'DUPLICATE_MAINTENANCE'; END IF;
  UPDATE public.tables SET ready_since=now()-interval '1 day',created_at=now()-interval '1 day';
  PERFORM public.cleanup_stale_bot_waiting_tables(10);
  PERFORM public.cleanup_stale_waiting_tables(interval '2 minutes');
  IF (SELECT count(*) FROM okeyix_ready_private.managed)<>8 THEN RAISE EXCEPTION 'READY_TABLE_CLEANED'; END IF;
  SELECT table_id,bot_id INTO target_table,bot FROM okeyix_ready_private.managed LIMIT 1;
  -- Only verified table IDs bypass owner-presence checks. No user identity is returned.
  PERFORM set_config('request.jwt.claim.sub',md5('human')::uuid::text,true);
  IF NOT EXISTS(SELECT 1 FROM public.okeyix_ready_table_ids(ARRAY[target_table]) id WHERE id=target_table)
    OR EXISTS(SELECT 1 FROM public.okeyix_ready_table_ids(ARRAY[md5('human-table')::uuid])) THEN
    RAISE EXCEPTION 'READY_ID_VERIFICATION_FAILED'; END IF;
  PERFORM set_config('request.jwt.claim.sub','',true);
  IF EXISTS(SELECT 1 FROM public.okeyix_ready_table_ids(ARRAY[target_table])) THEN
    RAISE EXCEPTION 'ANONYMOUS_READY_IDS_EXPOSED'; END IF;
  BEGIN
    INSERT INTO public.table_players(table_id,user_id,seat_index) VALUES(md5('human-table')::uuid,bot,1);
    RAISE EXCEPTION 'DUPLICATE_BOT_ACCEPTED';
  EXCEPTION WHEN unique_violation THEN NULL; END;
  UPDATE public.tables SET status='playing' WHERE id=target_table;
  PERFORM public.run_standard_bot_table_maintainer(3,true);
  IF (SELECT count(*) FROM okeyix_ready_private.managed)<>9 THEN RAISE EXCEPTION 'NOT_REPLENISHED_AFTER_START'; END IF;
  IF (SELECT status FROM public.tables WHERE id=target_table)<>'playing' THEN RAISE EXCEPTION 'PLAYING_CHANGED'; END IF;
  UPDATE public.tables SET status='waiting' WHERE id=target_table;
  SELECT count(*) INTO n FROM okeyix_ready_private.managed m
    WHERE okeyix_ready_private.keep_ready(m.table_id);
  IF n<>8 THEN RAISE EXCEPTION 'SURPLUS_TABLES_PROTECTED %',n; END IF;
  -- Expire the surplus through the existing cleanup, without closing a game.
  UPDATE public.tables SET ready_since=now()-interval '1 day';
  PERFORM public.cleanup_stale_bot_waiting_tables(10);
  IF (SELECT count(*) FROM okeyix_ready_private.managed)<>8 THEN RAISE EXCEPTION 'SURPLUS_NOT_EXPIRED'; END IF;
  -- Invalid/unfunded bot tables do not count as joinable and aren't protected.
  SELECT table_id,bot_id INTO target_table,bot FROM okeyix_ready_private.managed m
    JOIN public.tables t ON t.id=m.table_id WHERE t.status='waiting' LIMIT 1;
  UPDATE public.profiles SET coins=0 WHERE id=bot;
  IF okeyix_ready_private.keep_ready(target_table) THEN RAISE EXCEPTION 'UNFUNDED_PROTECTED'; END IF;
  UPDATE public.profiles SET coins=200000000 WHERE id=bot;
  -- Insufficient bot pool reports shortages instead of inventing accounts.
  DELETE FROM okeyix_bot_wallet_private.registry;
  r:=public.run_standard_bot_table_maintainer(3,true);
  IF (r->>'created')::int<>0 THEN RAISE EXCEPTION 'UNAPPROVED_BOT_USED'; END IF;
  IF (SELECT coins FROM public.profiles WHERE id=md5('human')::uuid)<>1000000 THEN
    RAISE EXCEPTION 'HUMAN_BALANCE_CHANGED'; END IF;
END $$;
DO $$ BEGIN
  IF has_function_privilege('authenticated','okeyix_bot_wallet_private.source_maintainer(integer,boolean)','EXECUTE')
    OR has_schema_privilege('authenticated','okeyix_ready_private','USAGE') THEN
    RAISE EXCEPTION 'CLIENT_PRIVILEGE_LEAK'; END IF;
END $$;
SET ROLE authenticated;
DO $$ BEGIN
  BEGIN
    PERFORM public.run_standard_bot_table_maintainer(3,true);
    RAISE EXCEPTION 'CLIENT_MAINTENANCE_ACCEPTED';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;
SELECT 'Ready table targets, exclusions, cleanup, bot claims, replenishment and balances passed' AS result;

-- LOCAL fixture only. Every assertion raises on failure.
\set ON_ERROR_STOP on
DO $$ BEGIN
  IF current_database()<>'okeyix_bot_wallet_test' THEN RAISE EXCEPTION 'LOCAL_TEST_DATABASE_REQUIRED'; END IF;
END $$;
CREATE FUNCTION public.test_assert(p_condition boolean,p_name text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_condition IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAILED: %',p_name; END IF; END $$;
SELECT public.test_assert((SELECT coins=200000000 FROM public.profiles WHERE id='00000000-0000-0000-0000-000000000001'),'zero bot funded at install');
SELECT public.test_assert((SELECT coins=12345 FROM public.profiles WHERE id='00000000-0000-0000-0000-000000000002'),'human untouched');
SELECT public.test_assert((SELECT coins=54321 FROM public.profiles WHERE id='00000000-0000-0000-0000-000000000003'),'auth account with bot flag excluded');
SELECT public.test_assert((SELECT count(*)=1 FROM okeyix_bot_wallet_private.topups),'one initial receipt');
SELECT public.test_assert(okeyix_bot_wallet_private.replenish('watchdog')=0,'repeat check no topup');
UPDATE public.profiles SET coins=NULL WHERE id='00000000-0000-0000-0000-000000000001';
SELECT public.test_assert(okeyix_bot_wallet_private.replenish('watchdog')=1,'null balance recovers as zero');
UPDATE public.profiles SET coins=50000000 WHERE id='00000000-0000-0000-0000-000000000001';
SELECT public.test_assert(okeyix_bot_wallet_private.replenish('watchdog')=0,'at threshold unchanged');
UPDATE public.profiles SET coins=49999999 WHERE id='00000000-0000-0000-0000-000000000001';
SELECT public.test_assert(okeyix_bot_wallet_private.replenish('watchdog')=1,'below threshold topup');
SELECT public.test_assert((SELECT amount=150000001 FROM okeyix_bot_wallet_private.topups ORDER BY id DESC LIMIT 1),'exact missing difference');
SELECT public.test_assert((SELECT coins>=max_coin FROM public.profiles CROSS JOIN public.leagues
  WHERE public.profiles.id='00000000-0000-0000-0000-000000000001' AND public.leagues.id='elite'),'champions maximum affordable');
UPDATE public.profiles SET coins=300000000 WHERE id='00000000-0000-0000-0000-000000000001';
SELECT public.test_assert(okeyix_bot_wallet_private.replenish('watchdog')=0,'high balance unchanged');
SELECT public.test_assert((SELECT coins=300000000 FROM public.profiles WHERE id='00000000-0000-0000-0000-000000000001'),'winnings never lowered');
SELECT public.test_game_charge('00000000-0000-0000-0000-000000000001',10000000);
SELECT public.test_game_reward('00000000-0000-0000-0000-000000000001',18000000);
SELECT public.test_assert((SELECT coins=308000000 FROM public.profiles WHERE id='00000000-0000-0000-0000-000000000001'),'normal debit and reward preserved');
SELECT public.test_assert(NOT EXISTS(SELECT 1 FROM public.test_contract_hashes h JOIN pg_proc p ON p.oid=h.oid
  WHERE md5(pg_get_functiondef(p.oid))<>h.hash),'game function bodies unchanged');
SELECT public.test_assert((public.run_standard_bot_table_maintainer(4,true)->>'eligible')::integer=1,'rich bot still eligible for cheap league');
UPDATE public.profiles SET coins=0 WHERE id='00000000-0000-0000-0000-000000000001';
SELECT public.test_assert(public.run_okey_watchdog()='{"ok":true,"processed":0}'::jsonb,'watchdog result preserved');
SELECT public.test_assert((SELECT n=1 FROM public.watchdog_runs),'original watchdog executes once');
SELECT public.test_assert((SELECT coins=200000000 FROM public.profiles WHERE id='00000000-0000-0000-0000-000000000001'),'existing watchdog funds bot');
-- Identity guards must work even though users RLS is OFF and clients have DML.
SET ROLE authenticated;
SET request.jwt.claim.role='authenticated';
DO $$ BEGIN
  BEGIN UPDATE public.users SET is_bot=true WHERE id='00000000-0000-0000-0000-000000000002';
    RAISE EXCEPTION 'FAILED spoof flag'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN INSERT INTO public.users VALUES('00000000-0000-0000-0000-000000000099',true,'spoof');
    RAISE EXCEPTION 'FAILED spoof insert'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.run_okey_watchdog(); RAISE EXCEPTION 'FAILED public topup';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM public.run_standard_bot_table_maintainer(4,true); RAISE EXCEPTION 'FAILED public maintainer';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN DELETE FROM public.users WHERE id='00000000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAILED bot deletion'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM okeyix_bot_wallet_private.replenish('watchdog'); RAISE EXCEPTION 'FAILED private access';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  UPDATE public.users SET username='normal_update' WHERE id='00000000-0000-0000-0000-000000000002';
END $$;
RESET ROLE;
RESET request.jwt.claim.role;
SET ROLE anon;
SET request.jwt.claim.role='anon';
DO $$ BEGIN
  BEGIN INSERT INTO public.users VALUES('00000000-0000-0000-0000-000000000098',true,'anon_spoof');
    RAISE EXCEPTION 'FAILED anon spoof'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
RESET request.jwt.claim.role;
-- A public SECURITY DEFINER trampoline cannot bypass JWT/outer-role checks.
CREATE FUNCTION public.test_spoof_trampoline() RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN UPDATE public.users SET is_bot=true WHERE id='00000000-0000-0000-0000-000000000002'; END $$;
SET ROLE authenticated;
SET request.jwt.claim.role='authenticated';
DO $$ BEGIN
  BEGIN PERFORM public.test_spoof_trampoline(); RAISE EXCEPTION 'FAILED definer spoof';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
RESET request.jwt.claim.role;
-- Failure while writing the receipt must roll back BOTH funding and watchdog.
CREATE FUNCTION public.test_reject_receipt() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'fixture receipt unavailable'; END $$;
CREATE TRIGGER test_reject_receipt BEFORE INSERT ON okeyix_bot_wallet_private.topups
  FOR EACH ROW EXECUTE FUNCTION public.test_reject_receipt();
UPDATE public.profiles SET coins=0 WHERE id='00000000-0000-0000-0000-000000000001';
DO $$ BEGIN
  BEGIN PERFORM public.run_okey_watchdog(); RAISE EXCEPTION 'FAILED receipt failure not propagated';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM<>'fixture receipt unavailable' THEN RAISE; END IF;
  END;
END $$;
SELECT public.test_assert((SELECT coins=0 FROM public.profiles WHERE id='00000000-0000-0000-0000-000000000001'),'failed funding rolls back');
SELECT public.test_assert((SELECT n=1 FROM public.watchdog_runs),'watchdog transaction rollback');
DROP TRIGGER test_reject_receipt ON okeyix_bot_wallet_private.topups;
-- Dynamic league maximum, overflow and disabled policy.
UPDATE public.leagues SET max_coin=11000000 WHERE id='elite';
SELECT okeyix_bot_wallet_private.replenish('watchdog');
SELECT public.test_assert((SELECT coins=220000000 FROM public.profiles WHERE id='00000000-0000-0000-0000-000000000001'),'real league config read dynamically');
UPDATE public.leagues SET max_coin=200000000 WHERE id='elite';
DO $$ BEGIN
  BEGIN PERFORM okeyix_bot_wallet_private.replenish('watchdog'); RAISE EXCEPTION 'FAILED overflow accepted';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM<>'BOT_RESERVE_INTEGER_CAPACITY_EXCEEDED' THEN RAISE; END IF;
  END;
END $$;
UPDATE public.leagues SET max_coin=10000000 WHERE id='elite';
UPDATE okeyix_bot_wallet_private.policy SET enabled=false;
UPDATE public.profiles SET coins=0 WHERE id='00000000-0000-0000-0000-000000000001';
SELECT public.test_assert(okeyix_bot_wallet_private.replenish('watchdog')=0,'disabled policy no credit');
UPDATE okeyix_bot_wallet_private.policy SET enabled=true;
SET ROLE service_role;
SET request.jwt.claim.role='service_role';
SELECT public.run_okey_watchdog();
RESET ROLE;
RESET request.jwt.claim.role;
SELECT public.test_assert((SELECT coins=200000000 FROM public.profiles WHERE id='00000000-0000-0000-0000-000000000001'),'authorized service lifecycle works');
UPDATE public.profiles SET coins=0 WHERE id='00000000-0000-0000-0000-000000000001';
SELECT 'BOT WALLET ASSERTIONS PASSED' AS result;

\set ON_ERROR_STOP on
BEGIN;
DO $$ DECLARE result jsonb; before_coin bigint; expected integer;
  uid uuid:='00000000-0000-4000-8000-000000000001';
  today text:='daily_bonus:'||to_char(statement_timestamp() AT TIME ZONE 'Europe/Istanbul','YYYY-MM-DD');
  rewards integer[]:=ARRAY[2500,5000,10000,20000,40000,80000,160000];
BEGIN
  IF current_database()<>'okeyix_retention_test' THEN RAISE EXCEPTION 'LOCAL_TEST_DATABASE_REQUIRED'; END IF;
  DELETE FROM public.wallet_transactions;
  DELETE FROM okeyix_retention_private.reward_progress;
  UPDATE public.profiles SET coins=1000;
  PERFORM set_config('request.jwt.claim.sub',uid::text,true);
  FOR d IN 1..8 LOOP
    expected:=rewards[(d-1)%7+1];
    result:=public.okeyix_daily_reward_status();
    IF NOT (result->>'available')::boolean OR (result->>'day')::int<>(d-1)%7+1 THEN
      RAISE EXCEPTION 'STATUS_DAY_FAILED: %',result; END IF;
    SELECT coins INTO before_coin FROM public.profiles WHERE id=uid;
    result:=public.okeyix_claim_daily_reward();
    IF NOT (result->>'credited')::boolean OR (result->>'amount')::int<>expected THEN
      RAISE EXCEPTION 'CLAIM_FAILED: %',result; END IF;
    IF (SELECT coins FROM public.profiles WHERE id=uid)<>before_coin+expected THEN
      RAISE EXCEPTION 'BALANCE_FAILED'; END IF;
    result:=public.okeyix_daily_reward_status();
    IF (result->>'available')::boolean OR (result->>'day')::int<>(d-1)%7+1 THEN
      RAISE EXCEPTION 'CLAIMED_STATUS_FAILED: %',result; END IF;
    IF (public.okeyix_claim_daily_reward()->>'credited')::boolean THEN
      RAISE EXCEPTION 'DOUBLE_CREDIT_FAILED'; END IF;
    IF public.claim_daily_bonus(uid,999999,'spoofed') THEN
      RAISE EXCEPTION 'LEGACY_AFTER_NEW_DOUBLE_CREDIT'; END IF;
    -- Move the fixture receipt to a previous day; skipping dates does not reset progress.
    UPDATE public.wallet_transactions SET note='daily_bonus:fixture-'||d WHERE user_id=uid AND note=today;
    UPDATE okeyix_retention_private.reward_progress SET last_day_key='past' WHERE user_id=uid;
  END LOOP;
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
  IF NOT public.claim_daily_bonus(auth.uid(),999999,'spoofed') THEN RAISE EXCEPTION 'LEGACY_CLAIM_FAILED'; END IF;
  IF (public.okeyix_claim_daily_reward()->>'credited')::boolean THEN RAISE EXCEPTION 'NEW_AFTER_LEGACY_DOUBLE_CREDIT'; END IF;
  IF (SELECT coins FROM public.profiles WHERE id=auth.uid())<>3500 THEN RAISE EXCEPTION 'LEGACY_AMOUNT_CHANGED'; END IF;
  INSERT INTO auth.users VALUES('00000000-0000-4000-8000-000000000003');
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',true);
  BEGIN PERFORM public.okeyix_claim_daily_reward(); RAISE EXCEPTION 'MISSING_PROFILE_ACCEPTED';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM<>'BONUS_PROFILE_NOT_FOUND' THEN RAISE; END IF;
  END;
  IF EXISTS(SELECT 1 FROM public.wallet_transactions WHERE user_id=auth.uid())
    OR EXISTS(SELECT 1 FROM okeyix_retention_private.reward_progress WHERE user_id=auth.uid()) THEN
    RAISE EXCEPTION 'FAILED_CLAIM_NOT_ROLLED_BACK'; END IF;
  PERFORM set_config('request.jwt.claim.sub','',true);
  BEGIN PERFORM public.okeyix_claim_daily_reward(); RAISE EXCEPTION 'ANONYMOUS_CLAIM_ACCEPTED';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  UPDATE public.users SET username='Deniz' WHERE id=uid;
  BEGIN UPDATE public.users SET username='  deniz  ' WHERE id<>uid;
    RAISE EXCEPTION 'DUPLICATE_NAME_ACCEPTED'; EXCEPTION WHEN unique_violation THEN NULL; END;
END $$;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
SELECT public.okeyix_daily_reward_status();
DO $$ BEGIN
  BEGIN PERFORM * FROM okeyix_retention_private.reward_progress;
    RAISE EXCEPTION 'PRIVATE_PROGRESS_READABLE'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;

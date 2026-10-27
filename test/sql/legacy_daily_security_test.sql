-- LOCAL fixture only, run after migration 20261027000400.
\set ON_ERROR_STOP on
BEGIN;
DO $$ DECLARE u uuid:='00000000-0000-4000-8000-000000000001';
  other uuid:='00000000-0000-4000-8000-000000000002';
  today text:='daily_bonus:'||to_char(statement_timestamp() AT TIME ZONE 'Europe/Istanbul','YYYY-MM-DD');
BEGIN
  IF current_database()<>'okeyix_retention_test' THEN RAISE EXCEPTION 'LOCAL_TEST_DATABASE_REQUIRED'; END IF;
  DELETE FROM public.wallet_transactions;
  DELETE FROM okeyix_retention_private.reward_progress;
  UPDATE public.profiles SET coins=1000;
  PERFORM set_config('request.jwt.claim.sub',u::text,true);
  IF NOT public.claim_daily_bonus(u,999999999,'daily_bonus:2099-01-01') THEN
    RAISE EXCEPTION 'LEGACY_COMPATIBILITY_FAILED'; END IF;
  IF (SELECT coins FROM public.profiles WHERE id=u)<>3500
    OR NOT EXISTS(SELECT 1 FROM public.wallet_transactions WHERE user_id=u AND note=today AND amount=2500) THEN
    RAISE EXCEPTION 'CLIENT_AMOUNT_OR_DAY_TRUSTED'; END IF;
  IF public.claim_daily_bonus(u,1,'another-key') THEN RAISE EXCEPTION 'SPOOFED_DAY_DOUBLE_CREDIT'; END IF;
  IF (public.okeyix_claim_daily_reward()->>'credited')::boolean THEN RAISE EXCEPTION 'NEW_LEGACY_DOUBLE_CREDIT'; END IF;
  BEGIN PERFORM public.claim_daily_bonus(other,2500,today); RAISE EXCEPTION 'OTHER_ACCOUNT_ACCEPTED';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claim.sub','',true);
  BEGIN PERFORM public.claim_daily_bonus(u,2500,today); RAISE EXCEPTION 'ANONYMOUS_ACCEPTED';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  IF (SELECT coins FROM public.profiles WHERE id=other)<>1000
    OR (SELECT count(*) FROM public.wallet_transactions)<>1 THEN RAISE EXCEPTION 'UNEXPECTED_CREDIT'; END IF;
END $$;
ROLLBACK;

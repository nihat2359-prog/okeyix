\set ON_ERROR_STOP on
BEGIN;
DO $$ DECLARE status jsonb; BEGIN
  IF current_database()<>'okeyix_retention_test' THEN RAISE EXCEPTION 'LOCAL_TEST_DATABASE_REQUIRED'; END IF;
  PERFORM set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
  status:=public.okeyix_daily_reward_status();
  IF status->'rewards'<>jsonb_build_array(2500,5000,10000,20000,40000,80000,160000)
    OR (status->>'day')::integer<>7 OR (status->>'credited_amount')::integer<>7500
    OR (status->>'available')::boolean THEN RAISE EXCEPTION 'UPGRADE_STATUS_FAILED: %',status; END IF;
  IF (public.okeyix_claim_daily_reward()->>'credited')::boolean THEN RAISE EXCEPTION 'UPGRADE_SECOND_PAYMENT'; END IF;
  IF (SELECT coins FROM public.profiles WHERE id=auth.uid())<>8500
    OR (SELECT claims FROM okeyix_retention_private.reward_progress WHERE user_id=auth.uid())<>7 THEN
    RAISE EXCEPTION 'UPGRADE_CHANGED_BALANCE_OR_PROGRESS'; END IF;
END $$;
ROLLBACK;

-- Rewarded ads are system credits, not IAP purchases. Keep the existing wallet
-- store constraint and all signature/daily-limit checks intact.
BEGIN;
DO $$
DECLARE definition text;
BEGIN
  SELECT pg_get_functiondef('public.okeyix_credit_ad_reward(uuid,uuid,text)'::regprocedure)
    INTO definition;
  IF position('''credit'',''admob''' in definition)=0 THEN
    RAISE EXCEPTION 'Unexpected ad reward function; wallet fix not applied';
  END IF;
  EXECUTE replace(definition,'''credit'',''admob''','''credit'',''system''');
  IF EXISTS(SELECT 1 FROM pg_constraint
    WHERE conrelid='public.wallet_transactions'::regclass AND conname='wallet_store_check'
      AND pg_get_constraintdef(oid) NOT LIKE '%system%') THEN
    RAISE EXCEPTION 'Wallet does not allow system credits';
  END IF;
END $$;
COMMIT;

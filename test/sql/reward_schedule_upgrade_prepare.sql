-- LOCAL ONLY. Run before migration 20261027000300 on the retention fixture.
\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
  IF current_database()<>'okeyix_retention_test' THEN RAISE EXCEPTION 'LOCAL_TEST_DATABASE_REQUIRED'; END IF;
END $$;
INSERT INTO okeyix_retention_private.reward_progress(user_id,claims,last_day_key)
VALUES('00000000-0000-4000-8000-000000000001',7,
  'daily_bonus:'||to_char(statement_timestamp() AT TIME ZONE 'Europe/Istanbul','YYYY-MM-DD'))
ON CONFLICT(user_id) DO UPDATE SET claims=excluded.claims,last_day_key=excluded.last_day_key;
INSERT INTO public.wallet_transactions(user_id,amount,reason,type,store,note)
VALUES('00000000-0000-4000-8000-000000000001',7500,'daily_bonus','credit','system',
  'daily_bonus:'||to_char(statement_timestamp() AT TIME ZONE 'Europe/Istanbul','YYYY-MM-DD'))
ON CONFLICT(user_id,note) WHERE reason='daily_bonus' AND note IS NOT NULL DO UPDATE SET amount=excluded.amount;
UPDATE public.profiles SET coins=8500 WHERE id='00000000-0000-4000-8000-000000000001';
COMMIT;

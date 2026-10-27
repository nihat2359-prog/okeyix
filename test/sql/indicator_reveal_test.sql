-- LOCAL ONLY. All receipts rolled back; no balances are modified.
\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
  IF current_database()<>'okeyix_chat_test' THEN RAISE EXCEPTION 'LOCAL_CHAT_TEST_REQUIRED'; END IF;
END $$;
INSERT INTO public.wallet_transactions(user_id,amount,reason,note) VALUES
 ('00000000-0000-4000-8000-000000000001',100,'indicator_bonus','indicator_bonus:10000000-0000-4000-8000-000000000001'),
 ('00000000-0000-4000-8000-000000000001',100,'indicator_bonus','indicator_bonus:10000000-0000-4000-8000-000000000001'),
 ('00000000-0000-4000-8000-000000000004',100,'indicator_bonus','indicator_bonus:10000000-0000-4000-8000-000000000001'),
 ('00000000-0000-4000-8000-000000000001',100,'daily_bonus','indicator_bonus:10000000-0000-4000-8000-000000000001'),
 ('00000000-0000-4000-8000-000000000001',100,'indicator_bonus','malformed');
DO $$ BEGIN
  IF (SELECT count(*) FROM public.table_indicator_events)<>1 THEN RAISE EXCEPTION 'EVENT_FILTER_OR_DEDUPE_FAILED'; END IF;
END $$;
UPDATE public.tables SET round_count=2;
INSERT INTO public.wallet_transactions(user_id,amount,reason,note) VALUES
 ('00000000-0000-4000-8000-000000000001',150,'indicator_bonus','indicator_bonus:10000000-0000-4000-8000-000000000001');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000004',true);
DO $$ BEGIN
  IF EXISTS(SELECT 1 FROM public.table_indicator_events) THEN RAISE EXCEPTION 'OUTSIDER_READ'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
DO $$ BEGIN
  IF (SELECT count(*) FROM public.table_indicator_events)<>2 THEN RAISE EXCEPTION 'MEMBER_EVENTS_MISSING'; END IF;
  BEGIN
    INSERT INTO public.table_indicator_events(table_id,player_id,round_no,amount)
    VALUES('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001',3,100);
    RAISE EXCEPTION 'CLIENT_EVENT_SPOOF';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
ROLLBACK;
\echo 'Indicator reveal receipt/RLS tests passed.'

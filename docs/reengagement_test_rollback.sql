-- OPTIONAL OPERATIONAL ROLLBACK. NOT RUN ON PRODUCTION.
-- Removes only the new manual test RPC. Keeps its audit/config tables.
-- No CASCADE, no existing game/push objects, no cron changes.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $$ BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'POSTGRES_REQUIRED'; END IF;
END $$;
LOCK TABLE okeyix_reengagement_test_private.tickets IN ACCESS EXCLUSIVE MODE;
DO $$ BEGIN
  IF EXISTS(SELECT 1 FROM okeyix_reengagement_test_private.tickets WHERE status='dispatching')
  THEN RAISE EXCEPTION 'TEST_DISPATCH_IN_PROGRESS_STOP_AND_INSPECT_BEFORE_ROLLBACK'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.okeyix_reengagement_test_worker(text,uuid,uuid,uuid,text,jsonb) FROM service_role;
DROP FUNCTION public.okeyix_reengagement_test_worker(text,uuid,uuid,uuid,text,jsonb);
NOTIFY pgrst,'reload schema';
COMMIT;

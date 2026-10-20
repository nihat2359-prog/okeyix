-- NOT APPLIED. Install after the first two migrations and staging acceptance.
BEGIN;
DO $check$
BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'STAT_DEPLOY_REQUIRES_POSTGRES'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_extension WHERE extname='pg_cron')
    THEN RAISE EXCEPTION 'STAT_PG_CRON_REQUIRED'; END IF;
END $check$;
-- Named scheduling is idempotent; no mobile timer or extra client request.
SELECT cron.schedule('okeyix-stat-projector','* * * * *',
  'SELECT okeyix_stat_private.process_events(250);');
COMMIT;

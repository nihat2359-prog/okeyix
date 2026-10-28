-- NOT APPLIED. Creates a DISABLED cron job. No HTTP request is made at install.
-- Requires 20261028000100 and existing pg_cron, pg_net, Vault extensions.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $$ BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'POSTGRES_REQUIRED'; END IF;
  IF to_regclass('cron.job') IS NULL OR to_regclass('vault.secrets') IS NULL
    OR NOT EXISTS(SELECT 1 FROM pg_extension WHERE extname='pg_net')
    OR to_regclass('okeyix_reengagement_private.settings') IS NULL
  THEN RAISE EXCEPTION 'REENGAGEMENT_PREREQUISITES_MISSING'; END IF;
  IF EXISTS(SELECT 1 FROM cron.job WHERE jobname='okeyix-reengagement-hourly') THEN
    RAISE EXCEPTION 'REENGAGEMENT_JOB_EXISTS_REVIEW_REQUIRED'; END IF;
  IF coalesce(current_setting('cron.timezone',true),'GMT') NOT IN ('UTC','GMT','Etc/UTC','Etc/GMT') THEN
    RAISE EXCEPTION 'REENGAGEMENT_CRON_TIMEZONE_REVIEW_REQUIRED'; END IF;
END $$;

CREATE FUNCTION okeyix_reengagement_private.invoke_worker() RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_url text; v_secret text; v_id bigint; v_now timestamptz:=clock_timestamp();
BEGIN
  IF NOT EXISTS(SELECT 1 FROM okeyix_reengagement_private.settings WHERE id AND enabled AND NOT dry_run)
    OR extract(hour FROM v_now AT TIME ZONE 'Europe/Istanbul') NOT BETWEEN 10 AND 20 THEN RETURN NULL; END IF;
  IF NOT EXISTS(SELECT 1 FROM okeyix_reengagement_private.candidates(v_now) WHERE reason='eligible') THEN RETURN NULL; END IF;
  SELECT decrypted_secret INTO STRICT v_url FROM vault.decrypted_secrets WHERE name='okeyix_reengagement_project_url';
  SELECT decrypted_secret INTO STRICT v_secret FROM vault.decrypted_secrets WHERE name='okeyix_reengagement_cron_secret';
  IF v_url !~ '^https://[a-z0-9-]+\.supabase\.co$' OR length(v_secret)<32 THEN
    RAISE EXCEPTION 'REENGAGEMENT_VAULT_CONFIGURATION_INVALID'; END IF;
  SELECT net.http_post(
    url:=v_url||'/functions/v1/process_reengagement_notifications',
    headers:=jsonb_build_object('Content-Type','application/json','x-reengagement-secret',v_secret),
    body:='{"mode":"process"}'::jsonb,timeout_milliseconds:=60000
  ) INTO v_id;
  RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION okeyix_reengagement_private.invoke_worker() FROM PUBLIC,anon,authenticated,service_role;

-- UTC 07:00..17:00 = Istanbul 10:00..20:00. Nothing is scheduled at 21:00.
-- Both schedule and deactivate happen in one transaction: never active at commit.
SELECT cron.schedule('okeyix-reengagement-hourly','0 7-17 * * *',
  'SELECT okeyix_reengagement_private.invoke_worker();');
-- Supabase postgres can manage jobs through cron.alter_job, not direct UPDATE.
SELECT cron.alter_job(jobid,active:=false) FROM cron.job WHERE jobname='okeyix-reengagement-hourly';
COMMIT;

-- LOCAL TEST ONLY. Mock scheduler/network: no external HTTP requests.
DO $$ BEGIN
  IF current_database()<>'okeyix_reengagement_test' THEN RAISE EXCEPTION 'LOCAL_TEST_DATABASE_REQUIRED'; END IF;
END $$;
CREATE SCHEMA cron;
CREATE TABLE cron.job(jobid bigserial PRIMARY KEY,jobname text,schedule text,command text,active boolean DEFAULT true);
CREATE FUNCTION cron.alter_job(job_id bigint,schedule text DEFAULT NULL,active boolean DEFAULT NULL)
RETURNS void LANGUAGE sql AS $$ UPDATE cron.job SET schedule=coalesce($2,cron.job.schedule),active=coalesce($3,cron.job.active) WHERE jobid=$1; $$;
INSERT INTO cron.job(jobname,schedule,command) VALUES('okeyix-reengagement-hourly','0 7-17 * * *','local mock');
CREATE SCHEMA vault;
CREATE TABLE vault.decrypted_secrets(name text,decrypted_secret text);
CREATE SCHEMA net;
CREATE FUNCTION net.http_post(url text,headers jsonb,body jsonb,timeout_milliseconds integer)
RETURNS bigint LANGUAGE sql AS $$ SELECT 1::bigint; $$;

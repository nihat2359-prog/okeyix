-- User-authorized policy: no daily quota, minute scheduler, one-off all-device campaign.
-- Installs capability only. A campaign must be explicitly prepared and started by postgres.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $$ BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'POSTGRES_REQUIRED'; END IF;
  IF coalesce(current_setting('cron.timezone',true),'GMT') NOT IN ('UTC','GMT','Etc/UTC','Etc/GMT') THEN
    RAISE EXCEPTION 'CRON_TIMEZONE_REVIEW_REQUIRED'; END IF;
END $$;

CREATE TABLE okeyix_reengagement_private.campaigns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_key text NOT NULL UNIQUE,
  title text NOT NULL CHECK(length(btrim(title)) BETWEEN 1 AND 80),
  body text NOT NULL CHECK(length(btrim(body)) BETWEEN 1 AND 300),
  status text NOT NULL DEFAULT 'prepared' CHECK(status IN ('prepared','running','paused','completed')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  expires_at timestamptz NOT NULL DEFAULT clock_timestamp()+interval '48 hours',
  completed_at timestamptz
);
CREATE UNIQUE INDEX one_running_renewal_campaign ON okeyix_reengagement_private.campaigns((true)) WHERE status='running';
CREATE TABLE okeyix_reengagement_private.campaign_deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id uuid NOT NULL REFERENCES okeyix_reengagement_private.campaigns(id),
  user_id uuid NOT NULL,
  device_id uuid NOT NULL,
  token_hash text NOT NULL CHECK(token_hash ~ '^[a-f0-9]{64}$'),
  status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','dispatching','accepted','rejected','invalid_token','unknown','cancelled')),
  queued_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  dispatched_at timestamptz,
  finished_at timestamptz,
  batch_id uuid,
  http_status integer CHECK(http_status BETWEEN 100 AND 599),
  error_code text CHECK(length(error_code)<=80),
  UNIQUE(campaign_id,token_hash)
);
CREATE INDEX ON okeyix_reengagement_private.campaign_deliveries(campaign_id,status,queued_at,id);
CREATE INDEX ON okeyix_reengagement_private.campaign_deliveries(user_id,dispatched_at DESC);
CREATE INDEX ON okeyix_reengagement_private.campaign_deliveries(token_hash) WHERE status='invalid_token';
ALTER TABLE okeyix_reengagement_private.campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE okeyix_reengagement_private.campaign_deliveries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON okeyix_reengagement_private.campaigns,okeyix_reengagement_private.campaign_deliveries FROM PUBLIC,anon,authenticated,service_role;

-- Resolve token ownership BEFORE filtering preferences/accounts, so an older row
-- cannot override the latest owner's opt-out. No raw token is stored in the queue.
CREATE FUNCTION okeyix_reengagement_private.campaign_devices()
RETURNS TABLE(device_id uuid,user_id uuid,token_hash text)
LANGUAGE sql STABLE SET search_path='' AS $$
  WITH latest AS (
    SELECT DISTINCT ON (btrim(d.push_token)) d.id,d.user_id,
      encode(sha256(convert_to(btrim(d.push_token),'UTF8')),'hex') AS token_hash
    FROM public.user_devices d
    WHERE nullif(btrim(d.push_token),'') IS NOT NULL
      AND lower(d.platform) IN ('ios','android')
    ORDER BY btrim(d.push_token),d.last_seen DESC NULLS LAST,d.created_at DESC NULLS LAST,d.id
  )
  SELECT d.id,d.user_id,d.token_hash FROM latest d
  JOIN public.profiles p ON p.id=d.user_id
  JOIN public.users u ON u.id=p.id
  JOIN auth.users a ON a.id=coalesce(u.auth_user_id,u.id)
  WHERE p.allow_game_invites IS TRUE AND NOT u.is_bot
    AND NOT u.is_banned AND NOT u.is_suspended AND a.deleted_at IS NULL
    AND (u.ban_until IS NULL OR u.ban_until AT TIME ZONE 'UTC'<=now())
    AND (u.suspension_until IS NULL OR u.suspension_until AT TIME ZONE 'UTC'<=now())
    AND (a.banned_until IS NULL OR a.banned_until<=now())
    AND NOT EXISTS(SELECT 1 FROM okeyix_reengagement_private.deliveries h
      WHERE h.token_hash=d.token_hash AND h.status='invalid_token')
    AND NOT EXISTS(SELECT 1 FROM okeyix_reengagement_private.campaign_deliveries h
      WHERE h.token_hash=d.token_hash AND h.status='invalid_token');
$$;

CREATE FUNCTION okeyix_reengagement_private.prepare_campaign(p_key text,p_title text,p_body text)
RETURNS uuid LANGUAGE plpgsql SET search_path='' AS $$
DECLARE v_id uuid;
BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'POSTGRES_REQUIRED'; END IF;
  -- A stable key and unique token constraint prevent a rerun from resending.
  INSERT INTO okeyix_reengagement_private.campaigns(campaign_key,title,body)
    VALUES(p_key,p_title,p_body) RETURNING id INTO v_id;
  INSERT INTO okeyix_reengagement_private.campaign_deliveries(campaign_id,user_id,device_id,token_hash)
    SELECT v_id,d.user_id,d.device_id,d.token_hash FROM okeyix_reengagement_private.campaign_devices() d;
  RETURN v_id;
END $$;

-- Patch only the exact deployed token-policy version; keep existing history and rules.
DO $patch$
DECLARE f regprocedure; body text; definition text;
  quota_block text:=$old$    SELECT count(*) INTO v_count FROM okeyix_reengagement_private.deliveries
      WHERE reserved_at>=(date_trunc('day',v_now AT TIME ZONE 'Europe/Istanbul') AT TIME ZONE 'Europe/Istanbul');
    IF v_count>=s.daily_limit THEN RETURN jsonb_build_object('skipped','daily_limit'); END IF;
$old$;
BEGIN
  PERFORM 1 FROM okeyix_reengagement_private.settings WHERE id FOR UPDATE;
  f:='public.okeyix_reengagement_worker(text,uuid,jsonb)'::regprocedure;
  SELECT replace(prosrc,chr(13)||chr(10),chr(10)) INTO body FROM pg_proc WHERE oid=f;
  IF md5(body)<>'63c16d946ce442d3dfb1be9f90c8d7f8' OR strpos(body,quota_block)=0 THEN
    RAISE EXCEPTION 'WORKER_SOURCE_CHANGED_REVIEW_REQUIRED'; END IF;
  definition:=replace(pg_get_functiondef(f),chr(13)||chr(10),chr(10));
  definition:=replace(definition,quota_block,'');
  definition:=replace(definition,'''enabled'',s.enabled,',
    '''enabled'',s.enabled AND NOT EXISTS(SELECT 1 FROM okeyix_reengagement_private.campaigns WHERE status=''running''),');
  definition:=replace(definition,'IF NOT s.enabled OR s.dry_run OR v_hour<10 OR v_hour>=21 THEN',
    'IF NOT s.enabled OR s.dry_run OR v_hour<10 OR v_hour>=21 OR EXISTS(SELECT 1 FROM okeyix_reengagement_private.campaigns WHERE status=''running'') THEN');
  EXECUTE definition;

  f:='okeyix_reengagement_private.candidates(timestamptz)'::regprocedure;
  SELECT replace(prosrc,chr(13)||chr(10),chr(10)) INTO body FROM pg_proc WHERE oid=f;
  IF md5(body)<>'00f9b784925898d0051f619583719cc4' THEN
    RAISE EXCEPTION 'CANDIDATES_SOURCE_CHANGED_REVIEW_REQUIRED'; END IF;
  definition:=replace(pg_get_functiondef(f),chr(13)||chr(10),chr(10));
  definition:=replace(definition,'      WHEN d.id IS NULL THEN ''no_valid_token''',
    $new$      WHEN EXISTS(SELECT 1 FROM okeyix_reengagement_private.campaign_deliveries h
        WHERE h.user_id=p.id AND h.dispatched_at>p_at-make_interval(hours=>s.cooldown_hours)) THEN 'campaign_cooldown'
      WHEN d.id IS NULL THEN 'no_valid_token'$new$);
  definition:=replace(definition,'    ORDER BY ud.last_seen DESC NULLS LAST,ud.created_at DESC NULLS LAST,ud.id',
    $new$      AND NOT EXISTS(SELECT 1 FROM okeyix_reengagement_private.campaign_deliveries h
        WHERE h.token_hash=encode(sha256(convert_to(btrim(ud.push_token),'UTF8')),'hex')
          AND h.status='invalid_token')
    ORDER BY ud.last_seen DESC NULLS LAST,ud.created_at DESC NULLS LAST,ud.id$new$);
  EXECUTE definition;
END $patch$;
-- There is no configurable or hard-coded daily quota after this migration.
ALTER TABLE okeyix_reengagement_private.settings DROP COLUMN daily_limit;
UPDATE okeyix_reengagement_private.settings SET batch_size=25 WHERE id;

CREATE FUNCTION public.okeyix_renewal_worker(p_action text,p_id uuid DEFAULT NULL,p_result jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c okeyix_reengagement_private.campaigns%ROWTYPE;
  r record; v_now timestamptz:=clock_timestamp(); v_batch uuid:=gen_random_uuid();
  v_items jsonb:='[]'; v_count integer:=0; v_result jsonb;
BEGIN
  -- Same campaign lock serializes claim/finish and operator pause.
  SELECT * INTO c FROM okeyix_reengagement_private.campaigns
    WHERE (p_id IS NULL AND status='running') OR id=p_id ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('enabled',false,'pending',0,'mode','no_campaign'); END IF;
  IF p_action='preview' THEN
    RETURN jsonb_build_object('enabled',c.status='running' AND c.expires_at>v_now,
      'dry_run',false,'within_send_window',extract(hour FROM v_now AT TIME ZONE 'Europe/Istanbul') BETWEEN 10 AND 20,
      'campaign_id',c.id,'campaign_key',c.campaign_key,'status',c.status,
      'pending',(SELECT count(*) FROM okeyix_reengagement_private.campaign_deliveries WHERE campaign_id=c.id AND status='pending'),
      'recoverable',(SELECT count(*) FROM okeyix_reengagement_private.campaign_deliveries WHERE campaign_id=c.id AND status='dispatching' AND dispatched_at<v_now-interval '5 minutes'),
      'counts',(SELECT jsonb_object_agg(status,n) FROM (SELECT status,count(*) n FROM okeyix_reengagement_private.campaign_deliveries WHERE campaign_id=c.id GROUP BY status) s));
  END IF;
  IF p_action='finish_batch' THEN
    IF jsonb_typeof(p_result->'results') IS DISTINCT FROM 'array' OR jsonb_array_length(p_result->'results')>5 THEN
      RAISE EXCEPTION 'INVALID_RESULTS'; END IF;
    FOR v_result IN SELECT value FROM jsonb_array_elements(p_result->'results') LOOP
      IF coalesce(v_result->>'status','') NOT IN ('accepted','rejected','invalid_token','unknown')
        OR coalesce(v_result->>'code','') !~ '^[A-Z0-9_]{0,80}$' THEN RAISE EXCEPTION 'INVALID_RESULT'; END IF;
      UPDATE okeyix_reengagement_private.campaign_deliveries SET status=v_result->>'status',finished_at=v_now,
        http_status=(v_result->>'http_status')::integer,error_code=v_result->>'code'
        WHERE id=(v_result->>'id')::uuid AND campaign_id=c.id AND status='dispatching'
          AND batch_id=(p_result->>'batch_id')::uuid;
      IF FOUND THEN v_count:=v_count+1; END IF;
    END LOOP;
    IF NOT EXISTS(SELECT 1 FROM okeyix_reengagement_private.campaign_deliveries
      WHERE campaign_id=c.id AND status IN ('pending','dispatching')) THEN
      UPDATE okeyix_reengagement_private.campaigns SET status='completed',completed_at=v_now WHERE id=c.id;
    END IF;
    RETURN jsonb_build_object('recorded',v_count=jsonb_array_length(p_result->'results'),'count',v_count);
  END IF;
  IF p_action IS DISTINCT FROM 'claim_batch' THEN RAISE EXCEPTION 'INVALID_ACTION'; END IF;
  IF c.status<>'running' OR c.expires_at<=v_now
    OR extract(hour FROM v_now AT TIME ZONE 'Europe/Istanbul') NOT BETWEEN 10 AND 20 THEN
    RETURN jsonb_build_object('items','[]'::jsonb,'skipped','paused_expired_or_outside_window'); END IF;
  UPDATE okeyix_reengagement_private.campaign_deliveries SET status='unknown',finished_at=v_now,
    error_code='WORKER_INTERRUPTED' WHERE campaign_id=c.id AND status='dispatching' AND dispatched_at<v_now-interval '5 minutes';
  -- Recheck the latest token owner, account, preferences and invalid-token history.
  -- A pending device that no longer matches is cancelled, never redirected.
  UPDATE okeyix_reengagement_private.campaign_deliveries h SET status='cancelled',finished_at=v_now,error_code='ELIGIBILITY_CHANGED'
    WHERE h.campaign_id=c.id AND h.status='pending' AND NOT EXISTS(
      SELECT 1 FROM okeyix_reengagement_private.campaign_devices() d
      WHERE d.device_id=h.device_id AND d.user_id=h.user_id AND d.token_hash=h.token_hash);
  FOR r IN SELECT h.id,btrim(d.push_token) AS token FROM okeyix_reengagement_private.campaign_deliveries h
    JOIN public.user_devices d ON d.id=h.device_id AND d.user_id=h.user_id
      AND encode(sha256(convert_to(btrim(d.push_token),'UTF8')),'hex')=h.token_hash
    WHERE h.campaign_id=c.id AND h.status='pending' ORDER BY h.queued_at,h.id LIMIT 5 FOR UPDATE OF h
  LOOP
    UPDATE okeyix_reengagement_private.campaign_deliveries SET status='dispatching',dispatched_at=v_now,batch_id=v_batch WHERE id=r.id;
    v_items:=v_items||jsonb_build_array(jsonb_build_object('id',r.id,'token',r.token,'title',c.title,'body',c.body,'category','renewal','campaign_key',c.campaign_key));
  END LOOP;
  IF jsonb_array_length(v_items)=0 AND NOT EXISTS(SELECT 1 FROM okeyix_reengagement_private.campaign_deliveries
    WHERE campaign_id=c.id AND status IN ('pending','dispatching')) THEN
    UPDATE okeyix_reengagement_private.campaigns SET status='completed',completed_at=v_now WHERE id=c.id;
  END IF;
  RETURN jsonb_build_object('campaign_id',c.id,'batch_id',v_batch,'items',v_items);
END $$;
REVOKE ALL ON FUNCTION public.okeyix_renewal_worker(text,uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.okeyix_renewal_worker(text,uuid,jsonb) TO service_role;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA okeyix_reengagement_private FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION okeyix_reengagement_private.invoke_worker() RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_url text; v_secret text; v_id bigint; v_mode text; v_now timestamptz:=clock_timestamp();
BEGIN
  IF extract(hour FROM v_now AT TIME ZONE 'Europe/Istanbul') NOT BETWEEN 10 AND 20 THEN RETURN NULL; END IF;
  UPDATE okeyix_reengagement_private.campaigns SET status='paused' WHERE status='running' AND expires_at<=v_now;
  IF EXISTS(SELECT 1 FROM okeyix_reengagement_private.campaigns WHERE status='running' AND expires_at>v_now) THEN
    v_mode:='campaign_process';
  ELSE
    IF NOT EXISTS(SELECT 1 FROM okeyix_reengagement_private.settings WHERE id AND enabled AND NOT dry_run)
      OR NOT EXISTS(SELECT 1 FROM okeyix_reengagement_private.candidates(v_now) WHERE reason='eligible') THEN RETURN NULL; END IF;
    v_mode:='process';
  END IF;
  SELECT decrypted_secret INTO STRICT v_url FROM vault.decrypted_secrets WHERE name='okeyix_reengagement_project_url';
  SELECT decrypted_secret INTO STRICT v_secret FROM vault.decrypted_secrets WHERE name='okeyix_reengagement_cron_secret';
  IF v_url !~ '^https://[a-z0-9-]+\.supabase\.co$' OR length(v_secret)<32 THEN
    RAISE EXCEPTION 'REENGAGEMENT_VAULT_CONFIGURATION_INVALID'; END IF;
  SELECT net.http_post(url:=v_url||'/functions/v1/process_reengagement_notifications',
    headers:=jsonb_build_object('Content-Type','application/json','x-reengagement-secret',v_secret),
    body:=jsonb_build_object('mode',v_mode),timeout_milliseconds:=60000) INTO v_id;
  RETURN v_id;
END $$;
-- Same job, new cadence. Small requests bound runtime; there is no daily ceiling.
SELECT cron.alter_job(jobid,schedule:='* 7-17 * * *') FROM cron.job WHERE jobname='okeyix-reengagement-hourly';
NOTIFY pgrst,'reload schema';
COMMIT;

-- NOT APPLIED. Supabase-only. No existing mobile/invitation objects are changed.
-- Unknown permission is excluded. A token is NOT evidence of permission.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $$ BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'POSTGRES_REQUIRED'; END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
    AND table_name='profiles' AND column_name='last_seen_at' AND udt_name='timestamptz')
    OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public'
    AND table_name='user_devices' AND column_name='last_seen' AND udt_name='timestamptz')
  THEN RAISE EXCEPTION 'REENGAGEMENT_SCHEMA_REVIEW_REQUIRED'; END IF;
END $$;

CREATE SCHEMA okeyix_reengagement_private;
REVOKE ALL ON SCHEMA okeyix_reengagement_private FROM PUBLIC,anon,authenticated,service_role;

CREATE TABLE okeyix_reengagement_private.settings (
  id boolean PRIMARY KEY DEFAULT true CHECK(id),
  enabled boolean NOT NULL DEFAULT false,
  dry_run boolean NOT NULL DEFAULT true,
  thresholds_hours integer[] NOT NULL DEFAULT ARRAY[48,120,288,456],
  cooldown_hours integer NOT NULL DEFAULT 72 CHECK(cooldown_hours>=72),
  batch_size integer NOT NULL DEFAULT 10 CHECK(batch_size BETWEEN 1 AND 25),
  daily_limit integer NOT NULL DEFAULT 100 CHECK(daily_limit BETWEEN 1 AND 1000),
  messages jsonb NOT NULL DEFAULT '[
    {"title":"Masan seni bekliyor","body":"Okeyix’te yeni bir ele ne dersin? Müsait olduğunda aramıza katıl."},
    {"title":"Yeniden görüşelim","body":"Biraz mola verdik. Hazır olduğunda Okeyix masaları seni bekliyor."},
    {"title":"Bir el Okeyix?","body":"Oyuna dönmek istersen masalar burada. Seni yeniden görmek isteriz."},
    {"title":"Okeyix’ten bir merhaba","body":"Bu son hatırlatmamız. Ne zaman istersen yeniden aramıza katılabilirsin."}
  ]'::jsonb,
  CHECK(array_length(thresholds_hours,1)=4 AND array_lower(thresholds_hours,1)=1
    AND array_position(thresholds_hours,NULL) IS NULL
    AND thresholds_hours[1]>=48 AND thresholds_hours[2]>=120
    AND thresholds_hours[3]>=288 AND thresholds_hours[4]>=456
    AND thresholds_hours[1]<thresholds_hours[2] AND thresholds_hours[2]<thresholds_hours[3]
    AND thresholds_hours[3]<thresholds_hours[4]),
  CHECK(jsonb_typeof(messages)='array' AND jsonb_array_length(messages)=4)
);
INSERT INTO okeyix_reengagement_private.settings DEFAULT VALUES;

-- Separate permission evidence is necessary: the existing schema has none.
-- No rows are backfilled from tokens or allow_game_invites.
-- Only an operator with independently verified evidence may record permission.
CREATE TABLE okeyix_reengagement_private.permissions (
  user_id uuid NOT NULL,
  device_id uuid NOT NULL,
  token_hash text NOT NULL CHECK(token_hash ~ '^[a-f0-9]{64}$'),
  reminders_allowed boolean NOT NULL DEFAULT false,
  platform_permission text NOT NULL DEFAULT 'unknown'
    CHECK(platform_permission IN ('unknown','denied','granted')),
  verified_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  expires_at timestamptz NOT NULL,
  evidence text NOT NULL CHECK(length(btrim(evidence)) BETWEEN 8 AND 500),
  PRIMARY KEY(user_id,device_id),
  CHECK(expires_at>verified_at AND expires_at<=verified_at+interval '30 days')
);

CREATE TABLE okeyix_reengagement_private.deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  cycle_at timestamptz NOT NULL,
  stage integer NOT NULL CHECK(stage BETWEEN 1 AND 4),
  device_id uuid NOT NULL,
  token_hash text NOT NULL,
  title text NOT NULL,
  body text NOT NULL,
  status text NOT NULL DEFAULT 'reserved'
    CHECK(status IN ('reserved','dispatching','accepted','rejected','invalid_token','unknown','cancelled')),
  reserved_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  dispatched_at timestamptz,
  finished_at timestamptz,
  http_status integer CHECK(http_status BETWEEN 100 AND 599),
  error_code text CHECK(length(error_code)<=80),
  UNIQUE(user_id,cycle_at,stage)
);
CREATE INDEX ON okeyix_reengagement_private.deliveries(user_id,reserved_at DESC);
CREATE INDEX ON okeyix_reengagement_private.deliveries(token_hash) WHERE status='invalid_token';
CREATE INDEX ON okeyix_reengagement_private.deliveries(reserved_at);
ALTER TABLE okeyix_reengagement_private.settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE okeyix_reengagement_private.permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE okeyix_reengagement_private.deliveries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA okeyix_reengagement_private FROM PUBLIC,anon,authenticated,service_role;

-- Internal evaluator. An operator can inspect reasons without exposing tokens.
-- p_at exists for deterministic LOCAL tests; the public worker always uses server time.
CREATE FUNCTION okeyix_reengagement_private.candidates(p_at timestamptz DEFAULT clock_timestamp())
RETURNS TABLE(user_id uuid,cycle_at timestamptz,stage integer,device_id uuid,
  token_hash text,reason text)
LANGUAGE sql STABLE SET search_path='' AS $$
  SELECT p.id,p.last_seen_at,st.stage,d.id,d.token_hash,
    CASE
      WHEN u.id IS NULL OR a.id IS NULL OR a.deleted_at IS NOT NULL THEN 'deleted_or_missing_account'
      WHEN u.is_bot THEN 'bot'
      WHEN u.is_banned OR u.is_suspended
        OR u.ban_until AT TIME ZONE 'UTC'>p_at
        OR u.suspension_until AT TIME ZONE 'UTC'>p_at
        OR a.banned_until>p_at THEN 'blocked'
      WHEN NOT p.allow_game_invites THEN 'existing_preference_disabled'
      WHEN p.last_seen_at IS NULL THEN 'activity_unknown'
      WHEN p.last_seen_at>p_at THEN 'activity_in_future'
      WHEN p.last_seen_at>p_at-make_interval(hours=>s.thresholds_hours[1]) THEN 'active'
      WHEN EXISTS(SELECT 1 FROM okeyix_reengagement_private.deliveries h
        WHERE h.user_id=p.id AND h.cycle_at=p.last_seen_at AND h.stage>=st.stage) THEN 'stage_already_reserved'
      WHEN EXISTS(SELECT 1 FROM okeyix_reengagement_private.deliveries h
        WHERE h.user_id=p.id AND h.reserved_at>p_at-make_interval(hours=>s.cooldown_hours)) THEN 'cooldown'
      WHEN d.id IS NULL THEN 'no_valid_token'
      WHEN pe.user_id IS NULL THEN 'permission_unknown'
      WHEN NOT pe.reminders_allowed OR pe.platform_permission='denied' THEN 'permission_denied'
      WHEN pe.platform_permission<>'granted' THEN 'permission_unknown'
      WHEN pe.token_hash<>d.token_hash OR pe.expires_at<=p_at OR pe.verified_at>p_at
        THEN 'permission_unverified_or_expired'
      ELSE 'eligible'
    END
  FROM public.profiles p
  CROSS JOIN okeyix_reengagement_private.settings s
  LEFT JOIN public.users u ON u.id=p.id
  LEFT JOIN auth.users a ON a.id=coalesce(u.auth_user_id,u.id)
  LEFT JOIN LATERAL (
    SELECT max(i)::integer AS stage FROM generate_series(1,4) i
    WHERE p.last_seen_at<=p_at-make_interval(hours=>s.thresholds_hours[i])
  ) st ON true
  LEFT JOIN LATERAL (
    SELECT ud.id,encode(sha256(convert_to(btrim(ud.push_token),'UTF8')),'hex') AS token_hash
    FROM public.user_devices ud
    WHERE ud.user_id=p.id AND nullif(btrim(ud.push_token),'') IS NOT NULL
      AND lower(ud.platform) IN ('ios','android') AND ud.last_seen<=p_at
      AND NOT EXISTS(SELECT 1 FROM okeyix_reengagement_private.deliveries h
        WHERE h.token_hash=encode(sha256(convert_to(btrim(ud.push_token),'UTF8')),'hex')
          AND h.status='invalid_token')
    ORDER BY ud.last_seen DESC NULLS LAST,ud.created_at DESC NULLS LAST,ud.id
    LIMIT 1
  ) d ON true
  LEFT JOIN okeyix_reengagement_private.permissions pe ON pe.user_id=p.id AND pe.device_id=d.id;
$$;

CREATE FUNCTION public.okeyix_reengagement_worker(p_action text,p_id uuid DEFAULT NULL,
  p_result jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE s okeyix_reengagement_private.settings%ROWTYPE;
  h okeyix_reengagement_private.deliveries%ROWTYPE;
  c record; v_now timestamptz:=clock_timestamp(); v_token text; v_reason text;
  v_hour integer; v_count integer; v_messages jsonb; v_outcome text;
BEGIN
  -- This row lock serializes reservations, limits and operator enable/disable.
  SELECT * INTO STRICT s FROM okeyix_reengagement_private.settings WHERE id FOR UPDATE;
  v_hour:=extract(hour FROM v_now AT TIME ZONE 'Europe/Istanbul');
  IF p_action='preview' THEN
    RETURN jsonb_build_object('enabled',s.enabled,'dry_run',s.dry_run,
      'within_send_window',v_hour>=10 AND v_hour<21,'batch_size',s.batch_size,
      'reasons',(SELECT jsonb_object_agg(reason,n) FROM (
        SELECT reason,count(*) n FROM okeyix_reengagement_private.candidates(v_now) GROUP BY reason) q),
      'permission_note','Tokens and allow_game_invites do not establish reminder consent or OS permission');
  END IF;
  IF p_action='finish' THEN
    v_outcome:=p_result->>'status';
    IF v_outcome IS NULL OR v_outcome NOT IN ('accepted','rejected','invalid_token','unknown') THEN
      RAISE EXCEPTION 'INVALID_RESULT'; END IF;
    IF coalesce(p_result->>'code','') !~ '^[A-Z0-9_]{0,80}$' THEN RAISE EXCEPTION 'INVALID_ERROR_CODE'; END IF;
    UPDATE okeyix_reengagement_private.deliveries SET status=v_outcome,
      finished_at=v_now,http_status=(p_result->>'http_status')::integer,
      error_code=p_result->>'code' WHERE id=p_id AND status='dispatching';
    RETURN jsonb_build_object('recorded',FOUND);
  END IF;
  IF p_action NOT IN ('claim','authorize') OR p_action IS NULL THEN RAISE EXCEPTION 'INVALID_ACTION'; END IF;
  IF NOT s.enabled OR s.dry_run OR v_hour<10 OR v_hour>=21 THEN
    RETURN jsonb_build_object('skipped','disabled_dry_run_or_outside_window'); END IF;

  IF p_action='claim' THEN
    -- Never retry an external request whose outcome may be unknown.
    UPDATE okeyix_reengagement_private.deliveries SET status='unknown',finished_at=v_now,
      error_code='WORKER_INTERRUPTED' WHERE status IN ('reserved','dispatching')
        AND reserved_at<v_now-interval '5 minutes';
    SELECT count(*) INTO v_count FROM okeyix_reengagement_private.deliveries
      WHERE reserved_at>=(date_trunc('day',v_now AT TIME ZONE 'Europe/Istanbul') AT TIME ZONE 'Europe/Istanbul');
    IF v_count>=s.daily_limit THEN RETURN jsonb_build_object('skipped','daily_limit'); END IF;
    SELECT * INTO c FROM okeyix_reengagement_private.candidates(v_now)
      WHERE reason='eligible' ORDER BY cycle_at,user_id LIMIT 1;
    IF NOT FOUND THEN RETURN jsonb_build_object('skipped','no_eligible_recipient'); END IF;
    v_messages:=s.messages->(c.stage-1);
    IF jsonb_typeof(v_messages->'title') IS DISTINCT FROM 'string'
      OR jsonb_typeof(v_messages->'body') IS DISTINCT FROM 'string'
      OR length(btrim(v_messages->>'title')) NOT BETWEEN 1 AND 80
      OR length(btrim(v_messages->>'body')) NOT BETWEEN 1 AND 300
    THEN RAISE EXCEPTION 'INVALID_MESSAGE_CONFIGURATION'; END IF;
    INSERT INTO okeyix_reengagement_private.deliveries(user_id,cycle_at,stage,device_id,token_hash,title,body,reserved_at)
      VALUES(c.user_id,c.cycle_at,c.stage,c.device_id,c.token_hash,v_messages->>'title',v_messages->>'body',v_now)
      RETURNING * INTO h;
    RETURN jsonb_build_object('id',h.id);
  END IF;

  SELECT * INTO h FROM okeyix_reengagement_private.deliveries WHERE id=p_id FOR UPDATE;
  IF NOT FOUND OR h.status<>'reserved' THEN RETURN jsonb_build_object('skipped','not_reserved'); END IF;
  -- Re-evaluate account, activity, consent, device ownership and newest token
  -- immediately before external dispatch. Ignore only this reservation's own gates.
  SELECT reason INTO v_reason FROM okeyix_reengagement_private.candidates(v_now)
    WHERE user_id=h.user_id AND cycle_at=h.cycle_at AND stage=h.stage
      AND device_id=h.device_id AND token_hash=h.token_hash;
  -- The evaluator reports this row's reservation before permission checks. Explicit
  -- permission recheck below prevents that ordering from masking a revoked permission.
  SELECT btrim(d.push_token) INTO v_token FROM public.user_devices d
    JOIN okeyix_reengagement_private.permissions pe ON pe.user_id=d.user_id AND pe.device_id=d.id
    WHERE d.id=h.device_id AND d.user_id=h.user_id
      AND pe.reminders_allowed AND pe.platform_permission='granted'
      AND pe.verified_at<=v_now AND pe.expires_at>v_now
      AND pe.token_hash=h.token_hash
      AND encode(sha256(convert_to(btrim(d.push_token),'UTF8')),'hex')=h.token_hash;
  IF v_reason IS DISTINCT FROM 'stage_already_reserved' OR v_token IS NULL
      OR h.reserved_at<v_now-interval '60 seconds' THEN
    UPDATE okeyix_reengagement_private.deliveries SET status='cancelled',finished_at=v_now,
      error_code='ELIGIBILITY_CHANGED' WHERE id=h.id;
    RETURN jsonb_build_object('skipped','eligibility_changed');
  END IF;
  UPDATE okeyix_reengagement_private.deliveries SET status='dispatching',dispatched_at=v_now WHERE id=h.id;
  RETURN jsonb_build_object('id',h.id,'token',v_token,'title',h.title,'body',h.body);
END $$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA okeyix_reengagement_private FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.okeyix_reengagement_worker(text,uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.okeyix_reengagement_worker(text,uuid,jsonb) TO service_role;
COMMIT;

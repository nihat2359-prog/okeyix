-- NOT APPLIED. Standalone manual test facility; no automation migration required.
-- FINAL SECURITY REVIEW: requires service_role AND a separate RPC capability.
-- Creates no cron and never reads/updates production automation settings.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $$ DECLARE missing text; BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'POSTGRES_REQUIRED'; END IF;
  IF to_regnamespace('okeyix_reengagement_test_private') IS NOT NULL
    OR to_regprocedure('public.okeyix_reengagement_test_worker(text,uuid,uuid,uuid,jsonb)') IS NOT NULL
    OR to_regprocedure('public.okeyix_reengagement_test_worker(text,uuid,uuid,uuid,text,jsonb)') IS NOT NULL
  THEN RAISE EXCEPTION 'TEST_PUSH_ALREADY_INSTALLED_REVIEW_REQUIRED_NO_CHANGES'; END IF;
  SELECT string_agg(e.s||'.'||e.t||'.'||e.c||' expected '||e.typ,', ') INTO missing
  FROM (VALUES
    ('public','profiles','id','uuid'),('public','profiles','allow_game_invites','bool'),
    ('public','users','id','uuid'),('public','users','auth_user_id','uuid'),
    ('public','users','is_bot','bool'),('public','users','is_banned','bool'),
    ('public','users','is_suspended','bool'),('public','users','ban_until','timestamp'),
    ('public','users','suspension_until','timestamp'),
    ('auth','users','id','uuid'),('auth','users','deleted_at','timestamptz'),
    ('auth','users','banned_until','timestamptz'),
    ('public','user_devices','id','uuid'),('public','user_devices','user_id','uuid'),
    ('public','user_devices','platform','text'),('public','user_devices','push_token','text')
  ) AS e(s,t,c,typ)
  LEFT JOIN information_schema.columns a ON a.table_schema=e.s AND a.table_name=e.t
    AND a.column_name=e.c AND a.udt_name=e.typ WHERE a.column_name IS NULL;
  IF missing IS NOT NULL THEN RAISE EXCEPTION 'TEST_PUSH_SCHEMA_MISMATCH: %',missing; END IF;
END $$;
CREATE SCHEMA okeyix_reengagement_test_private;
REVOKE ALL ON SCHEMA okeyix_reengagement_test_private FROM PUBLIC,anon,authenticated,service_role;
-- A different service_role process cannot read/replace this hash through this RPC.
-- Set only the SHA-256 HEX of the Edge-only RPC secret, never the raw secret.
CREATE TABLE okeyix_reengagement_test_private.authorization (
  id boolean PRIMARY KEY DEFAULT true CHECK(id),
  rpc_secret_hash text CHECK(rpc_secret_hash ~ '^[a-f0-9]{64}$')
);
INSERT INTO okeyix_reengagement_test_private.authorization DEFAULT VALUES;
ALTER TABLE okeyix_reengagement_test_private.authorization ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON okeyix_reengagement_test_private.authorization FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE okeyix_reengagement_test_private.tickets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  device_id uuid NOT NULL,
  token_hash text NOT NULL CHECK(token_hash ~ '^[a-f0-9]{64}$'),
  status text NOT NULL DEFAULT 'draft' CHECK(status IN
    ('draft','approved','dispatching','accepted','rejected','invalid_token','unknown')),
  test_consent_confirmed boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  approved_at timestamptz,
  expires_at timestamptz,
  dispatched_at timestamptz,
  receipt_hash text CHECK(receipt_hash ~ '^[a-f0-9]{64}$'),
  finished_at timestamptz,
  http_status integer CHECK(http_status BETWEEN 100 AND 599),
  error_code text CHECK(length(error_code)<=80),
  CHECK(status='draft' OR (test_consent_confirmed AND approved_at IS NOT NULL
    AND expires_at IS NOT NULL AND expires_at>approved_at AND expires_at<=approved_at+interval '15 minutes')),
  CHECK((status IN ('draft','approved') AND dispatched_at IS NULL AND receipt_hash IS NULL AND finished_at IS NULL)
    OR (status='dispatching' AND dispatched_at IS NOT NULL AND receipt_hash IS NOT NULL AND finished_at IS NULL)
    OR (status IN ('accepted','rejected','invalid_token','unknown') AND dispatched_at IS NOT NULL
      AND receipt_hash IS NOT NULL AND finished_at IS NOT NULL))
);
ALTER TABLE okeyix_reengagement_test_private.tickets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON okeyix_reengagement_test_private.tickets FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.okeyix_reengagement_test_worker(p_action text,p_ticket_id uuid,
  p_user_id uuid,p_device_id uuid,p_rpc_secret text,p_result jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE t okeyix_reengagement_test_private.tickets%ROWTYPE;
  v_token text; v_reason text; v_now timestamptz:=clock_timestamp(); v_outcome text;
  v_secret_hash text; v_receipt text; v_http integer; v_code text;
BEGIN
  -- EXECUTE permission alone is intentionally insufficient. Check capability
  -- before inspecting any ticket. Raw capability is never stored or returned.
  SELECT rpc_secret_hash INTO v_secret_hash FROM okeyix_reengagement_test_private.authorization WHERE id;
  IF v_secret_hash IS NULL OR p_rpc_secret IS NULL OR length(p_rpc_secret) NOT BETWEEN 32 AND 256
    OR encode(sha256(convert_to(p_rpc_secret,'UTF8')),'hex') IS DISTINCT FROM v_secret_hash
  THEN RAISE EXCEPTION 'TEST_RPC_UNAUTHORIZED' USING errcode='42501'; END IF;
  SELECT * INTO t FROM okeyix_reengagement_test_private.tickets
    WHERE id=p_ticket_id AND user_id=p_user_id AND device_id=p_device_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ready',false,'reason','TICKET_TARGET_MISMATCH'); END IF;
  IF p_action='finish' THEN
    IF t.status<>'dispatching' THEN RETURN jsonb_build_object('recorded',false,'reason','NOT_DISPATCHING'); END IF;
    v_receipt:=p_result->>'receipt';
    IF v_receipt IS NULL OR v_receipt !~ '^[a-f0-9]{64}$'
      OR encode(sha256(convert_to(v_receipt,'UTF8')),'hex') IS DISTINCT FROM t.receipt_hash
    THEN RAISE EXCEPTION 'INVALID_TEST_RECEIPT' USING errcode='42501'; END IF;
    v_outcome:=p_result->>'status';
    v_code:=p_result->>'code';
    IF p_result ? 'http_status' AND jsonb_typeof(p_result->'http_status')<>'null' THEN
      IF jsonb_typeof(p_result->'http_status')<>'number' OR (p_result->>'http_status') !~ '^[1-5][0-9]{2}$'
      THEN RAISE EXCEPTION 'INVALID_TEST_HTTP_STATUS'; END IF;
      v_http:=(p_result->>'http_status')::integer;
    END IF;
    IF NOT coalesce(
      (v_outcome='accepted' AND v_http BETWEEN 200 AND 299 AND v_code='FCM_ACCEPTED')
      OR (v_outcome='invalid_token' AND v_http=404 AND v_code='UNREGISTERED')
      OR (v_outcome='unknown' AND ((v_http IS NULL AND v_code='NETWORK_OUTCOME_UNKNOWN')
        OR (v_http BETWEEN 200 AND 299 AND v_code='FCM_RESPONSE_UNRECOGNIZED')))
      OR (v_outcome='rejected' AND v_http BETWEEN 400 AND 599 AND (v_code IN
        ('INVALID_ARGUMENT','SENDER_ID_MISMATCH','QUOTA_EXCEEDED','UNAVAILABLE','INTERNAL','THIRD_PARTY_AUTH_ERROR')
        OR v_code='FCM_HTTP_'||v_http::text)),false)
    THEN RAISE EXCEPTION 'INVALID_TEST_RESULT'; END IF;
    UPDATE okeyix_reengagement_test_private.tickets SET status=v_outcome,finished_at=v_now,
      http_status=v_http,error_code=v_code
    WHERE id=t.id AND status='dispatching' AND receipt_hash=t.receipt_hash;
    RETURN jsonb_build_object('recorded',FOUND);
  END IF;
  IF p_action IS NULL OR p_action NOT IN ('preview','consume') THEN RAISE EXCEPTION 'INVALID_TEST_ACTION'; END IF;
  -- No inactive-period, production enabled/dry_run, or automatic send-window gate.
  -- This is a specifically consented, short-lived single-device manual test.
  SELECT CASE
    WHEN u.id IS NULL OR a.id IS NULL OR a.deleted_at IS NOT NULL THEN 'ACCOUNT_MISSING_OR_DELETED'
    WHEN u.is_bot OR u.is_banned OR u.is_suspended OR a.banned_until>v_now
      OR u.ban_until AT TIME ZONE 'UTC'>v_now OR u.suspension_until AT TIME ZONE 'UTC'>v_now THEN 'ACCOUNT_BLOCKED'
    WHEN NOT p.allow_game_invites THEN 'EXISTING_PREFERENCE_DISABLED'
    WHEN d.id IS NULL OR lower(coalesce(d.platform,'')) NOT IN ('ios','android')
      OR nullif(btrim(d.push_token),'') IS NULL THEN 'DEVICE_UNAVAILABLE'
    WHEN encode(sha256(convert_to(btrim(d.push_token),'UTF8')),'hex')<>t.token_hash THEN 'TOKEN_CHANGED'
    WHEN t.status<>'approved' THEN 'TICKET_NOT_APPROVED_OR_ALREADY_CONSUMED'
    WHEN NOT t.test_consent_confirmed OR t.approved_at IS NULL OR t.approved_at>v_now
      OR t.expires_at IS NULL OR t.expires_at<=v_now
      OR t.expires_at>t.approved_at+interval '15 minutes' THEN 'TEST_CONSENT_MISSING_OR_EXPIRED'
    ELSE 'READY' END,btrim(d.push_token)
  INTO v_reason,v_token
  FROM public.profiles p
  LEFT JOIN public.users u ON u.id=p.id
  LEFT JOIN auth.users a ON a.id=coalesce(u.auth_user_id,u.id)
  LEFT JOIN public.user_devices d ON d.id=t.device_id AND d.user_id=p.id
  WHERE p.id=t.user_id;
  IF NOT FOUND THEN v_reason:='ACCOUNT_MISSING_OR_DELETED'; END IF;
  IF p_action='preview' OR v_reason IS DISTINCT FROM 'READY' THEN
    RETURN jsonb_build_object('ticket_id',t.id,'user_id',t.user_id,'device_id',t.device_id,
      'ready',v_reason='READY','reason',v_reason,'status',t.status,
      'platform_permission','unknown','expires_at',t.expires_at,
      'http_status',t.http_status,'error_code',t.error_code);
  END IF;
  -- Commit the one-use permit before the HTTP call. Replays cannot send again.
  v_receipt:=replace(gen_random_uuid()::text||gen_random_uuid()::text,'-','');
  UPDATE okeyix_reengagement_test_private.tickets SET status='dispatching',dispatched_at=v_now,
    receipt_hash=encode(sha256(convert_to(v_receipt,'UTF8')),'hex') WHERE id=t.id;
  RETURN jsonb_build_object('ready',true,'id',t.id,'token',v_token,'receipt',v_receipt);
END $$;
REVOKE ALL ON FUNCTION public.okeyix_reengagement_test_worker(text,uuid,uuid,uuid,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.okeyix_reengagement_test_worker(text,uuid,uuid,uuid,text,jsonb) TO service_role;
COMMENT ON FUNCTION public.okeyix_reengagement_test_worker(text,uuid,uuid,uuid,text,jsonb)
  IS 'Manual test only: service_role + Edge-only RPC secret, single-use ticket and receipt-bound finish. No cron.';
NOTIFY pgrst,'reload schema';
COMMIT;

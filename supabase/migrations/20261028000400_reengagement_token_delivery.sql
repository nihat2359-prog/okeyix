-- Explicit policy change approved by user: no separate verified-permission gate.
-- Tokens are delivery addresses, NOT proof of OS permission. OS settings still apply.
-- Preserves existing invitation opt-out, account filters, limits, cooldown and history.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $patch$
DECLARE f regprocedure; body text; definition text; changed text;
  old_case text:=$old$      WHEN pe.user_id IS NULL THEN 'permission_unknown'
      WHEN NOT pe.reminders_allowed OR pe.platform_permission='denied' THEN 'permission_denied'
      WHEN pe.platform_permission<>'granted' THEN 'permission_unknown'
      WHEN pe.token_hash<>d.token_hash OR pe.expires_at<=p_at OR pe.verified_at>p_at
        THEN 'permission_unverified_or_expired'
$old$;
  old_join text:=$old$  LEFT JOIN okeyix_reengagement_private.permissions pe ON pe.user_id=p.id AND pe.device_id=d.id;$old$;
  old_dispatch text:=$old$  -- The evaluator reports this row's reservation before permission checks. Explicit
  -- permission recheck below prevents that ordering from masking a revoked permission.
  SELECT btrim(d.push_token) INTO v_token FROM public.user_devices d
    JOIN okeyix_reengagement_private.permissions pe ON pe.user_id=d.user_id AND pe.device_id=d.id
    WHERE d.id=h.device_id AND d.user_id=h.user_id
      AND pe.reminders_allowed AND pe.platform_permission='granted'
      AND pe.verified_at<=v_now AND pe.expires_at>v_now
      AND pe.token_hash=h.token_hash
      AND encode(sha256(convert_to(btrim(d.push_token),'UTF8')),'hex')=h.token_hash;$old$;
  new_dispatch text:=$new$  -- Recheck the pinned device ownership and token immediately before dispatch.
  -- No server-side permission record is required under the approved policy.
  SELECT btrim(d.push_token) INTO v_token FROM public.user_devices d
    WHERE d.id=h.device_id AND d.user_id=h.user_id
      AND encode(sha256(convert_to(btrim(d.push_token),'UTF8')),'hex')=h.token_hash;$new$;
BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'POSTGRES_REQUIRED'; END IF;
  -- Same lock used by reservations: no worker sees a partially changed policy.
  PERFORM 1 FROM okeyix_reengagement_private.settings WHERE id FOR UPDATE;
  f:=to_regprocedure('okeyix_reengagement_private.candidates(timestamptz)');
  SELECT replace(prosrc,chr(13)||chr(10),chr(10)) INTO body FROM pg_proc
    WHERE oid=f AND proowner='postgres'::regrole;
  IF body IS NULL OR md5(body)<>'f179e04eda6b25c87e8a9af256046b96' THEN
    RAISE EXCEPTION 'CANDIDATES_SOURCE_CHANGED_REVIEW_REQUIRED'; END IF;
  definition:=replace(pg_get_functiondef(f),chr(13)||chr(10),chr(10));
  IF strpos(definition,old_case)=0 OR strpos(definition,old_join)=0 THEN
    RAISE EXCEPTION 'CANDIDATES_PATCH_TARGET_MISSING'; END IF;
  changed:=replace(replace(definition,old_case,''),old_join,';');
  EXECUTE changed;

  f:=to_regprocedure('public.okeyix_reengagement_worker(text,uuid,jsonb)');
  SELECT replace(prosrc,chr(13)||chr(10),chr(10)) INTO body FROM pg_proc
    WHERE oid=f AND proowner='postgres'::regrole AND prosecdef;
  IF body IS NULL OR md5(body)<>'2fe9c5dac6c3323cb4aee3daacc1997d' THEN
    RAISE EXCEPTION 'WORKER_SOURCE_CHANGED_REVIEW_REQUIRED'; END IF;
  definition:=replace(pg_get_functiondef(f),chr(13)||chr(10),chr(10));
  IF strpos(definition,old_dispatch)=0 THEN RAISE EXCEPTION 'DISPATCH_PATCH_TARGET_MISSING'; END IF;
  changed:=replace(definition,old_dispatch,new_dispatch);
  changed:=replace(changed,'Tokens and allow_game_invites do not establish reminder consent or OS permission',
    'Token is a delivery address, not proof of OS permission; device notification settings still apply');
  EXECUTE changed;
END $patch$;
NOTIFY pgrst,'reload schema';
COMMIT;

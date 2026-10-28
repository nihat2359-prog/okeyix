-- Run only after the fixture and migration in okeyix_reengagement_test.
\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
  IF current_database()<>'okeyix_reengagement_test' THEN RAISE EXCEPTION 'LOCAL_TEST_DATABASE_REQUIRED'; END IF;
  -- Freeze worker time ONLY inside this rolled-back local transaction.
  EXECUTE replace(pg_get_functiondef('public.okeyix_reengagement_worker(text,uuid,jsonb)'::regprocedure),
    'v_now timestamptz:=clock_timestamp()',
    'v_now timestamptz:=''2026-10-28 12:00:00+03''::timestamptz');
END $$;
CREATE FUNCTION pg_temp.check_it(ok boolean,description text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %',description; END IF;
RAISE NOTICE 'PASS: %',description; END $$;
INSERT INTO auth.users(id) VALUES('00000000-0000-0000-0000-000000000001');
INSERT INTO public.users(id) SELECT id FROM auth.users;
INSERT INTO public.profiles(id,last_seen_at) SELECT id,'2026-10-26 12:00+03' FROM auth.users;
INSERT INTO public.user_devices VALUES('00000000-0000-0000-0000-000000000011',
  '00000000-0000-0000-0000-000000000001','fake-device','ios','synthetic-token',
  '2026-10-26 12:00+03','2026-10-01');
SELECT pg_temp.check_it((SELECT NOT enabled AND dry_run FROM okeyix_reengagement_private.settings),'disabled and dry run by default');
SELECT pg_temp.check_it(public.okeyix_reengagement_worker('claim')->>'id' IS NULL,'disabled cannot reserve');
SELECT pg_temp.check_it((SELECT reason='permission_unknown' FROM okeyix_reengagement_private.candidates('2026-10-28 12:00+03')),'token is not permission');
INSERT INTO okeyix_reengagement_private.permissions VALUES(
 '00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000011',
 encode(sha256(convert_to('synthetic-token','UTF8')),'hex'),true,'granted',
 '2026-10-26 12:00+03','2026-11-01 12:00+03','Synthetic test permission');
SELECT pg_temp.check_it((SELECT stage=1 AND reason='eligible' FROM okeyix_reengagement_private.candidates('2026-10-28 12:00+03')),'48-hour boundary');
SELECT pg_temp.check_it((SELECT reason='active' FROM okeyix_reengagement_private.candidates('2026-10-28 11:59:59+03')),'before 48 hours');
SELECT pg_temp.check_it((SELECT stage=2 FROM okeyix_reengagement_private.candidates('2026-10-31 12:00+03')),'5-day stage');
SELECT pg_temp.check_it((SELECT stage=3 FROM okeyix_reengagement_private.candidates('2026-11-07 12:00+03')),'12-day stage');
SELECT pg_temp.check_it((SELECT stage=4 FROM okeyix_reengagement_private.candidates('2026-11-14 12:00+03')),'19-day final stage');
UPDATE public.users SET is_bot=true;
SELECT pg_temp.check_it((SELECT reason='bot' FROM okeyix_reengagement_private.candidates('2026-10-28 12:00+03')),'bots excluded');
UPDATE public.users SET is_bot=false,is_banned=true;
SELECT pg_temp.check_it((SELECT reason='blocked' FROM okeyix_reengagement_private.candidates('2026-10-28 12:00+03')),'blocked excluded');
UPDATE public.users SET is_banned=false,is_suspended=true;
SELECT pg_temp.check_it((SELECT reason='blocked' FROM okeyix_reengagement_private.candidates('2026-10-28 12:00+03')),'suspended excluded');
UPDATE public.users SET is_suspended=false;
UPDATE auth.users SET deleted_at='2026-10-27';
SELECT pg_temp.check_it((SELECT reason='deleted_or_missing_account' FROM okeyix_reengagement_private.candidates('2026-10-28 12:00+03')),'deleted excluded');
UPDATE auth.users SET deleted_at=NULL;
UPDATE public.profiles SET allow_game_invites=false;
SELECT pg_temp.check_it((SELECT reason='existing_preference_disabled' FROM okeyix_reengagement_private.candidates('2026-10-28 12:00+03')),'existing opt-out veto');
UPDATE public.profiles SET allow_game_invites=true;
UPDATE okeyix_reengagement_private.settings SET enabled=true,dry_run=false;
CREATE TEMP TABLE claim AS SELECT (public.okeyix_reengagement_worker('claim')->>'id')::uuid id;
SELECT pg_temp.check_it((SELECT id IS NOT NULL FROM claim),'eligible reserved');
SELECT pg_temp.check_it(public.okeyix_reengagement_worker('claim')->>'id' IS NULL,'duplicate reservation blocked');
UPDATE okeyix_reengagement_private.permissions SET reminders_allowed=false;
SELECT pg_temp.check_it(public.okeyix_reengagement_worker('authorize',(SELECT id FROM claim))->>'token' IS NULL,'consent revocation after reservation cancels');
SELECT pg_temp.check_it((SELECT status='cancelled' FROM okeyix_reengagement_private.deliveries),'cancellation retained');
UPDATE okeyix_reengagement_private.permissions SET reminders_allowed=true;
DELETE FROM okeyix_reengagement_private.deliveries;
UPDATE claim SET id=(public.okeyix_reengagement_worker('claim')->>'id')::uuid;
SELECT pg_temp.check_it(public.okeyix_reengagement_worker('authorize',(SELECT id FROM claim))->>'token'='synthetic-token','authorized once');
SELECT pg_temp.check_it(public.okeyix_reengagement_worker('authorize',(SELECT id FROM claim))->>'token' IS NULL,'authorize cannot replay');
SELECT public.okeyix_reengagement_worker('finish',(SELECT id FROM claim),'{"status":"unknown","code":"NETWORK_OUTCOME_UNKNOWN"}');
SELECT pg_temp.check_it(public.okeyix_reengagement_worker('claim')->>'id' IS NULL,'unknown outcomes never replay');
-- New inactivity cycle, but previous automatic attempt is still within 72 hours.
UPDATE public.profiles SET last_seen_at='2026-10-26 11:00+03';
SELECT pg_temp.check_it((SELECT reason='cooldown' FROM okeyix_reengagement_private.candidates('2026-10-28 12:00+03')),'cooldown applies across cycles');
UPDATE okeyix_reengagement_private.deliveries SET reserved_at='2026-10-25 12:00+03';
SELECT pg_temp.check_it((SELECT reason='eligible' FROM okeyix_reengagement_private.candidates('2026-10-28 12:00+03')),'72-hour boundary allows new cycle');
UPDATE public.user_devices SET push_token='replacement-token';
SELECT pg_temp.check_it((SELECT reason='permission_unverified_or_expired' FROM okeyix_reengagement_private.candidates('2026-10-28 12:00+03')),'replacement token needs its own evidence');
SELECT pg_temp.check_it(NOT has_function_privilege('authenticated','public.okeyix_reengagement_worker(text,uuid,jsonb)','EXECUTE'),'end-user RPC blocked');
SELECT pg_temp.check_it(NOT has_function_privilege('anon','public.okeyix_reengagement_worker(text,uuid,jsonb)','EXECUTE'),'anonymous RPC blocked');
SELECT pg_temp.check_it(has_function_privilege('service_role','public.okeyix_reengagement_worker(text,uuid,jsonb)','EXECUTE'),'worker RPC allowed');
-- Latest-device selection and permission evidence do not silently fall back to
-- an older permitted device when the latest device has unknown permission.
UPDATE public.user_devices SET push_token='synthetic-token';
INSERT INTO public.user_devices VALUES('00000000-0000-0000-0000-000000000012',
  '00000000-0000-0000-0000-000000000001','new-device','android','latest-token',
  '2026-10-27 12:00+03','2026-10-02');
SELECT pg_temp.check_it((SELECT reason='permission_unknown' AND device_id='00000000-0000-0000-0000-000000000012'
 FROM okeyix_reengagement_private.candidates('2026-10-28 12:00+03')),'newest unknown device does not borrow old permission');
INSERT INTO okeyix_reengagement_private.deliveries(user_id,cycle_at,stage,device_id,token_hash,title,body,status,reserved_at)
VALUES('00000000-0000-0000-0000-000000000001','2026-10-01',4,
 '00000000-0000-0000-0000-000000000012',encode(sha256(convert_to('latest-token','UTF8')),'hex'),
 'Test','Test','invalid_token','2026-10-20');
SELECT pg_temp.check_it((SELECT reason='eligible' AND device_id='00000000-0000-0000-0000-000000000011'
 FROM okeyix_reengagement_private.candidates('2026-10-28 12:00+03')),'known-invalid token skipped without changing invite tokens');
DELETE FROM public.user_devices WHERE device_id='new-device';
DELETE FROM okeyix_reengagement_private.deliveries;
-- Freeze to each due time, advance reservations, and prove exactly four stages.
DO $$
DECLARE t timestamptz; step integer; result jsonb; claim_id uuid;
BEGIN
  UPDATE public.profiles SET last_seen_at='2026-10-26 12:00+03';
  UPDATE okeyix_reengagement_private.permissions SET expires_at='2026-11-24 12:00+03';
  FOR step IN 1..4 LOOP
    t:='2026-10-26 12:00+03'::timestamptz+make_interval(hours=>(ARRAY[48,120,288,456])[step]);
    EXECUTE replace(pg_get_functiondef('public.okeyix_reengagement_worker(text,uuid,jsonb)'::regprocedure),
      substring(pg_get_functiondef('public.okeyix_reengagement_worker(text,uuid,jsonb)'::regprocedure)
        FROM 'v_now timestamptz:=[^;]+;'),format('v_now timestamptz:=%L::timestamptz;',t));
    result:=public.okeyix_reengagement_worker('claim');
    claim_id:=(result->>'id')::uuid;
    PERFORM pg_temp.check_it(claim_id IS NOT NULL,format('stage %s reserves on its due date',step));
    PERFORM pg_temp.check_it((SELECT stage=step FROM okeyix_reengagement_private.deliveries WHERE id=claim_id),
      format('stage %s is correct',step));
    PERFORM public.okeyix_reengagement_worker('authorize',claim_id);
    PERFORM public.okeyix_reengagement_worker('finish',claim_id,'{"status":"accepted","code":"FCM_ACCEPTED"}');
  END LOOP;
  PERFORM pg_temp.check_it((SELECT count(*)=4 FROM okeyix_reengagement_private.deliveries),'maximum four reservations per cycle');
  PERFORM pg_temp.check_it((SELECT reason='stage_already_reserved' FROM okeyix_reengagement_private.candidates('2026-12-01 12:00+03')),'no weekly reminder after stage four');
END $$;
-- Both independent server time checks reject 09:59 and 21:00.
DO $$ DECLARE t timestamptz; BEGIN
  FOREACH t IN ARRAY ARRAY['2026-10-28 09:59+03'::timestamptz,'2026-10-28 21:00+03'::timestamptz] LOOP
    EXECUTE replace(pg_get_functiondef('public.okeyix_reengagement_worker(text,uuid,jsonb)'::regprocedure),
      substring(pg_get_functiondef('public.okeyix_reengagement_worker(text,uuid,jsonb)'::regprocedure)
        FROM 'v_now timestamptz:=[^;]+;'),format('v_now timestamptz:=%L::timestamptz;',t));
    PERFORM pg_temp.check_it(public.okeyix_reengagement_worker('claim')->>'skipped'='disabled_dry_run_or_outside_window',
      format('outside window %s',t));
  END LOOP;
END $$;
ROLLBACK;

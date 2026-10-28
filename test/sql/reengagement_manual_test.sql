-- LOCAL ONLY. Requires reengagement_fixture.sql and test-push migration.
\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
 IF current_database()<>'okeyix_reengagement_test' THEN RAISE EXCEPTION 'LOCAL_TEST_DATABASE_REQUIRED'; END IF;
END $$;
CREATE FUNCTION pg_temp.assert_test(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %',label; END IF;
RAISE NOTICE 'PASS: %',label; END $$;
CREATE FUNCTION pg_temp.test_rpc(action text,ticket uuid,result jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE sql AS $$
 SELECT public.okeyix_reengagement_test_worker(action,ticket,
 '00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000033',
 'synthetic-rpc-secret-for-offline-testing-only',result);
$$;
DO $$ BEGIN
 BEGIN
  PERFORM public.okeyix_reengagement_test_worker('preview',gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),
    'synthetic-rpc-secret-for-offline-testing-only');
  RAISE EXCEPTION 'FAIL: unconfigured capability must block RPC';
 EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS: unconfigured hash blocks all RPC'; END;
END $$;
UPDATE okeyix_reengagement_test_private.authorization
 SET rpc_secret_hash=encode(sha256(convert_to('synthetic-rpc-secret-for-offline-testing-only','UTF8')),'hex');
-- Exercise the actual service_role, not only owner calls.
SET LOCAL ROLE service_role;
DO $$ BEGIN
 BEGIN
  PERFORM public.okeyix_reengagement_test_worker('consume',gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),NULL);
  RAISE EXCEPTION 'FAIL: service_role alone must not authorize';
 EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS: service_role without RPC capability rejected'; END;
 BEGIN
  PERFORM public.okeyix_reengagement_test_worker('consume',gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),'wrong-rpc-secret-with-more-than-32-chars');
  RAISE EXCEPTION 'FAIL: wrong RPC capability must not authorize';
 EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS: service_role with wrong RPC capability rejected'; END;
 BEGIN
  PERFORM rpc_secret_hash FROM okeyix_reengagement_test_private.authorization;
  RAISE EXCEPTION 'FAIL: service_role must not read hash configuration';
 EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS: service_role cannot read private capability hash'; END;
END $$;
RESET ROLE;
INSERT INTO auth.users(id) VALUES('00000000-0000-0000-0000-000000000003');
INSERT INTO public.users(id) VALUES('00000000-0000-0000-0000-000000000003');
INSERT INTO public.profiles(id,last_seen_at) VALUES('00000000-0000-0000-0000-000000000003',clock_timestamp());
INSERT INTO public.user_devices(id,user_id,device_id,platform,push_token,last_seen) VALUES(
 '00000000-0000-0000-0000-000000000033','00000000-0000-0000-0000-000000000003',
 'test-device','ios','synthetic-manual-token',clock_timestamp());
CREATE TEMP TABLE test_ticket AS WITH inserted AS (
 INSERT INTO okeyix_reengagement_test_private.tickets(user_id,device_id,token_hash)
 VALUES('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000033',
 encode(sha256(convert_to('synthetic-manual-token','UTF8')),'hex')) RETURNING id
) SELECT id FROM inserted;
SELECT pg_temp.assert_test(pg_temp.test_rpc('consume',(SELECT id FROM test_ticket))->>'token' IS NULL,'draft cannot send');
SELECT pg_temp.assert_test(NOT (pg_temp.test_rpc('finish',(SELECT id FROM test_ticket),
 '{"status":"accepted","http_status":200,"code":"FCM_ACCEPTED"}')->>'recorded')::boolean,'finish on draft does not record');
SELECT pg_temp.assert_test(public.okeyix_reengagement_test_worker('consume',(SELECT id FROM test_ticket),
 '00000000-0000-0000-0000-000000000099','00000000-0000-0000-0000-000000000033',
 'synthetic-rpc-secret-for-offline-testing-only')->>'reason'='TICKET_TARGET_MISMATCH','other account cannot consume');
UPDATE okeyix_reengagement_test_private.tickets SET status='approved',test_consent_confirmed=true,
 approved_at=clock_timestamp(),expires_at=clock_timestamp()+interval '14 minutes';
SELECT pg_temp.assert_test((pg_temp.test_rpc('preview',(SELECT id FROM test_ticket))->>'ready')::boolean,'active player can test without inactivity or automation');
SELECT pg_temp.assert_test(pg_temp.test_rpc('preview',(SELECT id FROM test_ticket))->>'platform_permission'='unknown','OS permission is never claimed as known');
SELECT pg_temp.assert_test((SELECT status='approved' FROM okeyix_reengagement_test_private.tickets),'preview does not consume');
UPDATE public.profiles SET allow_game_invites=false;
SELECT pg_temp.assert_test(pg_temp.test_rpc('consume',(SELECT id FROM test_ticket))->>'reason'='EXISTING_PREFERENCE_DISABLED','existing opt-out preserved');
UPDATE public.profiles SET allow_game_invites=true;
UPDATE public.users SET is_banned=true;
SELECT pg_temp.assert_test(pg_temp.test_rpc('consume',(SELECT id FROM test_ticket))->>'reason'='ACCOUNT_BLOCKED','blocked cannot test');
UPDATE public.users SET is_banned=false;
UPDATE auth.users SET deleted_at=clock_timestamp();
SELECT pg_temp.assert_test(pg_temp.test_rpc('consume',(SELECT id FROM test_ticket))->>'reason'='ACCOUNT_MISSING_OR_DELETED','deleted cannot test');
UPDATE auth.users SET deleted_at=NULL;
UPDATE public.user_devices SET push_token='changed-token';
SELECT pg_temp.assert_test(pg_temp.test_rpc('consume',(SELECT id FROM test_ticket))->>'reason'='TOKEN_CHANGED','token rotation invalidates ticket');
UPDATE public.user_devices SET push_token='synthetic-manual-token',user_id='00000000-0000-0000-0000-000000000099';
SELECT pg_temp.assert_test(pg_temp.test_rpc('consume',(SELECT id FROM test_ticket))->>'reason'='DEVICE_UNAVAILABLE','device ownership change cancels');
UPDATE public.user_devices SET user_id='00000000-0000-0000-0000-000000000003',platform=NULL;
SELECT pg_temp.assert_test(pg_temp.test_rpc('consume',(SELECT id FROM test_ticket))->>'reason'='DEVICE_UNAVAILABLE','unknown platform cannot send');
UPDATE public.user_devices SET platform='ios';
UPDATE okeyix_reengagement_test_private.tickets SET approved_at=clock_timestamp()-interval '20 minutes',expires_at=clock_timestamp()-interval '6 minutes';
SELECT pg_temp.assert_test(pg_temp.test_rpc('consume',(SELECT id FROM test_ticket))->>'reason'='TEST_CONSENT_MISSING_OR_EXPIRED','expired consent cannot send');
UPDATE okeyix_reengagement_test_private.tickets SET approved_at=clock_timestamp(),expires_at=clock_timestamp()+interval '14 minutes';
CREATE TEMP TABLE consumed AS SELECT pg_temp.test_rpc('consume',(SELECT id FROM test_ticket)) AS permit;
SELECT pg_temp.assert_test((SELECT permit->>'token'='synthetic-manual-token' FROM consumed),'approved device receives single permit');
SELECT pg_temp.assert_test(pg_temp.test_rpc('consume',(SELECT id FROM test_ticket))->>'token' IS NULL,'permit cannot be replayed');
DO $$ BEGIN
 BEGIN
  PERFORM pg_temp.test_rpc('finish',(SELECT id FROM test_ticket),'{"status":"accepted","http_status":200,"code":"FCM_ACCEPTED"}');
  RAISE EXCEPTION 'FAIL: finish without receipt';
 EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS: finish without receipt rejected'; END;
 BEGIN
  PERFORM pg_temp.test_rpc('finish',(SELECT id FROM test_ticket),jsonb_build_object(
    'status','accepted','http_status',200,'code','FCM_ACCEPTED','receipt',repeat('b',64)));
  RAISE EXCEPTION 'FAIL: finish with wrong receipt';
 EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS: finish with wrong receipt rejected'; END;
 BEGIN
  PERFORM pg_temp.test_rpc('finish',(SELECT id FROM test_ticket),jsonb_build_object(
    'status','accepted','http_status',500,'code','FCM_ACCEPTED','receipt',(SELECT permit->>'receipt' FROM consumed)));
  RAISE EXCEPTION 'FAIL: accepted with 500';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'INVALID_TEST_RESULT' THEN RAISE; END IF;
  RAISE NOTICE 'PASS: inconsistent accepted / HTTP 500 rejected'; END;
END $$;
SELECT pg_temp.assert_test((SELECT status='dispatching' AND finished_at IS NULL FROM okeyix_reengagement_test_private.tickets),'failed finishes do not alter history');
SELECT pg_temp.assert_test((pg_temp.test_rpc('finish',(SELECT id FROM test_ticket),
 jsonb_build_object('status','accepted','http_status',200,'code','FCM_ACCEPTED','receipt',(SELECT permit->>'receipt' FROM consumed)))->>'recorded')::boolean,'FCM result recorded');
SELECT pg_temp.assert_test(NOT (pg_temp.test_rpc('finish',(SELECT id FROM test_ticket),'{"status":"rejected","code":"UNAVAILABLE"}')->>'recorded')::boolean,'result cannot overwrite finished ticket');
SELECT pg_temp.assert_test(NOT has_function_privilege('anon','public.okeyix_reengagement_test_worker(text,uuid,uuid,uuid,text,jsonb)','EXECUTE'),'anon cannot authorize');
SELECT pg_temp.assert_test(NOT has_function_privilege('authenticated','public.okeyix_reengagement_test_worker(text,uuid,uuid,uuid,text,jsonb)','EXECUTE'),'end-user cannot authorize');
SELECT pg_temp.assert_test(has_function_privilege('service_role','public.okeyix_reengagement_test_worker(text,uuid,uuid,uuid,text,jsonb)','EXECUTE'),'worker can use manual RPC');
ROLLBACK;

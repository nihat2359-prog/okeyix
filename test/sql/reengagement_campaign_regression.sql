\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
  IF current_database()<>'okeyix_reengagement_test' THEN RAISE EXCEPTION 'LOCAL_TEST_DATABASE_REQUIRED'; END IF;
  -- Freeze only local worker time to noon; production always uses server time.
  EXECUTE replace(pg_get_functiondef('public.okeyix_reengagement_worker(text,uuid,jsonb)'::regprocedure),
    'v_now timestamptz:=clock_timestamp()',
    'v_now timestamptz:=date_trunc(''day'',clock_timestamp() AT TIME ZONE ''Europe/Istanbul'') AT TIME ZONE ''Europe/Istanbul''+interval ''12 hours''');
  EXECUTE replace(pg_get_functiondef('public.okeyix_renewal_worker(text,uuid,jsonb)'::regprocedure),
    'v_now timestamptz:=clock_timestamp()',
    'v_now timestamptz:=date_trunc(''day'',clock_timestamp() AT TIME ZONE ''Europe/Istanbul'') AT TIME ZONE ''Europe/Istanbul''+interval ''12 hours''');
END $$;
CREATE FUNCTION pg_temp.check_it(ok boolean,description text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %',description; END IF;
RAISE NOTICE 'PASS: %',description; END $$;
INSERT INTO auth.users(id) SELECT ('00000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid FROM generate_series(1,110) i;
INSERT INTO public.users(id) SELECT id FROM auth.users;
INSERT INTO public.profiles(id,last_seen_at) SELECT id,now()-interval '3 days' FROM auth.users;
INSERT INTO public.user_devices(id,user_id,device_id,platform,push_token,last_seen,created_at)
SELECT id,id,'device-'||id,'android','synthetic-'||id,now()-interval '3 days',now()-interval '5 days' FROM auth.users;
UPDATE okeyix_reengagement_private.settings SET enabled=true,dry_run=false;
-- 105 reservations on one day are permitted; history and cooldown still prevent replay.
DO $$ DECLARE result jsonb; i integer; BEGIN
  FOR i IN 1..105 LOOP
    result:=public.okeyix_reengagement_worker('claim');
    IF result->>'id' IS NULL THEN RAISE EXCEPTION 'FAIL: daily quota at %',i; END IF;
  END LOOP;
END $$;
SELECT pg_temp.check_it((SELECT count(*)=105 FROM okeyix_reengagement_private.deliveries),'more than 100 reservations per day');
SELECT pg_temp.check_it(NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='okeyix_reengagement_private' AND table_name='settings' AND column_name='daily_limit'),'daily quota column removed');
SELECT pg_temp.check_it((SELECT schedule='* 7-17 * * *' FROM cron.job WHERE jobname='okeyix-reengagement-hourly'),'minute scheduler preserves daytime window');
DELETE FROM okeyix_reengagement_private.deliveries;
-- A second device for one user, and a shared token whose newest owner opted out.
INSERT INTO public.user_devices VALUES('10000000-0000-0000-0000-000000000001',
 '00000000-0000-0000-0000-000000000001','second-device','ios','second-device-token',now()-interval '1 day',now());
INSERT INTO public.user_devices VALUES('10000000-0000-0000-0000-000000000002',
 '00000000-0000-0000-0000-000000000002','shared-old','android','shared-token',now()-interval '2 days',now());
INSERT INTO public.user_devices VALUES('10000000-0000-0000-0000-000000000003',
 '00000000-0000-0000-0000-000000000003','shared-new','android','shared-token',now()-interval '1 day',now());
UPDATE public.profiles SET allow_game_invites=false WHERE id='00000000-0000-0000-0000-000000000003';
UPDATE public.users SET is_bot=true WHERE id='00000000-0000-0000-0000-000000000004';
UPDATE public.users SET is_banned=true WHERE id='00000000-0000-0000-0000-000000000005';
UPDATE auth.users SET deleted_at=now() WHERE id='00000000-0000-0000-0000-000000000006';
INSERT INTO okeyix_reengagement_private.deliveries(user_id,cycle_at,stage,device_id,token_hash,title,body,status,reserved_at)
SELECT user_id,now()-interval '30 days',4,id,encode(sha256(convert_to(push_token,'UTF8')),'hex'),'old','old','invalid_token',now()-interval '10 days'
FROM public.user_devices WHERE user_id='00000000-0000-0000-0000-000000000007';
-- Active users receive the one-time announcement too.
UPDATE public.profiles SET last_seen_at=now() WHERE id='00000000-0000-0000-0000-000000000001';
CREATE TEMP TABLE campaign AS SELECT okeyix_reengagement_private.prepare_campaign('offline-renewal','Okeyix yenilendi!','Uygulamayı güncelle, masaya katıl.') id;
SELECT pg_temp.check_it((SELECT count(*)=2 FROM okeyix_reengagement_private.campaign_deliveries WHERE user_id='00000000-0000-0000-0000-000000000001'),'all devices of active user included');
SELECT pg_temp.check_it(NOT EXISTS(SELECT 1 FROM okeyix_reengagement_private.campaign_deliveries WHERE user_id IN (
 '00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000006','00000000-0000-0000-0000-000000000007')),'optout bots blocked deleted and known invalid excluded');
SELECT pg_temp.check_it(NOT EXISTS(SELECT 1 FROM okeyix_reengagement_private.campaign_deliveries WHERE token_hash=encode(sha256(convert_to('shared-token','UTF8')),'hex')),'latest shared-token owner optout cannot be bypassed');
DO $$ BEGIN
  BEGIN
    PERFORM okeyix_reengagement_private.prepare_campaign('offline-renewal','Duplicate','Duplicate');
    RAISE EXCEPTION 'FAIL: duplicate campaign key allowed';
  EXCEPTION WHEN unique_violation THEN NULL; END;
END $$;
UPDATE okeyix_reengagement_private.campaigns SET status='running';
SELECT pg_temp.check_it((public.okeyix_reengagement_worker('preview')->>'enabled')::boolean=false,'regular automation waits for campaign');
SELECT pg_temp.check_it(public.okeyix_reengagement_worker('claim')->>'id' IS NULL,'regular claims blocked during campaign');
-- Recheck optout and replaced token after snapshot, before dispatch.
UPDATE public.profiles SET allow_game_invites=false WHERE id='00000000-0000-0000-0000-000000000008';
UPDATE public.user_devices SET push_token='replacement-after-snapshot' WHERE user_id='00000000-0000-0000-0000-000000000009';
CREATE TEMP TABLE batch AS SELECT public.okeyix_renewal_worker('claim_batch') result;
SELECT pg_temp.check_it((SELECT jsonb_array_length(result->'items')=5 FROM batch),'small group of five claimed');
SELECT pg_temp.check_it((SELECT count(*)=2 FROM okeyix_reengagement_private.campaign_deliveries WHERE status='cancelled'),'optout and token change cancel queued recipients');
SAVEPOINT interrupted_last_group;
UPDATE okeyix_reengagement_private.campaign_deliveries SET dispatched_at='2000-01-01' WHERE status='dispatching';
UPDATE okeyix_reengagement_private.campaign_deliveries SET status='cancelled' WHERE status='pending';
SELECT pg_temp.check_it(public.okeyix_renewal_worker('preview')->>'recoverable'='5','last interrupted group is visible without pending devices');
SELECT public.okeyix_renewal_worker('claim_batch');
SELECT pg_temp.check_it((SELECT count(*)=5 FROM okeyix_reengagement_private.campaign_deliveries WHERE status='unknown'),'interrupted sends become unknown without retry');
SELECT pg_temp.check_it((SELECT status='completed' FROM okeyix_reengagement_private.campaigns),'recovery closes final interrupted group');
ROLLBACK TO interrupted_last_group;
SELECT pg_temp.check_it(public.okeyix_renewal_worker('finish_batch',(SELECT id FROM campaign),
 (SELECT jsonb_build_object('batch_id',gen_random_uuid(),'results',jsonb_agg(jsonb_build_object('id',item->>'id','status','accepted','code','FCM_ACCEPTED','http_status',200)))
  FROM batch,jsonb_array_elements(result->'items') item))->>'recorded'='false','wrong batch receipt cannot finalize delivery');
SELECT pg_temp.check_it(public.okeyix_renewal_worker('finish_batch',(SELECT id FROM campaign),
 (SELECT jsonb_build_object('batch_id',result->>'batch_id','results',jsonb_agg(jsonb_build_object('id',item->>'id','status','accepted','code','FCM_ACCEPTED','http_status',200)))
  FROM batch,jsonb_array_elements(result->'items') item GROUP BY result))->>'recorded'='true','claimed results recorded');
SELECT pg_temp.check_it((SELECT count(*)=5 FROM okeyix_reengagement_private.campaign_deliveries WHERE status='accepted'),'accepted history retained');
-- Consume the rest with synthetic results, no network.
DO $$ DECLARE b jsonb; results jsonb; i integer; BEGIN
  FOR i IN 1..30 LOOP
    b:=public.okeyix_renewal_worker('claim_batch');
    IF jsonb_array_length(b->'items')=0 OR NOT b ? 'items' THEN EXIT; END IF;
    SELECT jsonb_agg(jsonb_build_object('id',item->>'id','status','accepted','code','FCM_ACCEPTED','http_status',200)) INTO results FROM jsonb_array_elements(b->'items') item;
    PERFORM public.okeyix_renewal_worker('finish_batch',(SELECT id FROM campaign),jsonb_build_object('batch_id',b->>'batch_id','results',results));
  END LOOP;
END $$;
SELECT pg_temp.check_it((SELECT status='completed' FROM okeyix_reengagement_private.campaigns),'campaign completes after queue drains');
SELECT pg_temp.check_it(NOT EXISTS(SELECT 1 FROM okeyix_reengagement_private.campaign_deliveries WHERE status IN ('pending','dispatching')),'no pending recipients');
SELECT pg_temp.check_it(public.okeyix_renewal_worker('claim_batch')->>'enabled'='false','completed campaign cannot send again');
SELECT pg_temp.check_it((SELECT reason='campaign_cooldown' FROM okeyix_reengagement_private.candidates(now()) WHERE user_id='00000000-0000-0000-0000-000000000002'),'announcement starts regular 72h cooldown');
SELECT pg_temp.check_it(NOT has_function_privilege('authenticated','public.okeyix_renewal_worker(text,uuid,jsonb)','EXECUTE'),'end users cannot send campaign');
SELECT pg_temp.check_it(NOT has_function_privilege('anon','public.okeyix_renewal_worker(text,uuid,jsonb)','EXECUTE'),'anonymous cannot send campaign');
SELECT pg_temp.check_it(has_function_privilege('service_role','public.okeyix_renewal_worker(text,uuid,jsonb)','EXECUTE'),'server can process campaign');
ROLLBACK;

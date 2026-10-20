-- LOCAL/STAGING ONLY. Never run on production. Uses synthetic data; ROLLBACK.
\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
  IF current_database() NOT LIKE 'okeyix_stat_test_%'
    OR inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet THEN
    RAISE EXCEPTION 'LOCAL_TEST_DATABASE_REQUIRED'; END IF;
END $$;
CREATE FUNCTION pg_temp.check_it(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS NOT TRUE THEN RAISE EXCEPTION 'FAILED: %',label; END IF; END $$;
CREATE FUNCTION pg_temp.hand(u uuid,v uuid,at_time timestamptz,bot boolean DEFAULT false,st text DEFAULT 'completed')
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE sid uuid; rid uuid; winner uuid:=CASE WHEN st='completed' THEN u ELSE NULL END;
BEGIN
  INSERT INTO public.okeyix_stat_sessions(table_id,league_id,entry_coin,started_at)
    VALUES(gen_random_uuid(),'test',100,at_time-interval '1 minute') RETURNING id INTO sid;
  INSERT INTO public.okeyix_stat_rounds(session_id,source_start_key,round_no,status,winner_user_id,started_at,finished_at)
    VALUES(sid,gen_random_uuid()::text,1,st,winner,at_time-interval '1 minute',at_time) RETURNING id INTO rid;
  INSERT INTO public.okeyix_stat_players(round_id,user_id,round_started_at,seat_index,is_bot,outcome)
    VALUES(rid,u,at_time-interval '1 minute',0,false,CASE WHEN st='completed' THEN 'win' ELSE st END),
      (rid,v,at_time-interval '1 minute',1,bot,CASE WHEN st='completed' THEN 'loss' ELSE st END);
  RETURN rid;
END $$;
CREATE FUNCTION pg_temp.reject_second_payment() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN IF NEW.user_id=current_setting('test.referral_fail_user')::uuid THEN RAISE EXCEPTION 'injected'; END IF; RETURN NEW; END $$;

DO $tests$
DECLARE a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); c uuid:=gen_random_uuid();
  ac text; bc text; answer jsonb; inv uuid; initial_balance integer:=10000; k integer;
  d uuid:=gen_random_uuid(); four uuid;
BEGIN
  PERFORM pg_temp.check_it(NOT has_function_privilege('authenticated','okeyix_referral_private.process(integer)','EXECUTE'),'client cannot pay');
  PERFORM pg_temp.check_it(NOT has_schema_privilege('authenticated','okeyix_referral_private','USAGE'),'schema private');
  PERFORM pg_temp.check_it(NOT has_function_privilege('anon','public.okeyix_redeem_invite(text)','EXECUTE'),'anonymous cannot redeem');
  INSERT INTO public.users(id,username) VALUES(a,'synthetic A'),(b,'synthetic B'),(c,'synthetic C');
  INSERT INTO public.profiles(id,username,coins) VALUES(a,'A',10000),(b,'B',10000),(c,'C',10000);
  PERFORM set_config('request.jwt.claim.sub',a::text,true);
  ac:=public.okeyix_invite_dashboard()->>'code';
  PERFORM pg_temp.check_it(ac=public.okeyix_invite_dashboard()->>'code','code stable');
  PERFORM pg_temp.check_it(public.okeyix_redeem_invite(ac)->>'status'='own_code','self rejected');
  PERFORM set_config('request.jwt.claim.sub',b::text,true);
  bc:=public.okeyix_invite_dashboard()->>'code';
  PERFORM pg_temp.check_it(public.okeyix_redeem_invite('invalid')->>'status'='invalid_code','invalid rejected');
  UPDATE okeyix_referral_private.codes SET last_attempt_at=NULL WHERE user_id=b;
  PERFORM pg_temp.check_it(public.okeyix_redeem_invite(lower(ac))->>'status'='accepted','old account can redeem normalized code');
  SELECT id INTO inv FROM okeyix_referral_private.invitations WHERE invitee_id=b;
  PERFORM pg_temp.check_it(public.okeyix_redeem_invite(bc)->>'status'='already_used','only once for life');
  PERFORM pg_temp.hand(b,c,clock_timestamp()-interval '1 day'); -- before acceptance
  PERFORM pg_temp.hand(b,c,clock_timestamp(),true); -- bot snapshot
  PERFORM pg_temp.hand(b,c,clock_timestamp(),false,'aborted');
  PERFORM okeyix_referral_private.process(100);
  PERFORM pg_temp.check_it((SELECT progress=0 FROM okeyix_referral_private.invitations WHERE id=inv),'old bot and aborted excluded');
  FOR k IN 1..9 LOOP PERFORM pg_temp.hand(b,c,clock_timestamp()); END LOOP;
  UPDATE okeyix_referral_private.invitations SET checked_at='-infinity' WHERE id=inv;
  PERFORM okeyix_referral_private.process(100);
  PERFORM pg_temp.check_it((SELECT progress=9 AND rewarded_at IS NULL FROM okeyix_referral_private.invitations WHERE id=inv),'nine hands not paid');
  PERFORM pg_temp.check_it((SELECT coins=initial_balance FROM public.profiles WHERE id=a),'no early payment');
  PERFORM pg_temp.hand(b,c,clock_timestamp());
  UPDATE public.profiles SET coins=NULL WHERE id=a;
  UPDATE okeyix_referral_private.invitations SET checked_at='-infinity' WHERE id=inv;
  PERFORM okeyix_referral_private.process(100);
  PERFORM pg_temp.check_it((SELECT count(*)=0 FROM okeyix_referral_private.payments WHERE invitation_id=inv),'null wallet cannot invent balance');
  UPDATE public.profiles SET coins=2147483647 WHERE id=a;
  UPDATE okeyix_referral_private.invitations SET checked_at='-infinity' WHERE id=inv;
  PERFORM okeyix_referral_private.process(100);
  PERFORM pg_temp.check_it((SELECT count(*)=0 FROM okeyix_referral_private.payments WHERE invitation_id=inv),'overflow cannot partially pay');
  PERFORM pg_temp.check_it((SELECT coins=initial_balance FROM public.profiles WHERE id=b),'other balance unchanged on failure');
  UPDATE public.profiles SET coins=initial_balance WHERE id=a;
  PERFORM set_config('test.referral_fail_user',greatest(a,b)::text,true);
  CREATE TRIGGER referral_test_reject BEFORE INSERT ON public.wallet_transactions FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_second_payment();
  UPDATE okeyix_referral_private.invitations SET checked_at='-infinity' WHERE id=inv;
  PERFORM okeyix_referral_private.process(100);
  PERFORM pg_temp.check_it((SELECT count(*)=0 FROM okeyix_referral_private.payments WHERE invitation_id=inv),'second credit failure rolls back both receipts');
  PERFORM pg_temp.check_it((SELECT bool_and(coins=initial_balance) FROM public.profiles WHERE id IN(a,b)),'second credit failure rolls back both balances');
  PERFORM pg_temp.check_it((SELECT progress=10 AND rewarded_at IS NULL AND error_code IS NOT NULL FROM okeyix_referral_private.invitations WHERE id=inv),'failure remains retryable');
  DROP TRIGGER referral_test_reject ON public.wallet_transactions;
  UPDATE okeyix_referral_private.invitations SET checked_at='-infinity' WHERE id=inv;
  PERFORM okeyix_referral_private.process(100);
  PERFORM pg_temp.check_it((SELECT bool_and(coins=1010000) FROM public.profiles WHERE id IN(a,b)),'one million credited to both');
  PERFORM pg_temp.check_it((SELECT count(*)=2 FROM okeyix_referral_private.payments WHERE invitation_id=inv),'exactly two receipts');
  PERFORM okeyix_referral_private.process(100);
  PERFORM pg_temp.check_it((SELECT count(*)=2 FROM public.wallet_transactions WHERE user_id IN(a,b) AND reason='friend_referral'),'retry cannot double pay');
  PERFORM pg_temp.check_it((SELECT wins IS NULL AND losses IS NULL FROM public.users WHERE id=b),'career counters untouched');
  PERFORM set_config('request.jwt.claim.sub',a::text,true);
  answer:=public.okeyix_invite_dashboard();
  PERFORM pg_temp.check_it(answer->>'earned_coin'='1000000' AND answer->>'successful_invites'='1','dashboard inviter totals');
  PERFORM pg_temp.check_it(jsonb_array_length(public.okeyix_invited_friends())=1,'only own invited friends');
  PERFORM set_config('request.jwt.claim.sub',c::text,true);
  PERFORM pg_temp.check_it(jsonb_array_length(public.okeyix_invited_friends())=0,'other users cannot see invited list');
  PERFORM pg_temp.check_it(public.okeyix_redeem_invite(ac)->>'status'='accepted','unlimited different invitees');
  INSERT INTO public.users(id,username) VALUES(d,'Synthetic D');
  four:=pg_temp.hand(c,a,clock_timestamp());
  INSERT INTO public.okeyix_stat_players(round_id,user_id,round_started_at,seat_index,is_bot,outcome)
    SELECT four,b,started_at,2,false,'loss' FROM public.okeyix_stat_rounds WHERE id=four
    UNION ALL SELECT four,d,started_at,3,false,'loss' FROM public.okeyix_stat_rounds WHERE id=four;
  PERFORM okeyix_referral_private.process(100);
  PERFORM pg_temp.check_it((SELECT progress=1 FROM okeyix_referral_private.invitations WHERE invitee_id=c),'four humans count as one hand');
END $tests$;
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  IF public.okeyix_invite_dashboard()->>'code' IS NULL THEN RAISE EXCEPTION 'authenticated dashboard failed'; END IF;
  BEGIN
    PERFORM okeyix_referral_private.process(100);
    RAISE EXCEPTION 'authenticated must not be able to run reward worker';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT 'friend referral sequential / atomic rollback / replay / privacy tests passed' AS result;
ROLLBACK;

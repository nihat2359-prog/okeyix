-- LOCAL DISPOSABLE DATABASE ONLY. Never execute against Supabase.
DO $$ BEGIN
  IF current_database()<>'okeyix_bot_wallet_test' THEN RAISE EXCEPTION 'LOCAL_TEST_DATABASE_REQUIRED'; END IF;
END $$;
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;
CREATE SCHEMA auth;
CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('request.jwt.claim.role',true),'');
$$;
GRANT USAGE ON SCHEMA auth TO anon,authenticated,service_role;
CREATE TABLE auth.users(id uuid PRIMARY KEY);
CREATE TABLE public.users(id uuid PRIMARY KEY,is_bot boolean NOT NULL DEFAULT false,username text);
CREATE TABLE public.profiles(id uuid PRIMARY KEY,coins integer DEFAULT 10000);
CREATE TABLE public.leagues(id text PRIMARY KEY,name text,min_coin bigint,max_coin bigint);
INSERT INTO public.leagues VALUES
  ('standard','Acemiler',1000,50000),('bronze','Çıraklar',50000,250000),
  ('silver','Kalfalar',250000,1000000),('gold','Ustalar',1000000,3000000),
  ('elite','Şampiyonlar',3000000,10000000);
CREATE TABLE public.wallet_transactions(id bigint GENERATED ALWAYS AS IDENTITY,
  user_id uuid,amount integer NOT NULL,reason text NOT NULL);
CREATE TABLE public.table_players(user_id uuid,entry integer);
CREATE TABLE public.watchdog_runs(n integer);
INSERT INTO public.watchdog_runs VALUES(0);
CREATE SCHEMA cron;
CREATE TABLE cron.job(jobname text,username text,active boolean,database text,command text);
INSERT INTO cron.job VALUES('okey_watchdog_job','postgres',true,current_database(),'SELECT public.run_okey_watchdog();');
-- API contract doubles, NOT substitutes for testing real server bodies in staging.
CREATE FUNCTION public.run_okey_watchdog() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE public.watchdog_runs SET n=n+1;
  RETURN '{"ok":true,"processed":0}'::jsonb;
END $$;
CREATE FUNCTION public.run_standard_bot_table_maintainer(
  p_target_count integer DEFAULT 4,p_apply boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_min_coin integer:=1000; v_max_coin integer:=50000; n integer;
BEGIN
  select count(*) into n from public.users u join public.profiles p on p.id=u.id
  where coalesce(u.is_bot,false) = true
    and coalesce(p.coins,0) >= v_min_coin
    and coalesce(p.coins,0) <= v_max_coin;
  RETURN jsonb_build_object('eligible',n,'apply',p_apply);
END $$;
-- Representative existing fee/reward operations; migration must not modify them.
CREATE FUNCTION public.test_game_charge(p_user uuid,p_entry integer) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF (SELECT coins FROM public.profiles WHERE id=p_user)<p_entry THEN RAISE EXCEPTION 'INSUFFICIENT'; END IF;
  UPDATE public.profiles SET coins=coins-p_entry WHERE id=p_user;
  INSERT INTO public.wallet_transactions(user_id,amount,reason) VALUES(p_user,-p_entry,'table_entry');
END $$;
CREATE FUNCTION public.test_game_reward(p_user uuid,p_amount integer) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  UPDATE public.profiles SET coins=coins+p_amount WHERE id=p_user;
  INSERT INTO public.wallet_transactions(user_id,amount,reason) VALUES(p_user,p_amount,'game_win');
END $$;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.users TO anon,authenticated;
GRANT ALL ON public.profiles TO authenticated;
INSERT INTO public.users VALUES
  ('00000000-0000-0000-0000-000000000001',true,'fixture_bot'),
  ('00000000-0000-0000-0000-000000000002',false,'fixture_human'),
  ('00000000-0000-0000-0000-000000000003',true,'fixture_flagged_auth_account');
INSERT INTO auth.users VALUES('00000000-0000-0000-0000-000000000002'),('00000000-0000-0000-0000-000000000003');
INSERT INTO public.profiles VALUES
  ('00000000-0000-0000-0000-000000000001',0),
  ('00000000-0000-0000-0000-000000000002',12345),
  ('00000000-0000-0000-0000-000000000003',54321);
CREATE TABLE public.test_contract_hashes AS
  SELECT oid,md5(pg_get_functiondef(oid)) AS hash FROM pg_proc
  WHERE oid IN ('public.test_game_charge(uuid,integer)'::regprocedure,
    'public.test_game_reward(uuid,integer)'::regprocedure);

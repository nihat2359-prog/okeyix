-- LOCAL SYNTHETIC CONTRACT DOUBLES ONLY; not the production leave implementation.
DO $$ BEGIN
  IF current_database() NOT LIKE 'okeyix_start_recovery_test_%'
    OR inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet THEN
    RAISE EXCEPTION 'LOCAL_TEST_DATABASE_REQUIRED';
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END $$;
CREATE TABLE public.users(id uuid PRIMARY KEY,is_bot boolean NOT NULL);
CREATE TABLE public.profiles(id uuid PRIMARY KEY,last_seen_at timestamptz,is_online boolean);
CREATE TABLE public.tables(id uuid PRIMARY KEY,status text,max_players integer DEFAULT 2,ready_since timestamptz);
CREATE TABLE public.table_players(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),table_id uuid REFERENCES public.tables ON DELETE CASCADE,user_id uuid,hand jsonb DEFAULT '[]');
CREATE TABLE public.test_leaves(table_id uuid,user_id uuid);
CREATE SCHEMA okeyix_bot_wallet_private;
CREATE FUNCTION okeyix_bot_wallet_private.trusted() RETURNS boolean LANGUAGE sql AS $$
  SELECT current_setting('role') IN ('none','postgres');
$$;
CREATE FUNCTION public.leave_table(p_table_id uuid,p_user_id uuid) RETURNS void
LANGUAGE plpgsql AS $$ BEGIN
  IF current_setting('test.fail_leave',true)='true'
    OR current_setting('test.fail_user',true)=p_user_id::text THEN
    RAISE EXCEPTION 'SYNTHETIC_LEAVE_FAILURE';
  END IF;
  IF current_setting('test.delete_table',true)='true' THEN
    DELETE FROM public.tables WHERE id=p_table_id;
    RETURN;
  END IF;
  DELETE FROM public.table_players WHERE table_id=p_table_id AND user_id=p_user_id;
  INSERT INTO public.test_leaves VALUES(p_table_id,p_user_id);
END $$;
CREATE FUNCTION okeyix_bot_wallet_private.source_watchdog() RETURNS jsonb LANGUAGE sql AS $$ SELECT '{"original":true}'::jsonb; $$;
CREATE FUNCTION public.run_okey_watchdog() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE result jsonb;
BEGIN
  result:=okeyix_bot_wallet_private.source_watchdog();
  RETURN result;
END $$;
CREATE SCHEMA cron;
CREATE TABLE cron.job(active boolean,username text,database text,command text);
INSERT INTO cron.job VALUES(true,'postgres',current_database(),'SELECT public.run_okey_watchdog();');

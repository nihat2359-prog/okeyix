-- LOCAL TEST DATABASE ONLY. Minimal contracts; never run on Supabase.
\set ON_ERROR_STOP on
DO $$ BEGIN
  IF current_database()<>'okeyix_retention_test' THEN RAISE EXCEPTION 'LOCAL_TEST_DATABASE_REQUIRED'; END IF;
END $$;
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE ROLE service_role;
CREATE SCHEMA auth;
CREATE TABLE auth.users(id uuid PRIMARY KEY);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid;
$$;
CREATE TABLE public.users(id uuid PRIMARY KEY,username text);
CREATE TABLE public.profiles(id uuid PRIMARY KEY REFERENCES auth.users(id),coins bigint);
CREATE TABLE public.wallet_transactions(
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid REFERENCES auth.users(id),amount bigint,reason text,type text,store text,note text,
  created_at timestamptz DEFAULT now()
);
CREATE UNIQUE INDEX ux_wallet_daily_bonus_once_per_day
  ON public.wallet_transactions(user_id,note) WHERE reason='daily_bonus' AND note IS NOT NULL;
INSERT INTO auth.users VALUES('00000000-0000-4000-8000-000000000001'),('00000000-0000-4000-8000-000000000002');
INSERT INTO public.profiles SELECT id,1000 FROM auth.users;
INSERT INTO public.users SELECT id,'Oyuncu_'||right(id::text,4) FROM auth.users;

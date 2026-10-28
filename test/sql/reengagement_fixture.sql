-- LOCAL TEST DATABASE ONLY. Contains synthetic data, never production IDs/tokens.
DO $$ BEGIN
  IF current_database()<>'okeyix_reengagement_test' THEN RAISE EXCEPTION 'LOCAL_TEST_DATABASE_REQUIRED'; END IF;
END $$;
CREATE SCHEMA auth;
CREATE TABLE auth.users(id uuid PRIMARY KEY,banned_until timestamptz,deleted_at timestamptz);
CREATE TABLE public.users(id uuid PRIMARY KEY,auth_user_id uuid,is_bot boolean NOT NULL DEFAULT false,
  is_banned boolean NOT NULL DEFAULT false,is_suspended boolean NOT NULL DEFAULT false,
  ban_until timestamp,suspension_until timestamp);
CREATE TABLE public.profiles(id uuid PRIMARY KEY,allow_game_invites boolean NOT NULL DEFAULT true,
  last_seen_at timestamptz);
CREATE TABLE public.user_devices(id uuid PRIMARY KEY,user_id uuid,device_id text,
  platform text,push_token text,last_seen timestamptz,created_at timestamp);

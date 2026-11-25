-- Local contract fixture; not a production schema dump.
DO $$ BEGIN
  IF current_database()<>'okeyix_bot_pool_test' THEN RAISE EXCEPTION 'LOCAL_DATABASE_REQUIRED'; END IF;
END $$;
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;
CREATE SCHEMA auth;
CREATE TABLE auth.users(id uuid PRIMARY KEY);
CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('request.jwt.claim.role',true),'');
$$;
CREATE TABLE public.users(
  id uuid PRIMARY KEY, username text NOT NULL, email text UNIQUE,
  avatar_url text, rating integer, is_bot boolean NOT NULL DEFAULT false,
  wins integer NOT NULL DEFAULT 0, losses integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  untouched_default text NOT NULL DEFAULT 'default-kept'
);
CREATE UNIQUE INDEX fixture_unique_name ON public.users(lower(btrim(username)));
CREATE TABLE public.profiles(
  id uuid PRIMARY KEY REFERENCES public.users(id), username text, avatar text,
  rating integer NOT NULL DEFAULT 1200, coins integer NOT NULL DEFAULT 10000,
  is_online boolean NOT NULL DEFAULT false, allow_game_invites boolean DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.leagues(max_coin bigint);
INSERT INTO public.leagues VALUES(10000000);
-- Exercise a signup trigger that creates profiles before the seed inserts them.
CREATE FUNCTION public.fixture_profile() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.profiles(id,username) VALUES(NEW.id,NEW.username);
  RETURN NEW;
END $$;
CREATE TRIGGER fixture_profile AFTER INSERT ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.fixture_profile();


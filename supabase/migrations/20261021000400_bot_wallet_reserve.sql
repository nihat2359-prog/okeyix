-- NOT APPLIED. Staging first. Uses the EXISTING postgres watchdog schedule.
-- No game RPC, fee, reward, statistics writer, or human balance is changed.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $$ BEGIN
  IF current_user<>'postgres' OR NOT EXISTS(SELECT 1 FROM pg_roles
    WHERE rolname=current_user AND rolbypassrls) THEN
    RAISE EXCEPTION 'BOT_RESERVE_REQUIRES_POSTGRES';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('public.run_okey_watchdog()')
      AND proowner='postgres'::regrole AND md5(prosrc)='b60311af82a4e64d13541944d251149f')
    OR NOT EXISTS(SELECT 1 FROM pg_proc
      WHERE oid=to_regprocedure('public.run_standard_bot_table_maintainer(integer,boolean)')
      AND proowner='postgres'::regrole AND md5(prosrc)='b2d85bfb32b8057267a3fedce7421ecb') THEN
    RAISE EXCEPTION 'BOT_RESERVE_SOURCE_CHANGED';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM cron.job WHERE active AND username='postgres'
    AND database=current_database() AND position('run_okey_watchdog' IN command)>0) THEN
    RAISE EXCEPTION 'BOT_RESERVE_ACTIVE_WATCHDOG_REQUIRED';
  END IF;
END $$;

CREATE SCHEMA okeyix_bot_wallet_private AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA okeyix_bot_wallet_private FROM PUBLIC,anon,authenticated,service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA okeyix_bot_wallet_private REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
CREATE TABLE okeyix_bot_wallet_private.policy (
  singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
  enabled boolean NOT NULL DEFAULT true,
  low_multiple integer NOT NULL DEFAULT 5 CHECK(low_multiple>=1),
  target_multiple integer NOT NULL DEFAULT 20 CHECK(target_multiple>low_multiple)
);
INSERT INTO okeyix_bot_wallet_private.policy DEFAULT VALUES;
CREATE TABLE okeyix_bot_wallet_private.registry (
  user_id uuid PRIMARY KEY,
  registered_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE okeyix_bot_wallet_private.topups (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL,
  balance_before integer NOT NULL CHECK(balance_before>=0),
  balance_after integer NOT NULL,
  amount integer NOT NULL CHECK(amount>0),
  maximum_entry bigint NOT NULL CHECK(maximum_entry>0),
  origin text NOT NULL CHECK(origin IN ('migration','watchdog','maintainer')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK(balance_after::bigint=balance_before::bigint+amount)
);
CREATE INDEX topups_user_time ON okeyix_bot_wallet_private.topups(user_id,created_at DESC);
ALTER TABLE okeyix_bot_wallet_private.policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE okeyix_bot_wallet_private.registry ENABLE ROW LEVEL SECURITY;
ALTER TABLE okeyix_bot_wallet_private.topups ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA okeyix_bot_wallet_private FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA okeyix_bot_wallet_private FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION okeyix_bot_wallet_private.trusted() RETURNS boolean
LANGUAGE sql STABLE SET search_path=pg_catalog,pg_temp AS $$
  SELECT (session_user='postgres' AND current_setting('role') IN ('none','postgres')
      AND coalesce(auth.role(),'') IN ('','postgres'))
    OR (current_setting('role')='service_role' AND auth.role()='service_role');
$$;

-- users currently has no RLS and broad client grants. Protect only bot identity;
-- leave normal profile/avatar inserts and updates under their existing rules.
CREATE FUNCTION okeyix_bot_wallet_private.guard_identity() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
BEGIN
  IF TG_OP='DELETE' THEN
    IF NOT okeyix_bot_wallet_private.trusted() AND (OLD.is_bot OR EXISTS(
      SELECT 1 FROM okeyix_bot_wallet_private.registry WHERE user_id=OLD.id)) THEN
      RAISE EXCEPTION 'BOT_IDENTITY_SERVER_ONLY' USING ERRCODE='42501';
    END IF;
    RETURN OLD;
  END IF;
  IF NOT okeyix_bot_wallet_private.trusted() THEN
    IF (TG_OP='INSERT' AND NEW.is_bot) THEN
      RAISE EXCEPTION 'BOT_IDENTITY_SERVER_ONLY' USING ERRCODE='42501';
    END IF;
    IF TG_OP='UPDATE' AND (NEW.is_bot IS DISTINCT FROM OLD.is_bot OR
      (NEW.id IS DISTINCT FROM OLD.id AND (OLD.is_bot OR EXISTS(
        SELECT 1 FROM okeyix_bot_wallet_private.registry WHERE user_id=OLD.id)))) THEN
      RAISE EXCEPTION 'BOT_IDENTITY_SERVER_ONLY' USING ERRCODE='42501';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE FUNCTION okeyix_bot_wallet_private.register_identity() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
BEGIN
  IF NEW.is_bot AND okeyix_bot_wallet_private.trusted()
    AND NOT EXISTS(SELECT 1 FROM auth.users WHERE id=NEW.id) THEN
    INSERT INTO okeyix_bot_wallet_private.registry(user_id) VALUES(NEW.id)
      ON CONFLICT DO NOTHING;
  END IF;
  RETURN NEW;
END $$;
LOCK TABLE public.users IN SHARE ROW EXCLUSIVE MODE;
CREATE TRIGGER okeyix_bot_identity_guard BEFORE INSERT OR UPDATE OR DELETE ON public.users
  FOR EACH ROW EXECUTE FUNCTION okeyix_bot_wallet_private.guard_identity();
CREATE TRIGGER okeyix_bot_identity_register AFTER INSERT OR UPDATE OF is_bot ON public.users
  FOR EACH ROW EXECUTE FUNCTION okeyix_bot_wallet_private.register_identity();
-- One-time administrator adoption of existing bot-only identities. An account
-- in auth.users is ALWAYS excluded, even if its public is_bot flag is true.
INSERT INTO okeyix_bot_wallet_private.registry(user_id)
  SELECT u.id FROM public.users u WHERE u.is_bot
    AND NOT EXISTS(SELECT 1 FROM auth.users a WHERE a.id=u.id);

CREATE FUNCTION okeyix_bot_wallet_private.replenish(p_origin text) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE cfg record; maximum bigint; low_balance numeric; target_balance numeric;
  r record; delta integer; funded integer:=0;
BEGIN
  IF NOT okeyix_bot_wallet_private.trusted() THEN
    RAISE EXCEPTION 'BOT_RESERVE_SERVER_ONLY' USING ERRCODE='42501';
  END IF;
  IF p_origin IS NULL OR p_origin NOT IN ('migration','watchdog','maintainer') THEN
    RAISE EXCEPTION 'BOT_RESERVE_INVALID_ORIGIN';
  END IF;
  SELECT * INTO STRICT cfg FROM okeyix_bot_wallet_private.policy WHERE singleton;
  IF NOT cfg.enabled THEN RETURN 0; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.leagues) OR EXISTS(
    SELECT 1 FROM public.leagues WHERE min_coin IS NULL OR max_coin IS NULL
      OR min_coin<=0 OR max_coin<min_coin) THEN
    RAISE EXCEPTION 'BOT_RESERVE_INVALID_LEAGUE_RANGE';
  END IF;
  SELECT max(max_coin) INTO maximum FROM public.leagues;
  low_balance:=maximum::numeric*cfg.low_multiple;
  target_balance:=maximum::numeric*cfg.target_multiple;
  IF target_balance>2147483647 OR low_balance>2147483647 THEN
    RAISE EXCEPTION 'BOT_RESERVE_INTEGER_CAPACITY_EXCEEDED';
  END IF;
  IF EXISTS(SELECT 1 FROM okeyix_bot_wallet_private.registry b
    JOIN public.users u ON u.id=b.user_id AND u.is_bot
    LEFT JOIN public.profiles p ON p.id=b.user_id
    WHERE NOT EXISTS(SELECT 1 FROM auth.users a WHERE a.id=b.user_id)
      AND (p.id IS NULL OR p.coins<0)) THEN
    RAISE EXCEPTION 'BOT_RESERVE_WALLET_INVALID';
  END IF;
  FOR r IN SELECT p.id,coalesce(p.coins,0) AS coins FROM public.profiles p
    JOIN okeyix_bot_wallet_private.registry b ON b.user_id=p.id
    JOIN public.users u ON u.id=p.id AND u.is_bot
    WHERE coalesce(p.coins,0)<low_balance
      AND NOT EXISTS(SELECT 1 FROM auth.users a WHERE a.id=p.id)
    ORDER BY p.id FOR UPDATE OF p SKIP LOCKED LOOP
    delta:=(target_balance-r.coins)::integer;
    UPDATE public.profiles SET coins=coalesce(coins,0)+delta WHERE id=r.id;
    INSERT INTO okeyix_bot_wallet_private.topups(
      user_id,balance_before,balance_after,amount,maximum_entry,origin)
    VALUES(r.id,r.coins,target_balance::integer,delta,maximum,p_origin);
    funded:=funded+1;
  END LOOP;
  RETURN funded;
END $$;

-- Preserve the supplied source bodies. Patch only the bot eligibility filter:
-- internal reserve money must not disqualify a bot from a cheaper league.
ALTER FUNCTION public.run_standard_bot_table_maintainer(integer,boolean)
  SET SCHEMA okeyix_bot_wallet_private;
ALTER FUNCTION okeyix_bot_wallet_private.run_standard_bot_table_maintainer(integer,boolean)
  RENAME TO source_maintainer;
DO $$ DECLARE definition text; revised text; BEGIN
  definition:=pg_get_functiondef('okeyix_bot_wallet_private.source_maintainer(integer,boolean)'::regprocedure);
  revised:=replace(definition,'and coalesce(p.coins,0) <= v_max_coin','');
  IF revised=definition THEN RAISE EXCEPTION 'BOT_RESERVE_FILTER_NOT_FOUND'; END IF;
  definition:=revised;
  revised:=replace(definition,'where coalesce(u.is_bot,false) = true',
    'where coalesce(u.is_bot,false) = true and exists (select 1 from okeyix_bot_wallet_private.registry bw where bw.user_id=u.id) and not exists (select 1 from auth.users au where au.id=u.id)');
  IF revised=definition THEN RAISE EXCEPTION 'BOT_RESERVE_IDENTITY_FILTER_NOT_FOUND'; END IF;
  EXECUTE revised;
END $$;
ALTER FUNCTION okeyix_bot_wallet_private.source_maintainer(integer,boolean)
  SET search_path=pg_catalog,public,pg_temp;
CREATE FUNCTION public.run_standard_bot_table_maintainer(
  p_target_count integer DEFAULT 4,p_apply boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
BEGIN
  IF NOT okeyix_bot_wallet_private.trusted() THEN
    RAISE EXCEPTION 'BOT_RESERVE_SERVER_ONLY' USING ERRCODE='42501';
  END IF;
  IF p_apply THEN PERFORM okeyix_bot_wallet_private.replenish('maintainer'); END IF;
  RETURN okeyix_bot_wallet_private.source_maintainer(p_target_count,p_apply);
END $$;

ALTER FUNCTION public.run_okey_watchdog() SET SCHEMA okeyix_bot_wallet_private;
ALTER FUNCTION okeyix_bot_wallet_private.run_okey_watchdog() RENAME TO source_watchdog;
ALTER FUNCTION okeyix_bot_wallet_private.source_watchdog() SET search_path=pg_catalog,public,pg_temp;
CREATE FUNCTION public.run_okey_watchdog() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE result jsonb;
BEGIN
  IF NOT okeyix_bot_wallet_private.trusted() THEN
    RAISE EXCEPTION 'BOT_RESERVE_SERVER_ONLY' USING ERRCODE='42501';
  END IF;
  -- Complete existing game/statistics capture first; topups must never be
  -- mistaken for an entry, penalty or game reward in a before/after snapshot.
  result:=okeyix_bot_wallet_private.source_watchdog();
  PERFORM okeyix_bot_wallet_private.replenish('watchdog');
  RETURN result;
END $$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA okeyix_bot_wallet_private FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.run_okey_watchdog(),
  public.run_standard_bot_table_maintainer(integer,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.run_okey_watchdog(),
  public.run_standard_bot_table_maintainer(integer,boolean) TO service_role;
-- postgres remains the owner; the existing cron job keeps its name/schedule.
SELECT okeyix_bot_wallet_private.replenish('migration');
NOTIFY pgrst,'reload schema';
COMMIT;

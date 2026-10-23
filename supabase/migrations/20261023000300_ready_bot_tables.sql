-- NOT APPLIED. Stage first with the matching Flutter release.
-- Installs DISABLED. Provision a dedicated banned Auth owner, then activate policy.
-- Preserves tables.created_by NOT NULL and its auth.users foreign key.
-- Reuses the existing wallet registry, maintainer entrypoint and watchdog cron.
-- No game, reward, rating, payment or tile-dealing RPC is replaced.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $$ BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'READY_TABLES_REQUIRES_POSTGRES'; END IF;
  IF to_regclass('okeyix_bot_wallet_private.registry') IS NULL OR
     to_regprocedure('okeyix_bot_wallet_private.trusted()') IS NULL THEN
    RAISE EXCEPTION 'READY_TABLES_WALLET_MIGRATION_REQUIRED'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('public.cleanup_stale_bot_waiting_tables(integer)') AND proowner='postgres'::regrole AND prosecdef AND md5(replace(prosrc,chr(13)||chr(10),chr(10)))='5558267c552f2afe889408c60406d35b') THEN RAISE EXCEPTION 'READY_TABLES_SOURCE_CHANGED: public.cleanup_stale_bot_waiting_tables(integer)'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('public.cleanup_stale_waiting_tables(interval)') AND proowner='postgres'::regrole AND prosecdef AND md5(replace(prosrc,chr(13)||chr(10),chr(10)))='195f0a818c049892d268fcc3b6b5e39a') THEN RAISE EXCEPTION 'READY_TABLES_SOURCE_CHANGED: public.cleanup_stale_waiting_tables(interval)'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('public.run_okey_watchdog()') AND proowner='postgres'::regrole AND prosecdef AND md5(replace(prosrc,chr(13)||chr(10),chr(10)))='33b3cff537ae03842d035ee91f0571a9') THEN RAISE EXCEPTION 'READY_TABLES_SOURCE_CHANGED: public.run_okey_watchdog()'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure('okeyix_bot_wallet_private.source_maintainer(integer,boolean)') AND proowner='postgres'::regrole AND prosecdef AND md5(replace(prosrc,chr(13)||chr(10),chr(10)))='5150ce3c994e79ed971195add5f6c761') THEN RAISE EXCEPTION 'READY_TABLES_SOURCE_CHANGED: okeyix_bot_wallet_private.source_maintainer(integer,boolean)'; END IF;
  IF NOT EXISTS(SELECT 1 FROM cron.job WHERE active AND username='postgres'
    AND command ~ 'public\.run_okey_watchdog\(\)' AND database=current_database()) THEN
    RAISE EXCEPTION 'READY_TABLES_EXISTING_WATCHDOG_JOB_REQUIRED'; END IF;
END $$;

CREATE SCHEMA okeyix_ready_private AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA okeyix_ready_private FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE okeyix_ready_private.policy (
  singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
  enabled boolean NOT NULL DEFAULT false,
  owner_id uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  CHECK(NOT enabled OR owner_id IS NOT NULL),
  target integer NOT NULL DEFAULT 3 CHECK(target BETWEEN 0 AND 10)
);
INSERT INTO okeyix_ready_private.policy DEFAULT VALUES;
CREATE TABLE okeyix_ready_private.managed (
  table_id uuid PRIMARY KEY REFERENCES public.tables(id) ON DELETE CASCADE,
  bot_id uuid NOT NULL REFERENCES public.users(id),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE okeyix_ready_private.policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE okeyix_ready_private.managed ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA okeyix_ready_private FROM PUBLIC,anon,authenticated,service_role;

-- Only an admin-provisioned, banned, never-used Auth identity can own these
-- tables. Auth accounts are excluded from the playing-bot wallet registry.
CREATE FUNCTION okeyix_ready_private.valid_owner(p_owner uuid) RETURNS boolean
LANGUAGE sql STABLE SET search_path=pg_catalog,pg_temp AS $$
  SELECT EXISTS(SELECT 1 FROM auth.users a WHERE a.id=p_owner
    AND a.raw_app_meta_data->>'okeyix_system'='ready_tables_owner'
    AND a.banned_until>now() AND a.last_sign_in_at IS NULL
    AND NOT EXISTS(SELECT 1 FROM public.table_players p WHERE p.user_id=a.id)
    AND NOT EXISTS(SELECT 1 FROM okeyix_bot_wallet_private.registry b WHERE b.user_id=a.id));
$$;
CREATE FUNCTION okeyix_ready_private.guard_policy() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
BEGIN
  IF NOT okeyix_bot_wallet_private.trusted() THEN
    RAISE EXCEPTION 'READY_TABLES_SERVER_ONLY' USING ERRCODE='42501'; END IF;
  IF NEW.owner_id IS NOT NULL AND (NEW.enabled OR NEW.owner_id IS DISTINCT FROM OLD.owner_id) THEN
    IF NOT okeyix_ready_private.valid_owner(NEW.owner_id) THEN
      RAISE EXCEPTION 'READY_TABLES_DEDICATED_OWNER_REQUIRED'; END IF;
    IF EXISTS(SELECT 1 FROM okeyix_ready_private.managed m
      JOIN public.tables t ON t.id=m.table_id WHERE t.created_by<>NEW.owner_id) THEN
      RAISE EXCEPTION 'READY_TABLES_OWNER_IN_USE'; END IF;
    -- Hide only this verified non-playing system identity from human presence
    -- and leaderboards if normal Auth signup triggers produced public rows.
    UPDATE public.users SET is_bot=true WHERE id=NEW.owner_id;
    UPDATE public.profiles SET is_online=false WHERE id=NEW.owner_id;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER okeyix_ready_policy_guard BEFORE UPDATE ON okeyix_ready_private.policy
  FOR EACH ROW EXECUTE FUNCTION okeyix_ready_private.guard_policy();

CREATE FUNCTION okeyix_ready_private.is_managed(p_table_id uuid) RETURNS boolean
LANGUAGE sql STABLE SET search_path=pg_catalog,pg_temp AS $$
  SELECT EXISTS(SELECT 1 FROM okeyix_ready_private.managed m
    JOIN public.tables t ON t.id=m.table_id CROSS JOIN okeyix_ready_private.policy c
    WHERE m.table_id=p_table_id AND t.created_by=c.owner_id
      AND okeyix_ready_private.valid_owner(c.owner_id));
$$;

-- Read-only server verification for the lobby's stale-owner guard. No list of
-- accounts or unrestricted private tables is exposed, and no writer is added.
CREATE FUNCTION public.okeyix_ready_table_ids(p_table_ids uuid[]) RETURNS SETOF uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
  SELECT t.id FROM public.tables t WHERE t.id=ANY(p_table_ids)
    AND auth.uid() IS NOT NULL AND cardinality(p_table_ids)<=200
    AND okeyix_ready_private.is_managed(t.id)
    AND coalesce(to_jsonb(t)->>'is_private','false')='false'
    AND coalesce(to_jsonb(t)->>'invite_only','false')='false'
    AND coalesce(to_jsonb(t)->>'is_invite_only','false')='false'
    AND coalesce(to_jsonb(t)->>'is_public','true')='true'
    AND coalesce(to_jsonb(t)->>'visibility','public')='public'
    AND coalesce(to_jsonb(t)->>'password','')=''
    AND coalesce(to_jsonb(t)->>'password_hash','')='';
$$;

CREATE FUNCTION okeyix_ready_private.is_public(t jsonb) RETURNS boolean
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,pg_temp AS $$
  SELECT coalesce(t->>'is_private','false')='false'
    AND coalesce(t->>'invite_only','false')='false'
    AND coalesce(t->>'is_invite_only','false')='false'
    AND coalesce(t->>'is_public','true')='true'
    AND coalesce(t->>'visibility','public')='public'
    AND coalesce(t->>'password','')='' AND coalesce(t->>'password_hash','')='';
$$;

-- Count only usable one-seat tables. Humans keep normal online eligibility;
-- registered bot accounts need no fabricated presence or auth account.
CREATE FUNCTION okeyix_ready_private.is_ready(p_table_id uuid) RETURNS boolean
LANGUAGE sql STABLE SET search_path=pg_catalog,pg_temp AS $$
  SELECT EXISTS(SELECT 1 FROM public.tables t JOIN public.leagues l ON l.id=t.league_id
    JOIN public.table_players tp ON tp.table_id=t.id
    JOIN public.users u ON u.id=tp.user_id JOIN public.profiles p ON p.id=u.id
    WHERE t.id=p_table_id AND t.status='waiting' AND t.max_players=2
      AND t.entry_coin BETWEEN l.min_coin AND l.max_coin
      AND t.entry_coin>0 AND p.coins>=t.entry_coin
      AND coalesce(p.rating,1200)>=coalesce((to_jsonb(l)->>'min_rating')::int,0)
      AND tp.seat_index IN (0,1)
      AND okeyix_ready_private.is_public(to_jsonb(t))
      AND (SELECT count(*) FROM public.table_players x WHERE x.table_id=t.id)=1
      AND ((NOT u.is_bot AND (t.created_by=u.id OR okeyix_ready_private.is_managed(t.id)) AND p.is_online AND
          p.last_seen_at>now()-interval '75 seconds') OR
        (u.is_bot AND okeyix_ready_private.is_managed(t.id)
          AND EXISTS(SELECT 1 FROM okeyix_bot_wallet_private.registry b WHERE b.user_id=u.id)
          AND NOT EXISTS(SELECT 1 FROM auth.users a WHERE a.id=u.id))));
$$;

CREATE FUNCTION okeyix_ready_private.keep_ready(p_table_id uuid) RETURNS boolean
LANGUAGE sql STABLE SET search_path=pg_catalog,pg_temp AS $$
  SELECT EXISTS(SELECT 1 FROM okeyix_ready_private.managed m
    JOIN public.tables t ON t.id=m.table_id
    CROSS JOIN okeyix_ready_private.policy c
    WHERE m.table_id=p_table_id AND c.enabled AND c.target>0
      AND t.league_id::text IN ('standard','bronze','silver')
      AND t.created_by=c.owner_id AND okeyix_ready_private.is_ready(t.id)
      AND EXISTS(SELECT 1 FROM public.table_players tp
        WHERE tp.table_id=t.id AND tp.user_id=m.bot_id)
      -- Once returned tables or real players exceed the target, only the
      -- required oldest ready bot tables are protected. Existing cleanup
      -- expires the surplus normally; no new table deletion path is added.
      AND (SELECT count(*) FROM okeyix_ready_private.managed m2
        JOIN public.tables t2 ON t2.id=m2.table_id
        WHERE t2.league_id=t.league_id AND t2.created_by=c.owner_id
          AND okeyix_ready_private.is_ready(t2.id)
          AND (m2.created_at,m2.table_id)<=(m.created_at,m.table_id))
        <= greatest(c.target-(SELECT count(*) FROM public.tables real_table
          WHERE real_table.league_id=t.league_id
            AND okeyix_ready_private.is_ready(real_table.id)
            AND NOT EXISTS(SELECT 1 FROM okeyix_ready_private.managed other
              WHERE other.table_id=real_table.id)),0));
$$;

-- Coordinate with Quick Play's existing bot-claim lock, including invitations
-- that insert table_players directly. Human seating is unchanged.
CREATE FUNCTION okeyix_ready_private.guard_bot_seat() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
BEGIN
  IF EXISTS(SELECT 1 FROM okeyix_bot_wallet_private.registry b JOIN public.users u ON u.id=b.user_id
    WHERE b.user_id=NEW.user_id AND u.is_bot
      AND NOT EXISTS(SELECT 1 FROM auth.users a WHERE a.id=b.user_id)) THEN
    IF NOT pg_try_advisory_xact_lock(hashtextextended('quick-bot:'||NEW.user_id::text,0)) THEN
      RAISE EXCEPTION 'BOT_SEAT_BUSY' USING ERRCODE='55P03'; END IF;
    IF EXISTS(SELECT 1 FROM public.table_players p JOIN public.tables t ON t.id=p.table_id
      WHERE p.user_id=NEW.user_id AND t.status IN ('waiting','start','starting','playing')) THEN
      RAISE EXCEPTION 'BOT_ALREADY_SEATED' USING ERRCODE='23505'; END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER okeyix_ready_bot_seat_guard BEFORE INSERT ON public.table_players
  FOR EACH ROW EXECUTE FUNCTION okeyix_ready_private.guard_bot_seat();

-- Existing source implementation is replaced only after the exact live source
-- contracts below have been checked. Existing public trusted wrapper is reused.
CREATE OR REPLACE FUNCTION okeyix_bot_wallet_private.source_maintainer(
  p_target_count integer DEFAULT 3,p_apply boolean DEFAULT false
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE cfg record; l record; b record; available integer; missing integer;
  made integer; total integer:=0; chosen uuid; report jsonb:='[]'::jsonb;
BEGIN
  IF NOT okeyix_bot_wallet_private.trusted() THEN
    RAISE EXCEPTION 'BOT_RESERVE_SERVER_ONLY' USING ERRCODE='42501'; END IF;
  IF NOT pg_try_advisory_xact_lock(hashtextextended('okeyix-ready-maintainer',0)) THEN
    RETURN jsonb_build_object('ok',true,'busy',true); END IF;
  SELECT * INTO cfg FROM okeyix_ready_private.policy;
  IF NOT cfg.enabled OR cfg.target=0 THEN RETURN jsonb_build_object('ok',true,'enabled',false); END IF;
  IF NOT okeyix_ready_private.valid_owner(cfg.owner_id) THEN
    RAISE EXCEPTION 'READY_TABLES_SYSTEM_OWNER_INVALID'; END IF;
  IF p_target_count IS NULL OR p_target_count<0 OR p_target_count>10 THEN
    RAISE EXCEPTION 'READY_TABLES_INVALID_TARGET'; END IF;
  FOR l IN SELECT * FROM public.leagues WHERE id::text IN ('standard','bronze','silver')
    ORDER BY display_order,id LOOP
    IF l.min_coin IS NULL OR l.min_coin<=0 OR l.max_coin IS NULL
      OR l.max_coin<l.min_coin OR l.min_coin>2147483647 THEN
      RAISE EXCEPTION 'READY_TABLES_INVALID_STAKES'; END IF;
    SELECT count(*) INTO available FROM public.tables t WHERE t.league_id=l.id
      AND okeyix_ready_private.is_ready(t.id);
    missing:=greatest(least(cfg.target,p_target_count)-available,0);
    made:=0;
    IF p_apply AND missing>0 THEN
      FOR b IN SELECT p.id FROM public.profiles p JOIN public.users u ON u.id=p.id
        JOIN okeyix_bot_wallet_private.registry r ON r.user_id=u.id
        WHERE u.is_bot AND NOT EXISTS(SELECT 1 FROM auth.users a WHERE a.id=u.id)
          AND p.coins>=l.min_coin
          AND coalesce(p.rating,1200)>=coalesce((to_jsonb(l)->>'min_rating')::int,0)
          AND NOT EXISTS(SELECT 1 FROM public.table_players tp JOIN public.tables t ON t.id=tp.table_id
            WHERE tp.user_id=u.id AND t.status IN ('waiting','start','starting','playing'))
        ORDER BY p.id FOR UPDATE OF p SKIP LOCKED LOOP
        IF NOT pg_try_advisory_xact_lock(hashtextextended('quick-bot:'||b.id::text,0)) THEN CONTINUE; END IF;
        IF EXISTS(SELECT 1 FROM public.table_players tp JOIN public.tables t ON t.id=tp.table_id
          WHERE tp.user_id=b.id AND t.status IN ('waiting','start','starting','playing')) THEN CONTINUE; END IF;
        INSERT INTO public.tables(league_id,created_by,status,max_players,entry_coin,
          min_rounds,turn_seconds,spectators_enabled,chat_enabled,ready_since)
        VALUES(l.id,cfg.owner_id,'waiting',2,l.min_coin,
          greatest(coalesce((to_jsonb(l)->>'min_rounds')::int,2),1),
          CASE WHEN coalesce((to_jsonb(l)->>'turn_seconds')::int,20)<=15 THEN 15 ELSE 20 END,
          true,true,now()) RETURNING id INTO chosen;
        INSERT INTO public.table_players(table_id,user_id,seat_index,hand,is_double_mode,consecutive_timeouts)
          VALUES(chosen,b.id,0,'[]'::jsonb,false,0);
        INSERT INTO okeyix_ready_private.managed(table_id,bot_id) VALUES(chosen,b.id);
        made:=made+1; total:=total+1;
        EXIT WHEN made>=missing;
      END LOOP;
    END IF;
    report:=report||jsonb_build_array(jsonb_build_object('league_id',l.id,
      'available_before',available,'created',made,'shortage',greatest(missing-made,0)));
  END LOOP;
  RETURN jsonb_build_object('ok',true,'apply',p_apply,'created',total,'leagues',report);
END $$;

-- Preserve original cleanup and watchdog bodies, adding only managed-table
-- exceptions and a maintenance call after existing watchdog + wallet work.
DO $patch$
DECLARE fn regprocedure; body text; definition text; old_text text; new_text text; signature text;
BEGIN
  FOREACH signature IN ARRAY ARRAY['public.cleanup_stale_bot_waiting_tables(integer)',
      'public.cleanup_stale_waiting_tables(interval)'] LOOP
    fn:=signature::regprocedure;
    SELECT prosrc INTO body FROM pg_proc WHERE oid=fn;
    old_text:='where t.status = ''waiting''';
    IF (length(body)-length(replace(body,old_text,'')))/length(old_text)<>1 THEN
      RAISE EXCEPTION 'READY_TABLES_CLEANUP_CONTRACT_CHANGED'; END IF;
    new_text:=old_text||' and not okeyix_ready_private.keep_ready(t.id)';
    definition:=pg_get_functiondef(fn);
    EXECUTE replace(definition,old_text,new_text);
  END LOOP;
  fn:='public.run_okey_watchdog()'::regprocedure;
  SELECT prosrc INTO body FROM pg_proc WHERE oid=fn;
  old_text:='PERFORM okeyix_bot_wallet_private.replenish(''watchdog'');';
  IF (length(body)-length(replace(body,old_text,'')))/length(old_text)<>1 THEN
    RAISE EXCEPTION 'READY_TABLES_WATCHDOG_CONTRACT_CHANGED'; END IF;
  new_text:=old_text||E'\n  result:=result||jsonb_build_object(''ready_tables'',okeyix_bot_wallet_private.source_maintainer((SELECT target FROM okeyix_ready_private.policy),true));';
  EXECUTE replace(pg_get_functiondef(fn),old_text,new_text);
END $patch$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA okeyix_ready_private FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.okeyix_ready_table_ids(uuid[]) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.okeyix_ready_table_ids(uuid[]) TO authenticated;
NOTIFY pgrst,'reload schema';
REVOKE ALL ON FUNCTION okeyix_bot_wallet_private.source_maintainer(integer,boolean)
  FROM PUBLIC,anon,authenticated,service_role;
-- No new scheduler. Existing postgres watchdog job calls the new maintainer.
COMMIT;

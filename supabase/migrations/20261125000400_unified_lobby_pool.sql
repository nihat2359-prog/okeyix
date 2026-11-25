-- One ready seat per lower league, five-second human queue, read-only showcases.
-- Existing game start/deal/fee RPCs, bot balances and active games are preserved.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $$ DECLARE signature text; expected text; BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'POSTGRES_REQUIRED'; END IF;
  IF has_schema_privilege('anon','public','CREATE')
    OR has_schema_privilege('authenticated','public','CREATE') THEN
    RAISE EXCEPTION 'LOBBY_POOL_PUBLIC_SCHEMA_NOT_TRUSTED'; END IF;
  FOR signature,expected IN SELECT * FROM (VALUES
    ('public.okeyix_quick_play_v2(uuid,text)','3277fe54bd5ca899338abb80247c0dd8'),
    ('okeyix_bot_wallet_private.source_maintainer(integer,boolean)','2a7bc8a53a51fe526a4ee239fe626987')
  ) s(signature,expected) LOOP
    IF NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=to_regprocedure(signature)
      AND proowner='postgres'::regrole AND prosecdef
      AND md5(btrim(regexp_replace(prosrc,'\s+',' ','g')))=expected) THEN
      RAISE EXCEPTION 'LOBBY_POOL_SOURCE_CHANGED: %',signature;
    END IF;
  END LOOP;
  IF NOT EXISTS(SELECT 1 FROM okeyix_ready_private.policy p
    WHERE okeyix_ready_private.valid_owner(p.owner_id)) THEN
    RAISE EXCEPTION 'READY_TABLES_VALID_OWNER_REQUIRED'; END IF;
END $$;

-- Only managed, waiting, bot-only, one-seat tables may be removed. Row locks
-- serialize with joins; a concurrent join's table lock causes SKIP LOCKED.
CREATE FUNCTION okeyix_ready_private.prune_surplus(p_league text) RETURNS integer
-- Existing table-delete voice cleanup triggers resolve public.table_messages
-- via search_path. Preserve their normal public resolution during cascades.
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp AS $$
DECLARE cfg record; human_tables integer; budget integer; kept integer:=0;
  removed integer:=0; affected integer; candidate record;
BEGIN
  IF p_league NOT IN ('standard','bronze','silver') THEN RETURN 0; END IF;
  IF NOT pg_try_advisory_xact_lock(hashtextextended('ready-prune:'||p_league,0)) THEN RETURN 0; END IF;
  SELECT * INTO cfg FROM okeyix_ready_private.policy WHERE singleton;
  IF NOT cfg.enabled THEN RETURN 0; END IF;
  SELECT count(*) INTO human_tables FROM public.tables t
    WHERE t.league_id::text=p_league AND okeyix_ready_private.is_ready(t.id)
      AND NOT EXISTS(SELECT 1 FROM okeyix_ready_private.managed m WHERE m.table_id=t.id)
      AND coalesce(to_jsonb(t)->>'is_fake','false')='false'
      AND EXISTS(SELECT 1 FROM public.table_players tp JOIN public.users u ON u.id=tp.user_id
        WHERE tp.table_id=t.id AND NOT u.is_bot);
  budget:=greatest(cfg.target-human_tables,0);
  FOR candidate IN SELECT t.id FROM public.tables t
    JOIN okeyix_ready_private.managed m ON m.table_id=t.id
    WHERE t.league_id::text=p_league AND t.status='waiting' AND t.created_by=cfg.owner_id
      AND (SELECT count(*) FROM public.table_players tp WHERE tp.table_id=t.id)=1
      AND EXISTS(SELECT 1 FROM public.table_players tp JOIN public.users u ON u.id=tp.user_id
        WHERE tp.table_id=t.id AND tp.user_id=m.bot_id AND u.is_bot)
    ORDER BY m.created_at,m.table_id FOR UPDATE OF t SKIP LOCKED
  LOOP
    IF okeyix_ready_private.is_ready(candidate.id) AND kept<budget THEN
      kept:=kept+1; CONTINUE;
    END IF;
    DELETE FROM public.tables t WHERE t.id=candidate.id AND t.status='waiting'
      AND (SELECT count(*) FROM public.table_players tp WHERE tp.table_id=t.id)=1
      AND NOT EXISTS(SELECT 1 FROM public.table_players tp JOIN public.users u ON u.id=tp.user_id
        WHERE tp.table_id=t.id AND NOT u.is_bot);
    GET DIAGNOSTICS affected=ROW_COUNT;
    removed:=removed+affected;
  END LOOP;
  RETURN removed;
END $$;
REVOKE ALL ON FUNCTION okeyix_ready_private.prune_surplus(text) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION okeyix_ready_private.prune_after_human_seat() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE league text;
BEGIN
  IF EXISTS(SELECT 1 FROM public.users WHERE id=NEW.user_id AND NOT is_bot) THEN
    SELECT league_id::text INTO league FROM public.tables WHERE id=NEW.table_id AND status='waiting';
    IF league IS NOT NULL THEN PERFORM okeyix_ready_private.prune_surplus(league); END IF;
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION okeyix_ready_private.prune_after_human_seat() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER okeyix_ready_prune_on_human_seat AFTER INSERT OR UPDATE OF table_id,user_id
  ON public.table_players FOR EACH ROW EXECUTE FUNCTION okeyix_ready_private.prune_after_human_seat();

-- Preserve the installed maintainer and V2 transaction/cancellation logic;
-- patch only the reviewed, exact source fragments.
DO $patch$ DECLARE fn regprocedure; definition text; old_text text; new_text text; BEGIN
  fn:='okeyix_bot_wallet_private.source_maintainer(integer,boolean)'::regprocedure;
  old_text:='    SELECT count(*) INTO available FROM public.tables t WHERE t.league_id=l.id';
  new_text:='    IF p_apply THEN PERFORM okeyix_ready_private.prune_surplus(l.id::text); END IF;'||E'\n'||old_text;
  definition:=pg_get_functiondef(fn);
  IF (length(definition)-length(replace(definition,old_text,'')))/length(old_text)<>1 THEN
    RAISE EXCEPTION 'READY_MAINTAINER_PATCH_CONTRACT_CHANGED'; END IF;
  EXECUTE replace(definition,old_text,new_text);

  fn:='public.okeyix_quick_play_v2(uuid,text)'::regprocedure;
  definition:=pg_get_functiondef(fn);
  old_text:='      AND okeyix_quick_private.is_public(to_jsonb(x))';
  new_text:=old_text||E'\n      AND coalesce(to_jsonb(x)->>''is_fake'',''false'')=''false'''||
    E'\n      AND NOT EXISTS(SELECT 1 FROM okeyix_ready_private.managed m WHERE m.table_id=x.id)';
  IF (length(definition)-length(replace(definition,old_text,'')))/length(old_text)<>1 THEN
    RAISE EXCEPTION 'QUICK_PLAY_HUMAN_TABLE_PATCH_CONTRACT_CHANGED'; END IF;
  EXECUTE replace(definition,old_text,new_text);
END $patch$;
ALTER TABLE okeyix_match_private.requests ALTER COLUMN wait_until
  SET DEFAULT clock_timestamp()+interval '5 seconds';
-- In-flight requests retain their existing deadline; retries remain idempotent.

-- Synthetic tables exist only in this response: no actual seats, games,
-- statistics, matchmaking candidates or fabricated presence are written.
CREATE FUNCTION public.okeyix_lobby_showcase(p_league_id text) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
WITH league AS (
  SELECT id,min_coin FROM public.leagues WHERE id::text=p_league_id AND auth.uid() IS NOT NULL
), bots AS (
  SELECT u.id,u.username,u.avatar_url,p.rating,
    row_number() OVER(ORDER BY md5(p_league_id||u.id::text),u.id) AS n
  FROM public.users u JOIN public.profiles p ON p.id=u.id
    JOIN okeyix_bot_wallet_private.registry r ON r.user_id=u.id
  WHERE u.is_bot AND NOT EXISTS(SELECT 1 FROM auth.users a WHERE a.id=u.id)
  ORDER BY md5(p_league_id||u.id::text),u.id LIMIT 14
), pairs AS (
  SELECT ((b.n-1)/2)::integer AS position,jsonb_agg(jsonb_build_object(
    'user_id',b.id,'username',b.username,'avatar_url',b.avatar_url,'rating',b.rating,
    'is_bot',true,'seat_index',(b.n-1)%2) ORDER BY b.n) AS players
  FROM bots b GROUP BY (b.n-1)/2 HAVING count(*)=2
)
SELECT coalesce(jsonb_agg(jsonb_build_object(
  'id','showcase:'||l.id||':'||p.position,'league_id',l.id,'is_fake',true,
  'status','playing','max_players',2,'entry_coin',l.min_coin,
  'spectators_enabled',false,'chat_enabled',false,'pot_amount',0,'round_count',0,
  '_players',p.players) ORDER BY p.position),'[]'::jsonb)
FROM pairs p CROSS JOIN league l;
$$;
REVOKE ALL ON FUNCTION public.okeyix_lobby_showcase(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.okeyix_lobby_showcase(text) TO authenticated;

UPDATE okeyix_ready_private.policy SET enabled=true,target=1 WHERE singleton;
-- Reconcile the old three-table pool now. Subsequent minute watchdogs refill
-- only missing lower-league seats; human insert triggers prune surplus sooner.
SELECT okeyix_bot_wallet_private.source_maintainer(1,true);
NOTIFY pgrst,'reload schema';
COMMIT;

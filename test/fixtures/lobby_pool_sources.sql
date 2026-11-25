-- Captured read-only from production; local fixture dependencies are in lobby_pool_fixture.sql.
CREATE OR REPLACE FUNCTION okeyix_bot_wallet_private.source_maintainer(p_target_count integer DEFAULT 3, p_apply boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
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
END $function$
;
CREATE OR REPLACE FUNCTION okeyix_ready_private.is_ready(p_table_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION okeyix_ready_private.keep_ready(p_table_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
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
$function$
;
-- NOT APPLIED. Run after 20261022000100. Instant matching across all eligible
-- leagues; only creates a new table when an actual eligible bot is secured.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $$ BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'QUICK_PLAY_REQUIRES_POSTGRES'; END IF;
 IF to_regclass('okeyix_quick_private.requests') IS NULL THEN
   RAISE EXCEPTION 'QUICK_PLAY_BASE_MIGRATION_REQUIRED'; END IF;
END $$;
CREATE OR REPLACE FUNCTION public.okeyix_quick_play(
 p_request_id uuid,p_league_id text DEFAULT NULL,p_action text DEFAULT 'refresh'
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE u uuid:=auth.uid(); q okeyix_quick_private.requests%ROWTYPE;
 t record; l record; candidate record; bot record;
 balance bigint; rating integer; minimum bigint; maximum bigint;
 chosen uuid; chosen_bot uuid; n integer; owns boolean:=false;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE='42501'; END IF;
 IF p_request_id IS NULL OR p_action IS NULL OR p_action NOT IN ('start','refresh','cancel','bot') THEN
   RAISE EXCEPTION 'QUICK_PLAY_INVALID_ACTION'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('quick:'||u::text,0));
 SELECT * INTO q FROM okeyix_quick_private.requests
   WHERE user_id=u AND request_id=p_request_id FOR UPDATE;
 IF NOT FOUND AND p_action='cancel' THEN
   INSERT INTO okeyix_quick_private.requests(user_id,request_id,state)
     VALUES(u,p_request_id,'cancelled');
   RETURN jsonb_build_object('state','cancelled');
 END IF;
 IF q.state='cancelled' THEN RETURN jsonb_build_object('state','cancelled'); END IF;
 IF q.request_id IS NULL THEN
   IF p_action<>'start' THEN RAISE EXCEPTION 'QUICK_PLAY_REQUEST_NOT_FOUND'; END IF;
   SELECT pr.coins,pr.rating INTO balance,rating FROM public.profiles pr WHERE pr.id=u;
   IF balance IS NULL OR balance<=0 THEN RAISE EXCEPTION 'NOT_ENOUGH_COINS'; END IF;
   IF NOT EXISTS(SELECT 1 FROM public.users WHERE id=u AND NOT is_bot) THEN
     RAISE EXCEPTION 'QUICK_PLAY_PLAYER_REQUIRED' USING ERRCODE='42501'; END IF;
   IF EXISTS(SELECT 1 FROM public.table_players p JOIN public.tables x ON x.id=p.table_id
     WHERE p.user_id=u AND x.status IN ('waiting','start','starting','playing')) THEN
     RAISE EXCEPTION 'QUICK_PLAY_ALREADY_SEATED'; END IF;
   UPDATE okeyix_quick_private.requests SET state='cancelled' WHERE user_id=u AND state='waiting';
   -- p_league_id is deliberately ignored: tab selection is not player eligibility.
   FOR candidate IN SELECT x.* FROM public.tables x
     JOIN public.leagues g ON g.id=x.league_id
     WHERE x.status='waiting' AND x.max_players=2 AND x.created_by<>u
       AND g.min_coin>0 AND g.max_coin>=g.min_coin
       AND x.entry_coin BETWEEN g.min_coin AND g.max_coin AND x.entry_coin<=balance
       AND coalesce(rating,0)>=coalesce((to_jsonb(g)->>'min_rating')::integer,0)
       AND okeyix_quick_private.is_public(to_jsonb(x))
       AND (SELECT count(*) FROM public.table_players p WHERE p.table_id=x.id)=1
       AND EXISTS(SELECT 1 FROM public.table_players p JOIN public.users human ON human.id=p.user_id
         JOIN public.profiles pr ON pr.id=p.user_id
         WHERE p.table_id=x.id AND p.user_id=x.created_by AND NOT human.is_bot
           AND pr.coins>=x.entry_coin AND pr.is_online
           AND pr.last_seen_at>clock_timestamp()-interval '75 seconds')
     ORDER BY x.entry_coin,x.id FOR UPDATE OF x SKIP LOCKED
   LOOP
     SELECT count(*) INTO n FROM public.table_players WHERE table_id=candidate.id;
     IF n<>1 THEN CONTINUE; END IF;
     SELECT pr.coins,pr.rating INTO balance,rating FROM public.profiles pr WHERE pr.id=u FOR UPDATE;
     SELECT * INTO l FROM public.leagues WHERE id=candidate.league_id;
     IF balance IS NULL OR balance<candidate.entry_coin OR
       coalesce(rating,0)<coalesce((to_jsonb(l)->>'min_rating')::integer,0) THEN CONTINUE; END IF;
     BEGIN
       INSERT INTO public.table_players(table_id,user_id,seat_index,hand)
         SELECT candidate.id,u,s,'[]'::jsonb FROM generate_series(0,1) s
         WHERE NOT EXISTS(SELECT 1 FROM public.table_players p
           WHERE p.table_id=candidate.id AND p.seat_index=s) LIMIT 1;
       GET DIAGNOSTICS n=ROW_COUNT;
       IF n=1 THEN chosen:=candidate.id; EXIT; END IF;
     EXCEPTION WHEN unique_violation THEN CONTINUE;
     END;
   END LOOP;
   IF chosen IS NULL THEN
     -- Current league comes from the server rating ranges, as in the lobby's
     -- league assignment. It is independent of the currently selected tab.
     SELECT * INTO l FROM public.leagues g
       WHERE coalesce(rating,0)>=coalesce((to_jsonb(g)->>'min_rating')::integer,0)
         AND (coalesce((to_jsonb(g)->>'max_rating')::integer,0)<=0 OR
           coalesce(rating,0)<=(to_jsonb(g)->>'max_rating')::integer)
       ORDER BY coalesce((to_jsonb(g)->>'min_rating')::integer,0) DESC,
         coalesce((to_jsonb(g)->>'display_order')::integer,0) DESC,g.id LIMIT 1;
     IF NOT FOUND THEN RAISE EXCEPTION 'QUICK_PLAY_LEAGUE_NOT_FOUND'; END IF;
     minimum:=l.min_coin; maximum:=l.max_coin;
     IF minimum IS NULL OR minimum<=0 OR maximum IS NULL OR maximum<minimum OR maximum>2147483647 THEN
       RAISE EXCEPTION 'QUICK_PLAY_INVALID_STAKES'; END IF;
     IF balance<minimum THEN RAISE EXCEPTION 'NOT_ENOUGH_COINS'; END IF;
     FOR bot IN SELECT b.id FROM public.users b JOIN public.profiles pr ON pr.id=b.id
       WHERE b.is_bot AND NOT EXISTS(SELECT 1 FROM auth.users a WHERE a.id=b.id)
         AND pr.coins>=minimum
         AND coalesce(pr.rating,0)>=coalesce((to_jsonb(l)->>'min_rating')::integer,0)
         AND NOT EXISTS(SELECT 1 FROM public.table_players p JOIN public.tables x ON x.id=p.table_id
           WHERE p.user_id=b.id AND x.status IN ('waiting','start','starting','playing'))
       ORDER BY b.id
     LOOP
       IF NOT pg_try_advisory_xact_lock(hashtextextended('quick-bot:'||bot.id::text,0)) THEN CONTINUE; END IF;
       PERFORM id FROM public.profiles WHERE id IN(u,bot.id) ORDER BY id FOR UPDATE;
       IF EXISTS(SELECT 1 FROM public.table_players p JOIN public.tables x ON x.id=p.table_id
         WHERE p.user_id=bot.id AND x.status IN ('waiting','start','starting','playing')) THEN CONTINUE; END IF;
       IF (SELECT count(*) FROM public.profiles WHERE id IN(u,bot.id) AND coins>=minimum)<>2 THEN CONTINUE; END IF;
       chosen_bot:=bot.id; EXIT;
     END LOOP;
     IF chosen_bot IS NULL THEN RAISE EXCEPTION 'QUICK_PLAY_NO_BOT_AVAILABLE'; END IF;
     -- Human and bot are committed together; no public human-waiting table is
     -- left behind if bot allocation, trigger, or seat insertion fails.
     INSERT INTO public.tables(league_id,max_players,entry_coin,min_rounds,status,
       created_by,turn_seconds,spectators_enabled,chat_enabled)
       VALUES(l.id,2,minimum,coalesce((to_jsonb(l)->>'min_rounds')::integer,2),
         'waiting',u,20,true,true) RETURNING id INTO chosen;
     INSERT INTO public.table_players(table_id,user_id,seat_index,hand)
       VALUES(chosen,u,0,'[]'::jsonb),(chosen,chosen_bot,1,'[]'::jsonb);
     owns:=true;
   END IF;
   INSERT INTO okeyix_quick_private.requests(user_id,request_id,league_id,table_id,created_table,state)
     SELECT u,p_request_id,x.league_id::text,chosen,owns,'matched' FROM public.tables x WHERE x.id=chosen
     RETURNING * INTO q;
 END IF;
 SELECT * INTO t FROM public.tables WHERE id=q.table_id FOR UPDATE;
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM public.table_players WHERE table_id=q.table_id AND user_id=u) THEN
   UPDATE okeyix_quick_private.requests SET state='cancelled' WHERE user_id=u AND request_id=p_request_id;
   RETURN jsonb_build_object('state','cancelled');
 END IF;
 SELECT count(*) INTO n FROM public.table_players WHERE table_id=t.id;
 IF n>=2 AND t.status IN ('waiting','start','starting','playing') THEN
   UPDATE okeyix_quick_private.requests SET state='matched' WHERE user_id=u AND request_id=p_request_id;
   RETURN jsonb_build_object('state','ready','table_id',t.id,'is_creator',q.created_table,
     'league_id',t.league_id,'entry',t.entry_coin,
     'bot',EXISTS(SELECT 1 FROM public.table_players p JOIN public.users b ON b.id=p.user_id WHERE p.table_id=t.id AND b.is_bot));
 END IF;
 -- Pending requests created by the old 10-second flow may still be cancelled.
 IF p_action='cancel' AND t.status='waiting' AND n=1 THEN
   PERFORM public.leave_table(t.id,u);
   DELETE FROM public.tables x WHERE x.id=t.id AND x.status IN ('waiting','start')
     AND NOT EXISTS(SELECT 1 FROM public.table_players WHERE table_id=x.id);
   UPDATE okeyix_quick_private.requests SET state='cancelled' WHERE user_id=u AND request_id=p_request_id;
   RETURN jsonb_build_object('state','cancelled');
 END IF;
 IF t.status NOT IN ('waiting','start','starting','playing') THEN
   RETURN jsonb_build_object('state','cancelled'); END IF;
 RAISE EXCEPTION 'QUICK_PLAY_LEGACY_REQUEST_CANCEL_REQUIRED';
END $$;
ALTER FUNCTION public.okeyix_quick_play(uuid,text,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.okeyix_quick_play(uuid,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.okeyix_quick_play(uuid,text,text) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;

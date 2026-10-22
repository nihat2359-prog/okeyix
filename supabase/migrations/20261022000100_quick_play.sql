-- NOT APPLIED. Stage first. Uses existing two-seat rows, start_game and leave_table.
-- No entry debit here: current lobby seats directly; start_game owns the fee.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $$ BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'QUICK_PLAY_REQUIRES_POSTGRES'; END IF;
  IF to_regprocedure('public.leave_table(uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION 'QUICK_PLAY_LEAVE_REQUIRED'; END IF;
END $$;
CREATE SCHEMA okeyix_quick_private AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA okeyix_quick_private FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE okeyix_quick_private.requests (
  user_id uuid NOT NULL, request_id uuid NOT NULL, league_id text,
  table_id uuid, created_table boolean NOT NULL DEFAULT false,
  state text NOT NULL CHECK(state IN ('waiting','matched','cancelled')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(user_id,request_id)
);
ALTER TABLE okeyix_quick_private.requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA okeyix_quick_private FROM PUBLIC,anon,authenticated,service_role;

-- Conservative interpretation of optional privacy fields. Existing lobby has
-- no private-table mode; never infer public from an explicit private flag.
CREATE FUNCTION okeyix_quick_private.is_public(t jsonb) RETURNS boolean
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,pg_temp AS $$
 SELECT coalesce(t->>'is_private','false')='false'
   AND coalesce(t->>'invite_only','false')='false'
   AND coalesce(t->>'is_invite_only','false')='false'
   AND coalesce(t->>'is_public','true')='true'
   AND coalesce(t->>'visibility','public')='public'
   AND coalesce(t->>'password','')=''
   AND coalesce(t->>'password_hash','')='';
$$;

CREATE FUNCTION public.okeyix_quick_play(
  p_request_id uuid, p_league_id text DEFAULT NULL, p_action text DEFAULT 'refresh'
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE u uuid:=auth.uid(); q okeyix_quick_private.requests%ROWTYPE;
  t record; l record; candidate record; bot record;
  balance bigint; rating integer; minimum bigint; maximum bigint;
  chosen uuid; n integer; owns boolean:=false; bot_selected boolean:=false;
BEGIN
  IF u IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE='42501'; END IF;
  IF p_request_id IS NULL OR p_action IS NULL OR p_action NOT IN ('start','refresh','cancel','bot') THEN
    RAISE EXCEPTION 'QUICK_PLAY_INVALID_ACTION'; END IF;
  -- Serialize all requests for this player, including cancellation before start.
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
    SELECT * INTO l FROM public.leagues WHERE id::text=p_league_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'QUICK_PLAY_LEAGUE_NOT_FOUND'; END IF;
    minimum:=l.min_coin; maximum:=l.max_coin;
    IF minimum IS NULL OR minimum<=0 OR maximum IS NULL OR maximum<minimum
      OR maximum>2147483647 THEN RAISE EXCEPTION 'QUICK_PLAY_INVALID_STAKES'; END IF;
    SELECT coins,pr.rating INTO balance,rating FROM public.profiles pr WHERE pr.id=u;
    IF balance IS NULL OR balance<minimum THEN RAISE EXCEPTION 'NOT_ENOUGH_COINS'; END IF;
    IF coalesce(rating,0)<coalesce((to_jsonb(l)->>'min_rating')::integer,0) THEN
      RAISE EXCEPTION 'QUICK_PLAY_RATING_REQUIRED'; END IF;
    IF NOT EXISTS(SELECT 1 FROM public.users WHERE id=u AND NOT is_bot) THEN
      RAISE EXCEPTION 'QUICK_PLAY_PLAYER_REQUIRED' USING ERRCODE='42501'; END IF;
    IF EXISTS(SELECT 1 FROM public.table_players p JOIN public.tables x ON x.id=p.table_id
      WHERE p.user_id=u AND x.status IN ('waiting','start','starting','playing')) THEN
      RAISE EXCEPTION 'QUICK_PLAY_ALREADY_SEATED'; END IF;
    UPDATE okeyix_quick_private.requests SET state='cancelled'
      WHERE user_id=u AND state='waiting';
    -- Table lock -> profile locks is the same order as the game start path.
    FOR candidate IN SELECT x.* FROM public.tables x
      WHERE x.league_id::text=p_league_id AND x.status='waiting' AND x.max_players=2
        AND x.created_by<>u AND x.entry_coin BETWEEN minimum AND maximum
        AND x.entry_coin<=balance AND okeyix_quick_private.is_public(to_jsonb(x))
        AND (SELECT count(*) FROM public.table_players p WHERE p.table_id=x.id)=1
        AND EXISTS(SELECT 1 FROM public.table_players p JOIN public.users human ON human.id=p.user_id
          JOIN public.profiles pr ON pr.id=p.user_id
          WHERE p.table_id=x.id AND p.user_id=x.created_by AND NOT human.is_bot
            AND pr.coins>=x.entry_coin AND pr.is_online
            AND pr.last_seen_at>clock_timestamp()-interval '75 seconds')
      ORDER BY x.entry_coin,x.id LIMIT 24 FOR UPDATE SKIP LOCKED
    LOOP
      SELECT count(*) INTO n FROM public.table_players WHERE table_id=candidate.id;
      IF n<>1 OR NOT EXISTS(
        SELECT 1 FROM public.table_players p JOIN public.users human ON human.id=p.user_id
        JOIN public.profiles pr ON pr.id=p.user_id
        WHERE p.table_id=candidate.id AND NOT human.is_bot AND p.user_id=candidate.created_by
          AND pr.coins>=candidate.entry_coin AND pr.is_online
          AND pr.last_seen_at>clock_timestamp()-interval '75 seconds'
      ) THEN CONTINUE; END IF;
      SELECT coins INTO balance FROM public.profiles WHERE id=u FOR UPDATE;
      IF balance<candidate.entry_coin THEN CONTINUE; END IF;
      BEGIN
        INSERT INTO public.table_players(table_id,user_id,seat_index,hand)
          SELECT candidate.id,u,s,'[]'::jsonb FROM generate_series(0,1) s
          WHERE NOT EXISTS(SELECT 1 FROM public.table_players p
            WHERE p.table_id=candidate.id AND p.seat_index=s) LIMIT 1;
        chosen:=candidate.id;
        EXIT;
      EXCEPTION WHEN unique_violation THEN CONTINUE;
      END;
    END LOOP;
    IF chosen IS NULL THEN
      SELECT coins INTO balance FROM public.profiles WHERE id=u FOR UPDATE;
      IF balance IS NULL OR balance<minimum THEN RAISE EXCEPTION 'NOT_ENOUGH_COINS'; END IF;
      INSERT INTO public.tables(league_id,max_players,entry_coin,min_rounds,status,
        created_by,turn_seconds,spectators_enabled,chat_enabled)
      VALUES(l.id,2,minimum,coalesce((to_jsonb(l)->>'min_rounds')::integer,2),
        'waiting',u,20,true,true) RETURNING id INTO chosen;
      INSERT INTO public.table_players(table_id,user_id,seat_index,hand)
        VALUES(chosen,u,0,'[]'::jsonb);
      owns:=true;
    END IF;
    INSERT INTO okeyix_quick_private.requests(user_id,request_id,league_id,table_id,created_table,state)
      VALUES(u,p_request_id,p_league_id,chosen,owns,'waiting') RETURNING * INTO q;
  END IF;

  SELECT * INTO t FROM public.tables WHERE id=q.table_id FOR UPDATE;
  IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM public.table_players WHERE table_id=q.table_id AND user_id=u) THEN
    UPDATE okeyix_quick_private.requests SET state='cancelled' WHERE user_id=u AND request_id=p_request_id;
    RETURN jsonb_build_object('state','cancelled');
  END IF;
  SELECT count(*) INTO n FROM public.table_players WHERE table_id=t.id;
  IF n>=2 OR t.status IN ('start','starting','playing') THEN
    UPDATE okeyix_quick_private.requests SET state='matched' WHERE user_id=u AND request_id=p_request_id;
    RETURN jsonb_build_object('state','ready','table_id',t.id,'is_creator',q.created_table,
      'bot',EXISTS(SELECT 1 FROM public.table_players p JOIN public.users b ON b.id=p.user_id
        WHERE p.table_id=t.id AND b.is_bot));
  END IF;
  IF t.status<>'waiting' THEN RETURN jsonb_build_object('state','cancelled'); END IF;
  IF p_action='cancel' THEN
    PERFORM public.leave_table(t.id,u);
    -- Same lifecycle as leaving an empty waiting table from OkeyGameScreen.
    DELETE FROM public.tables x WHERE x.id=t.id AND x.status IN ('waiting','start')
      AND NOT EXISTS(SELECT 1 FROM public.table_players WHERE table_id=x.id);
    UPDATE okeyix_quick_private.requests SET state='cancelled' WHERE user_id=u AND request_id=p_request_id;
    RETURN jsonb_build_object('state','cancelled');
  END IF;
  IF p_action='bot' THEN
    IF NOT q.created_table OR clock_timestamp()<q.created_at+interval '10 seconds' THEN
      RAISE EXCEPTION 'QUICK_PLAY_WAIT_REQUIRED'; END IF;
    SELECT * INTO l FROM public.leagues WHERE id=t.league_id;
    -- Same eligible-bot seating mechanism as GameAvatarOverlay: insert seat 1,
    -- then existing table trigger/start_game owns all dealing and payments.
    FOR bot IN SELECT b.id FROM public.users b JOIN public.profiles pr ON pr.id=b.id
      WHERE b.is_bot AND NOT EXISTS(SELECT 1 FROM auth.users a WHERE a.id=b.id)
        AND pr.coins>=t.entry_coin
        AND coalesce(pr.rating,0)>=coalesce((to_jsonb(l)->>'min_rating')::integer,0)
        AND NOT EXISTS(SELECT 1 FROM public.table_players p JOIN public.tables x ON x.id=p.table_id
          WHERE p.user_id=b.id AND x.status IN ('waiting','start','starting','playing'))
      ORDER BY b.id LIMIT 20
    LOOP
      -- Serialize bot claims across different quick tables without deadlocks.
      IF NOT pg_try_advisory_xact_lock(hashtextextended('quick-bot:'||bot.id::text,0)) THEN CONTINUE; END IF;
      PERFORM id FROM public.profiles WHERE id IN (u,bot.id) ORDER BY id FOR UPDATE;
      IF EXISTS(SELECT 1 FROM public.table_players p JOIN public.tables x ON x.id=p.table_id
        WHERE p.user_id=bot.id AND x.status IN ('waiting','start','starting','playing')) THEN CONTINUE; END IF;
      IF (SELECT count(*) FROM public.profiles WHERE id IN(u,bot.id) AND coins>=t.entry_coin)<>2 THEN
        CONTINUE; END IF;
      INSERT INTO public.table_players(table_id,user_id,seat_index,hand)
        VALUES(t.id,bot.id,1,'[]'::jsonb);
      bot_selected:=true;
      UPDATE okeyix_quick_private.requests SET state='matched' WHERE user_id=u AND request_id=p_request_id;
      EXIT;
    END LOOP;
  END IF;
  RETURN jsonb_build_object('state',CASE WHEN bot_selected THEN 'ready' ELSE 'waiting' END,
    'table_id',t.id,'is_creator',q.created_table,'bot',bot_selected,
    'entry',t.entry_coin,'created_at',q.created_at,
    'no_bot',p_action='bot' AND NOT bot_selected);
END $$;
ALTER FUNCTION public.okeyix_quick_play(uuid,text,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION okeyix_quick_private.is_public(jsonb) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.okeyix_quick_play(uuid,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.okeyix_quick_play(uuid,text,text) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;

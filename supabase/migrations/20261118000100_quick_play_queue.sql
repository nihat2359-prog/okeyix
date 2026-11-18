-- NOT APPLIED TO PRODUCTION. Additive RPC; the published client's RPC is unchanged.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $$ BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'POSTGRES_REQUIRED'; END IF;
  IF to_regprocedure('public.okeyix_quick_play(uuid,text,text)') IS NULL OR
     to_regprocedure('okeyix_quick_private.is_public(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'QUICK_PLAY_INSTANT_REQUIRED';
  END IF;
  IF (SELECT md5(btrim(regexp_replace(prosrc,'\s+',' ','g'))) FROM pg_proc
    WHERE oid='public.okeyix_quick_play(uuid,text,text)'::regprocedure)
    IS DISTINCT FROM 'e431fe551abfb0c0245ae1ebec7c1bd5' THEN
    RAISE EXCEPTION 'QUICK_PLAY_INSTANT_SOURCE_CHANGED';
  END IF;
END $$;

CREATE SCHEMA okeyix_match_private AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA okeyix_match_private FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE okeyix_match_private.requests (
  user_id uuid NOT NULL,
  request_id uuid NOT NULL,
  state text NOT NULL CHECK(state IN ('waiting','resolving','matched','cancelled','failed')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  wait_until timestamptz NOT NULL DEFAULT clock_timestamp()+interval '10 seconds',
  lease_until timestamptz NOT NULL DEFAULT clock_timestamp()+interval '4 seconds',
  result jsonb,
  PRIMARY KEY(user_id,request_id)
);
CREATE UNIQUE INDEX one_quick_wait_per_user ON okeyix_match_private.requests(user_id)
  WHERE state IN ('waiting','resolving');
CREATE INDEX quick_wait_lease ON okeyix_match_private.requests(lease_until) WHERE state='waiting';
ALTER TABLE okeyix_match_private.requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA okeyix_match_private
  FROM PUBLIC,anon,authenticated,service_role;

-- Lease expiry never needs to remove a table/seat: waiting has neither.
-- Eligible-candidate queries enforce expiry even if no janitor is running.
CREATE FUNCTION okeyix_match_private.expire_waiters() RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE n bigint;
BEGIN
  UPDATE okeyix_match_private.requests SET state='cancelled'
    WHERE state='waiting' AND lease_until<=clock_timestamp();
  GET DIAGNOSTICS n=ROW_COUNT;
  RETURN n;
END $$;
REVOKE ALL ON FUNCTION okeyix_match_private.expire_waiters() FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.okeyix_quick_play_v2(p_request_id uuid,p_action text DEFAULT 'refresh')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE
  u uuid:=auth.uid(); q okeyix_match_private.requests%ROWTYPE; peer record;
  candidate record; l record; balance bigint; rating integer;
  other_balance bigint; other_rating integer; chosen uuid; n integer;
  answer jsonb; error_code text;
BEGIN
  IF u IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE='42501'; END IF;
  IF p_request_id IS NULL OR p_action IS NULL OR p_action NOT IN ('start','refresh','cancel') THEN
    RAISE EXCEPTION 'QUICK_PLAY_INVALID_ACTION'; END IF;

  -- Short transactions serialize queue pairing and cancel/fallback transitions.
  -- Reuse legacy user/bot locks so old and new clients cannot double-seat a user.
  PERFORM pg_advisory_xact_lock(hashtextextended('quick-v2-match',0));
  PERFORM pg_advisory_xact_lock(hashtextextended('quick:'||u::text,0));
  PERFORM okeyix_match_private.expire_waiters();
  SELECT * INTO q FROM okeyix_match_private.requests
    WHERE user_id=u AND request_id=p_request_id FOR UPDATE;

  IF q.state='matched' THEN
    IF EXISTS(SELECT 1 FROM public.table_players p JOIN public.tables t ON t.id=p.table_id
      WHERE p.user_id=u AND p.table_id=(q.result->>'table_id')::uuid
        AND t.status IN ('waiting','start','starting','playing')) THEN
      -- A committed match wins a cancellation race: return the actual table.
      RETURN q.result;
    END IF;
    UPDATE okeyix_match_private.requests SET state='cancelled'
      WHERE user_id=u AND request_id=p_request_id;
    RETURN jsonb_build_object('state','cancelled');
  END IF;
  IF q.state='cancelled' THEN RETURN jsonb_build_object('state','cancelled'); END IF;
  IF p_action='cancel' THEN
    INSERT INTO okeyix_match_private.requests(user_id,request_id,state)
      VALUES(u,p_request_id,'cancelled') ON CONFLICT(user_id,request_id)
      DO UPDATE SET state='cancelled';
    RETURN jsonb_build_object('state','cancelled');
  END IF;
  IF q.state='failed' THEN RETURN q.result; END IF;
  IF q.request_id IS NULL AND p_action<>'start' THEN
    RAISE EXCEPTION 'QUICK_PLAY_REQUEST_NOT_FOUND'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.users WHERE id=u AND NOT is_bot) THEN
    RAISE EXCEPTION 'QUICK_PLAY_PLAYER_REQUIRED' USING ERRCODE='42501'; END IF;
  IF EXISTS(SELECT 1 FROM public.table_players p JOIN public.tables t ON t.id=p.table_id
    WHERE p.user_id=u AND t.status IN ('waiting','start','starting','playing')) THEN
    RAISE EXCEPTION 'QUICK_PLAY_ALREADY_SEATED'; END IF;
  SELECT coins,pr.rating INTO balance,rating FROM public.profiles pr WHERE id=u FOR UPDATE;
  IF balance IS NULL OR balance<=0 THEN RAISE EXCEPTION 'NOT_ENOUGH_COINS'; END IF;
  IF q.request_id IS NULL THEN
    IF EXISTS(SELECT 1 FROM okeyix_match_private.requests WHERE user_id=u AND state='waiting') THEN
      RAISE EXCEPTION 'QUICK_PLAY_ALREADY_WAITING'; END IF;
    INSERT INTO okeyix_match_private.requests(user_id,request_id,state)
      VALUES(u,p_request_id,'waiting') RETURNING * INTO q;
  END IF;

  -- Preserve the instant RPC's cross-league public human-table search exactly.
  FOR candidate IN SELECT x.* FROM public.tables x JOIN public.leagues g ON g.id=x.league_id
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
  IF chosen IS NOT NULL THEN
    answer:=jsonb_build_object('state','ready','table_id',chosen,'is_creator',false,
      'bot',false,'league_id',candidate.league_id,'entry',candidate.entry_coin);
    UPDATE okeyix_match_private.requests SET state='matched',result=answer
      WHERE user_id=u AND request_id=p_request_id;
    RETURN answer;
  END IF;

  -- FIFO among live waiting requests. Choose an affordable common league from
  -- server rules; no thresholds and no selected-lobby-tab input are duplicated.
  FOR peer IN SELECT r.* FROM okeyix_match_private.requests r
    WHERE r.state='waiting' AND r.user_id<>u
      AND r.lease_until>clock_timestamp() AND r.wait_until>clock_timestamp()
    ORDER BY r.created_at,r.user_id FOR UPDATE
  LOOP
    IF NOT pg_try_advisory_xact_lock(hashtextextended('quick:'||peer.user_id::text,0)) THEN CONTINUE; END IF;
    IF EXISTS(SELECT 1 FROM public.table_players p JOIN public.tables t ON t.id=p.table_id
      WHERE p.user_id=peer.user_id AND t.status IN ('waiting','start','starting','playing')) THEN
      UPDATE okeyix_match_private.requests SET state='cancelled'
        WHERE user_id=peer.user_id AND request_id=peer.request_id;
      CONTINUE;
    END IF;
    SELECT pr.coins,pr.rating INTO other_balance,other_rating FROM public.profiles pr
      JOIN public.users human ON human.id=pr.id AND NOT human.is_bot
      WHERE pr.id=peer.user_id FOR UPDATE OF pr;
    SELECT * INTO l FROM public.leagues g
      WHERE g.min_coin>0 AND g.max_coin>=g.min_coin AND g.min_coin<=2147483647
        AND g.min_coin<=least(balance,other_balance)
        AND coalesce((to_jsonb(g)->>'min_rating')::integer,0)<=least(coalesce(rating,0),coalesce(other_rating,0))
      ORDER BY coalesce((to_jsonb(g)->>'min_rating')::integer,0) DESC,
        coalesce((to_jsonb(g)->>'display_order')::integer,0) DESC,g.id LIMIT 1;
    IF NOT FOUND OR other_balance IS NULL OR peer.lease_until<=clock_timestamp()
      OR peer.wait_until<=clock_timestamp() THEN CONTINUE; END IF;
    INSERT INTO public.tables(league_id,max_players,entry_coin,min_rounds,status,
      created_by,turn_seconds,spectators_enabled,chat_enabled)
      VALUES(l.id,2,l.min_coin,coalesce((to_jsonb(l)->>'min_rounds')::integer,2),
        'waiting',peer.user_id,20,true,true) RETURNING id INTO chosen;
    INSERT INTO public.table_players(table_id,user_id,seat_index,hand)
      VALUES(chosen,peer.user_id,0,'[]'::jsonb),(chosen,u,1,'[]'::jsonb);
    answer:=jsonb_build_object('state','ready','table_id',chosen,'is_creator',false,
      'bot',false,'league_id',l.id,'entry',l.min_coin);
    UPDATE okeyix_match_private.requests SET state='matched',result=answer
      WHERE user_id=u AND request_id=p_request_id;
    UPDATE okeyix_match_private.requests SET state='matched',
      result=answer||jsonb_build_object('is_creator',true)
      WHERE user_id=peer.user_id AND request_id=peer.request_id;
    RETURN answer;
  END LOOP;

  IF clock_timestamp()<q.wait_until THEN
    UPDATE okeyix_match_private.requests SET lease_until=clock_timestamp()+interval '4 seconds'
      WHERE user_id=u AND request_id=p_request_id;
    RETURN jsonb_build_object('state','waiting','remaining_ms',
      greatest(0,ceil(extract(epoch FROM(q.wait_until-clock_timestamp()))*1000)::integer));
  END IF;

  -- The last human check above and this close occur under the same queue lock.
  -- Never allow a request to remain matchable while legacy bot allocation runs.
  UPDATE okeyix_match_private.requests SET state='resolving' WHERE user_id=u AND request_id=p_request_id;
  BEGIN
    SELECT * INTO l FROM public.leagues g
      WHERE coalesce(rating,0)>=coalesce((to_jsonb(g)->>'min_rating')::integer,0)
        AND (coalesce((to_jsonb(g)->>'max_rating')::integer,0)<=0 OR
          coalesce(rating,0)<=(to_jsonb(g)->>'max_rating')::integer)
      ORDER BY coalesce((to_jsonb(g)->>'min_rating')::integer,0) DESC,
        coalesce((to_jsonb(g)->>'display_order')::integer,0) DESC,g.id LIMIT 1;
    -- Also enforce the existing upper-league policy if its trigger is missing.
    -- Existing triggers are left intact; no bot-policy bypass is introduced.
    IF l.id::text IN ('gold','elite') THEN RAISE EXCEPTION 'HUMAN_ONLY_LEAGUE'; END IF;
    answer:=public.okeyix_quick_play(p_request_id,NULL,'start');
    UPDATE okeyix_match_private.requests SET state='matched',result=answer
      WHERE user_id=u AND request_id=p_request_id;
    RETURN answer;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_code=MESSAGE_TEXT;
    -- Return only known error codes, never internal SQL/customer details.
    IF error_code NOT IN ('HUMAN_ONLY_LEAGUE','NOT_ENOUGH_COINS','QUICK_PLAY_NO_BOT_AVAILABLE',
      'QUICK_PLAY_ALREADY_SEATED','QUICK_PLAY_LEAGUE_NOT_FOUND','QUICK_PLAY_INVALID_STAKES') THEN
      error_code:='QUICK_PLAY_FAILED'; END IF;
    answer:=jsonb_build_object('state','error','code',error_code);
    UPDATE okeyix_match_private.requests SET state='failed',result=answer
      WHERE user_id=u AND request_id=p_request_id;
    RETURN answer;
  END;
END $$;
ALTER FUNCTION public.okeyix_quick_play_v2(uuid,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.okeyix_quick_play_v2(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.okeyix_quick_play_v2(uuid,text) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;

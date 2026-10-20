-- NOT APPLIED. Existing RPC names/results stay compatible; their reviewed payment
-- bodies are copied byte-for-byte into a non-API schema, then called exactly once.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $backup$
DECLARE x record; f oid; d text;
BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'STAT_DEPLOY_REQUIRES_POSTGRES'; END IF;
  IF pg_catalog.has_schema_privilege('anon','public','CREATE')
    OR pg_catalog.has_schema_privilege('authenticated','public','CREATE')
    OR pg_catalog.to_regclass('public._tmp_shuffled_tiles') IS NOT NULL
  THEN RAISE EXCEPTION 'STAT_PUBLIC_SCHEMA_NOT_TRUSTED'; END IF;
  FOR x IN SELECT * FROM (VALUES
    ('start_game','uuid','f16782ad8627ab2712337e1ae96ce03d'),
    ('game_finish','uuid,uuid,jsonb,jsonb','73603c480b73120e90aac2aba7def39c'),
    ('leave_table','uuid,uuid','d16a86bfa72b328c85667a0e124452a1'),
    ('game_timeout_move','uuid,uuid','03dd065484700f3a0958f7907c234b9a'),
    ('game_discard','uuid,uuid,jsonb,boolean,jsonb,boolean','a45eaed4c21b3b426c9409051312da9d')
  ) v(name,args,digest) LOOP
    f:=pg_catalog.to_regprocedure('public.'||x.name||'('||x.args||')');
    IF f IS NULL THEN RAISE EXCEPTION 'STAT_SOURCE_MISSING: %',x.name; END IF;
    d:=pg_catalog.pg_get_functiondef(f);
    IF md5(d)<>x.digest THEN RAISE EXCEPTION 'STAT_SOURCE_DRIFT: %',x.name; END IF;
    INSERT INTO okeyix_stat_private.original_acl(name,arguments,acl)
    SELECT x.name,x.args,proacl FROM pg_catalog.pg_proc WHERE oid=f;
    EXECUTE replace(d,'CREATE OR REPLACE FUNCTION public.'||x.name||'(',
      'CREATE OR REPLACE FUNCTION okeyix_stat_private.source_'||x.name||'(');
  END LOOP;
END $backup$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA okeyix_stat_private FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION okeyix_stat_private.put_event(
  p_table uuid,p_round bigint,p_seed text,p_kind text,p_league text,p_entry bigint,
  p_at timestamptz,p_winner uuid,p_okey boolean,p_double boolean,p_reason text,p_players jsonb
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog,pg_temp AS $body$
DECLARE n bigint; e okeyix_stat_private.events%ROWTYPE;
BEGIN
  IF jsonb_typeof(p_players) IS DISTINCT FROM 'array'
    THEN RAISE EXCEPTION 'STAT_INVALID_RECEIPT_ARRAY'; END IF;
  IF p_kind IN ('begin','complete') THEN
    IF jsonb_array_length(p_players) NOT IN (2,4)
      OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_players) x WHERE
        jsonb_typeof(x) IS DISTINCT FROM 'object'
        OR NOT (x ?& ARRAY['user_id','seat_index','is_bot'])
        OR jsonb_typeof(x->'is_bot') IS DISTINCT FROM 'boolean'
        OR (p_kind='begin' AND NOT x ? 'coin_entry')
        OR (p_kind='complete' AND NOT (x ?& ARRAY['coin_reward','coin_refund','coin_bonus','coin_penalty','rating_delta'])))
      OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_players) x CROSS JOIN LATERAL jsonb_object_keys(x) k
        WHERE k NOT IN ('user_id','seat_index','is_bot','coin_entry','coin_reward','coin_refund','coin_bonus','coin_penalty','rating_delta'))
      OR (SELECT count(DISTINCT q.user_id)<>jsonb_array_length(p_players)
            OR count(DISTINCT q.seat_index)<>jsonb_array_length(p_players)
          FROM jsonb_to_recordset(p_players) AS q(user_id uuid,seat_index smallint))
    THEN RAISE EXCEPTION 'STAT_INVALID_RECEIPT_PLAYERS'; END IF;
  ELSIF jsonb_array_length(p_players)<>0 THEN RAISE EXCEPTION 'STAT_UNEXPECTED_RECEIPT_PLAYERS'; END IF;
  INSERT INTO okeyix_stat_private.events(table_id,round_no,seed,kind,league_id,entry_coin,
    occurred_at,winner_user_id,is_okey,is_double,reason)
  VALUES(p_table,p_round,p_seed,p_kind,p_league,p_entry,p_at,p_winner,p_okey,p_double,p_reason)
  ON CONFLICT(table_id,round_no,seed,kind) DO NOTHING RETURNING id INTO n;
  IF n IS NULL THEN
    SELECT * INTO STRICT e FROM okeyix_stat_private.events
    WHERE table_id=p_table AND round_no=p_round AND seed=p_seed AND kind=p_kind FOR UPDATE;
    n:=e.id;
    IF ROW(e.league_id,e.entry_coin,e.occurred_at,e.winner_user_id,e.is_okey,e.is_double,e.reason)
      IS DISTINCT FROM ROW(p_league,p_entry,p_at,p_winner,p_okey,p_double,p_reason)
    THEN RAISE EXCEPTION 'STAT_EVENT_REPLAY_CONFLICT'; END IF;
    IF EXISTS (
      (SELECT user_id,seat_index,is_bot,coin_entry,coin_reward,coin_refund,coin_bonus,coin_penalty,rating_delta
       FROM okeyix_stat_private.event_players WHERE event_id=n
       EXCEPT SELECT * FROM jsonb_to_recordset(p_players) AS p(user_id uuid,seat_index smallint,is_bot boolean,
         coin_entry bigint,coin_reward bigint,coin_refund bigint,coin_bonus bigint,coin_penalty bigint,rating_delta integer))
      UNION ALL
      (SELECT * FROM jsonb_to_recordset(p_players) AS p(user_id uuid,seat_index smallint,is_bot boolean,
         coin_entry bigint,coin_reward bigint,coin_refund bigint,coin_bonus bigint,coin_penalty bigint,rating_delta integer)
       EXCEPT SELECT user_id,seat_index,is_bot,coin_entry,coin_reward,coin_refund,coin_bonus,coin_penalty,rating_delta
       FROM okeyix_stat_private.event_players WHERE event_id=n)
    ) THEN RAISE EXCEPTION 'STAT_EVENT_PLAYERS_REPLAY_CONFLICT'; END IF;
    RETURN n;
  END IF;
  INSERT INTO okeyix_stat_private.event_players
    (event_id,user_id,seat_index,is_bot,coin_entry,coin_reward,coin_refund,coin_bonus,coin_penalty,rating_delta)
  SELECT n,p.* FROM jsonb_to_recordset(p_players) AS p(user_id uuid,seat_index smallint,is_bot boolean,
    coin_entry bigint,coin_reward bigint,coin_refund bigint,coin_bonus bigint,coin_penalty bigint,rating_delta integer);
  IF p_kind IN ('begin','complete') AND (
    (SELECT count(*) FROM okeyix_stat_private.event_players WHERE event_id=n) NOT IN (2,4)
    OR (p_kind='complete' AND NOT EXISTS(SELECT 1 FROM okeyix_stat_private.event_players
      WHERE event_id=n AND user_id=p_winner))
  ) THEN RAISE EXCEPTION 'STAT_INVALID_EVENT_PARTICIPANTS'; END IF;
  RETURN n;
END $body$;

CREATE FUNCTION okeyix_stat_private.abort_round(p_table uuid,p_round bigint,p_seed text,p_at timestamptz,p_reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $body$
BEGIN
  IF EXISTS(SELECT 1 FROM okeyix_stat_private.events
      WHERE table_id=p_table AND round_no=p_round AND seed=p_seed AND kind='begin')
    AND NOT EXISTS(SELECT 1 FROM okeyix_stat_private.events
      WHERE table_id=p_table AND round_no=p_round AND seed=p_seed AND kind IN ('complete','abort')) THEN
    PERFORM okeyix_stat_private.put_event(p_table,p_round,p_seed,'abort',NULL,NULL,p_at,
      NULL,false,false,p_reason,'[]'::jsonb);
  END IF;
END $body$;

CREATE FUNCTION okeyix_stat_private.dispatch(
  p_action text,p_table_id uuid,p_user_id uuid DEFAULT NULL,p_slots jsonb DEFAULT NULL,
  p_tile jsonb DEFAULT NULL,p_finish boolean DEFAULT false,p_player_action boolean DEFAULT true
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,pg_temp AS $body$
DECLARE
  t public.tables%ROWTYPE;
  after_table public.tables%ROWTYPE;
  caller uuid:=auth.uid();
  trusted boolean:=COALESCE(auth.role()='service_role',false) OR
    (session_user='postgres' AND auth.uid() IS NULL AND auth.role() IS NULL);
  roster jsonb;
  before_players jsonb;
  receipts jsonb;
  result jsonb;
  begin_id bigint;
  stamp timestamptz;
  legacy_okey boolean:=false;
  legacy_double boolean:=false;
BEGIN
  IF p_action NOT IN ('start','finish','leave','timeout','discard') OR p_action IS NULL
    THEN RAISE EXCEPTION 'STAT_INVALID_GAME_ACTION'; END IF;
  IF p_action='discard' AND (p_finish IS NULL OR p_player_action IS NULL)
    THEN RAISE EXCEPTION 'STAT_INVALID_DISCARD_FLAGS' USING ERRCODE='22004'; END IF;
  SELECT * INTO t FROM public.tables WHERE id=p_table_id FOR UPDATE;
  IF NOT FOUND THEN
    -- Original leave is idempotent for an already removed table; no state changes.
    IF p_action='leave' AND (trusted OR caller=p_user_id) THEN RETURN 'null'::jsonb; END IF;
    RAISE EXCEPTION 'TABLE_NOT_FOUND';
  END IF;
  IF NOT trusted THEN
    -- A retried self-leave must not reset a later hand after this user left.
    IF p_action='leave' AND caller IS NOT NULL AND caller=p_user_id
      AND NOT EXISTS(SELECT 1 FROM public.table_players WHERE table_id=p_table_id AND user_id=caller)
    THEN RETURN 'null'::jsonb; END IF;
    IF caller IS NULL OR NOT EXISTS(SELECT 1 FROM public.table_players tp
      JOIN public.users u ON u.id=tp.user_id
      WHERE tp.table_id=p_table_id AND tp.user_id=caller AND NOT u.is_bot)
    THEN RAISE EXCEPTION 'GAME_CALLER_NOT_SEATED' USING ERRCODE='42501'; END IF;
    IF p_action='leave' AND p_user_id IS DISTINCT FROM caller
      THEN RAISE EXCEPTION 'GAME_CANNOT_REMOVE_OTHER_PLAYER' USING ERRCODE='42501'; END IF;
    IF p_action IN ('finish','discard') AND p_user_id IS DISTINCT FROM caller
      AND NOT EXISTS(SELECT 1 FROM public.table_players tp JOIN public.users u ON u.id=tp.user_id
        WHERE tp.table_id=p_table_id AND tp.user_id=p_user_id AND u.is_bot AND tp.seat_index=t.current_turn)
      AND NOT (p_action='discard' AND NOT p_player_action AND NOT p_finish
        AND now() >= COALESCE(t.turn_started_at,now())
          + make_interval(secs=>COALESCE(t.turn_seconds,15))-interval '1 second')
    THEN RAISE EXCEPTION 'GAME_CANNOT_PLAY_OTHER_HUMAN' USING ERRCODE='42501'; END IF;
  END IF;

  -- Only monetary operations lock/snapshot profiles; ordinary moves add no polling
  -- and no profile observers. Lock order: table -> participants -> ordered profiles.
  IF (p_action='start' AND t.status<>'playing') OR p_action='finish'
    OR (p_action='discard' AND p_finish) THEN
    PERFORM tp.id FROM public.table_players tp WHERE tp.table_id=p_table_id ORDER BY tp.id FOR UPDATE;
    SELECT id INTO begin_id FROM okeyix_stat_private.events
      WHERE table_id=p_table_id AND round_no=t.round_count AND seed=t.shuffle_seed AND kind='begin';
    IF p_action<>'start' AND begin_id IS NOT NULL THEN
      SELECT jsonb_agg(jsonb_build_object('user_id',user_id,'seat_index',seat_index,'is_bot',is_bot) ORDER BY seat_index)
      INTO roster FROM okeyix_stat_private.event_players WHERE event_id=begin_id;
    ELSE
      SELECT jsonb_agg(jsonb_build_object('user_id',tp.user_id,'seat_index',tp.seat_index,'is_bot',u.is_bot) ORDER BY tp.seat_index)
      INTO roster FROM public.table_players tp LEFT JOIN public.users u ON u.id=tp.user_id WHERE tp.table_id=p_table_id;
    END IF;
    PERFORM p.id FROM public.profiles p
      WHERE p.id IN (SELECT (x->>'user_id')::uuid FROM jsonb_array_elements(roster) x)
      ORDER BY p.id FOR UPDATE;
    SELECT jsonb_agg(x || jsonb_build_object('coins',p.coins,'rating',p.rating)) INTO before_players
      FROM jsonb_array_elements(roster) x LEFT JOIN public.profiles p ON p.id=(x->>'user_id')::uuid;
    IF p_action='discard' AND p_finish THEN
      SELECT COALESCE(tp.is_double_mode,false), EXISTS(
        SELECT 1 FROM jsonb_array_elements(COALESCE(tp.hand,'[]'::jsonb)) h
        WHERE h->>'id'=p_tile->>'id' AND COALESCE((h->>'is_joker')::boolean,false)
          AND NOT COALESCE((h->>'is_fake_joker')::boolean,false))
      INTO legacy_double,legacy_okey FROM public.table_players tp
      WHERE tp.table_id=p_table_id AND tp.user_id=p_user_id;
    END IF;
  END IF;

  CASE p_action
    WHEN 'start' THEN result:=okeyix_stat_private.source_start_game(p_table_id);
    WHEN 'finish' THEN result:=okeyix_stat_private.source_game_finish(p_table_id,p_user_id,p_slots,p_tile);
    WHEN 'leave' THEN PERFORM okeyix_stat_private.source_leave_table(p_table_id,p_user_id); result:='null'::jsonb;
    WHEN 'timeout' THEN result:=okeyix_stat_private.source_game_timeout_move(p_table_id,p_user_id);
    WHEN 'discard' THEN result:=okeyix_stat_private.source_game_discard(p_table_id,p_user_id,p_tile,p_finish,p_slots,p_player_action);
  END CASE;
  SELECT * INTO after_table FROM public.tables WHERE id=p_table_id;
  stamp:=clock_timestamp();
  IF p_action='start' AND t.status<>'playing' AND COALESCE((result->>'ok')::boolean,false)
    AND NOT COALESCE((result->>'already_playing')::boolean,false) THEN
    IF after_table.status<>'playing' OR after_table.round_count<>t.round_count+1
      OR after_table.shuffle_seed IS NULL OR after_table.shuffle_seed IS NOT DISTINCT FROM t.shuffle_seed
      THEN RAISE EXCEPTION 'STAT_DEAL_IDENTITY_INVALID'; END IF;
    -- Fail on malformed UUID seeds rather than silently accepting a different identity.
    PERFORM after_table.shuffle_seed::uuid;
    -- Also handle a reset followed by a new deal in the SAME transaction, before
    -- the deferred reset trigger runs. Terminal events must precede the next begin.
    PERFORM okeyix_stat_private.abort_round(p_table_id,t.round_count,t.shuffle_seed,
      after_table.turn_started_at,'superseded_by_deal');
    SELECT jsonb_agg(jsonb_build_object(
      'user_id',x->>'user_id','seat_index',(x->>'seat_index')::smallint,'is_bot',(x->>'is_bot')::boolean,
      'coin_entry',CASE WHEN (x->>'coins')::bigint>=p.coins::bigint THEN (x->>'coins')::bigint-p.coins::bigint END))
    INTO receipts FROM jsonb_array_elements(before_players) x
      LEFT JOIN public.profiles p ON p.id=(x->>'user_id')::uuid;
    PERFORM okeyix_stat_private.put_event(p_table_id,after_table.round_count,after_table.shuffle_seed,
      'begin',after_table.league_id,after_table.entry_coin,after_table.turn_started_at,
      NULL,false,false,'dealt',receipts);
  ELSIF (p_action='finish' OR (p_action='discard' AND p_finish))
    AND COALESCE((result->>'ok')::boolean,false) AND begin_id IS NOT NULL THEN
    -- The authoritative solver/engine has already returned success. Preserve its
    -- actual flags and the locked roster even if it removed low-coin players.
    SELECT jsonb_agg(jsonb_build_object(
      'user_id',x->>'user_id','seat_index',(x->>'seat_index')::smallint,'is_bot',(x->>'is_bot')::boolean,
      'coin_reward',CASE WHEN x->>'coins' IS NOT NULL AND p.coins IS NOT NULL
        THEN greatest(p.coins::bigint-(x->>'coins')::bigint,0) END,
      'coin_refund',0,'coin_bonus',0,
      'coin_penalty',CASE WHEN x->>'coins' IS NOT NULL AND p.coins IS NOT NULL
        THEN greatest((x->>'coins')::bigint-p.coins::bigint,0) END,
      'rating_delta',p.rating-(x->>'rating')::integer))
    INTO receipts FROM jsonb_array_elements(before_players) x
      LEFT JOIN public.profiles p ON p.id=(x->>'user_id')::uuid;
    PERFORM okeyix_stat_private.put_event(p_table_id,t.round_count,t.shuffle_seed,'complete',
      NULL,NULL,after_table.last_finish_at,(result->>'winner_user_id')::uuid,
      CASE WHEN p_action='finish' THEN (result->>'is_okey')::boolean ELSE legacy_okey END,
      CASE WHEN p_action='finish' THEN (result->>'is_double')::boolean ELSE legacy_double END,
      CASE WHEN p_action='finish' THEN 'game_finish' ELSE 'legacy_discard_finish' END,receipts);
  ELSIF t.status='playing' AND (after_table.id IS NULL OR after_table.status<>'playing') THEN
    PERFORM okeyix_stat_private.abort_round(p_table_id,t.round_count,t.shuffle_seed,stamp,
      CASE p_action WHEN 'leave' THEN 'player_left' WHEN 'timeout' THEN 'timeout' ELSE 'source_reset' END);
  END IF;
  RETURN result;
END $body$;

-- Compatible public entry points. No client receives private statistics EXECUTE.
CREATE OR REPLACE FUNCTION public.start_game(p_table_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp
AS $$ SELECT okeyix_stat_private.dispatch('start',p_table_id); $$;
CREATE OR REPLACE FUNCTION public.game_finish(p_table_id uuid,p_user_id uuid,p_slots jsonb,p_last_tile jsonb)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp
AS $$ SELECT okeyix_stat_private.dispatch('finish',p_table_id,p_user_id,p_slots,p_last_tile); $$;
CREATE OR REPLACE FUNCTION public.leave_table(p_table_id uuid,p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp
AS $$ BEGIN PERFORM okeyix_stat_private.dispatch('leave',p_table_id,p_user_id); END $$;
CREATE OR REPLACE FUNCTION public.game_timeout_move(p_table_id uuid,p_user_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp
AS $$ SELECT okeyix_stat_private.dispatch('timeout',p_table_id,p_user_id); $$;
CREATE OR REPLACE FUNCTION public.game_discard(p_table_id uuid,p_user_id uuid,p_tile jsonb,
  p_finish boolean DEFAULT false,p_slots jsonb DEFAULT NULL,p_is_player_action boolean DEFAULT true)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public,pg_temp
AS $$ SELECT okeyix_stat_private.dispatch('discard',p_table_id,p_user_id,p_slots,p_tile,p_finish,p_is_player_action); $$;

CREATE FUNCTION okeyix_stat_private.table_ended()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $body$
DECLARE stamp timestamptz:=clock_timestamp();
BEGIN
  -- Deferred until transaction end: successful game_finish can delete players
  -- and reset status BEFORE dispatch has recorded the completed event.
  PERFORM okeyix_stat_private.abort_round(OLD.id,OLD.round_count,OLD.shuffle_seed,stamp,
    CASE WHEN TG_OP='DELETE' THEN 'table_deleted' ELSE 'source_reset' END);
  IF TG_OP='DELETE' AND (EXISTS(SELECT 1 FROM okeyix_stat_private.events WHERE table_id=OLD.id AND kind='begin')
    OR EXISTS(SELECT 1 FROM public.okeyix_stat_sessions WHERE table_id=OLD.id)) THEN
    PERFORM okeyix_stat_private.put_event(OLD.id,0,'','close',NULL,NULL,stamp,NULL,false,false,'table_deleted','[]'::jsonb);
  END IF;
  RETURN NULL;
END $body$;
CREATE CONSTRAINT TRIGGER okeyix_stat_table_reset
AFTER UPDATE ON public.tables DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
WHEN (OLD.status='playing' AND NEW.status<>'playing')
EXECUTE FUNCTION okeyix_stat_private.table_ended();
CREATE CONSTRAINT TRIGGER okeyix_stat_table_delete
AFTER DELETE ON public.tables DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
EXECUTE FUNCTION okeyix_stat_private.table_ended();

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA okeyix_stat_private FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.start_game(uuid),public.game_finish(uuid,uuid,jsonb,jsonb),
  public.leave_table(uuid,uuid),public.game_timeout_move(uuid,uuid),
  public.game_discard(uuid,uuid,jsonb,boolean,jsonb,boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.start_game(uuid),public.game_finish(uuid,uuid,jsonb,jsonb),
  public.leave_table(uuid,uuid),public.game_timeout_move(uuid,uuid),
  public.game_discard(uuid,uuid,jsonb,boolean,jsonb,boolean) TO authenticated,service_role;
COMMIT;

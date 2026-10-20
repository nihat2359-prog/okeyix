-- NOT APPLIED. Run only after review, first on an isolated/staging database.
-- Requires the three existing permanent statistics tables from the supplied inventory.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $check$
BEGIN
  IF current_user <> 'postgres' OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = current_user AND rolbypassrls
  ) THEN RAISE EXCEPTION 'STAT_DEPLOY_REQUIRES_POSTGRES_BYPASSRLS'; END IF;
  IF pg_catalog.to_regclass('public.okeyix_stat_sessions') IS NULL
    OR pg_catalog.to_regclass('public.okeyix_stat_rounds') IS NULL
    OR pg_catalog.to_regclass('public.okeyix_stat_players') IS NULL
  THEN RAISE EXCEPTION 'STAT_BASE_TABLES_MISSING'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint
    WHERE conrelid = 'public.okeyix_stat_rounds'::regclass
      AND conname = 'okeyix_stat_rounds_winner_participant_fk'
      AND condeferrable AND condeferred)
  THEN RAISE EXCEPTION 'STAT_WINNER_CONSTRAINT_MISMATCH'; END IF;
END $check$;

CREATE SCHEMA okeyix_stat_private AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA okeyix_stat_private FROM PUBLIC, anon, authenticated, service_role;

-- Typed, immutable event receipts. No hands, moves, names or raw RPC response JSON.
-- Historical source IDs deliberately have NO foreign keys to live game tables.
CREATE TABLE okeyix_stat_private.events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  table_id uuid NOT NULL,
  round_no bigint NOT NULL CHECK (round_no >= 0),
  seed text NOT NULL,
  kind text NOT NULL CHECK (kind IN ('begin','complete','abort','close')),
  league_id text,
  entry_coin bigint CHECK (entry_coin >= 0),
  occurred_at timestamptz NOT NULL,
  winner_user_id uuid,
  is_okey boolean NOT NULL DEFAULT false,
  is_double boolean NOT NULL DEFAULT false,
  reason text NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  processed_at timestamptz,
  attempts integer NOT NULL DEFAULT 0,
  retry_at timestamptz NOT NULL DEFAULT now(),
  error_code text,
  UNIQUE (table_id, round_no, seed, kind),
  CHECK ((kind = 'complete') = (winner_user_id IS NOT NULL)),
  CHECK (kind = 'complete' OR (NOT is_okey AND NOT is_double)),
  CHECK (kind = 'close' OR (round_no > 0 AND length(seed) > 0))
);
CREATE UNIQUE INDEX events_one_terminal ON okeyix_stat_private.events(table_id,round_no,seed)
  WHERE kind IN ('complete','abort');
CREATE INDEX events_pending ON okeyix_stat_private.events(id) WHERE processed_at IS NULL;
CREATE INDEX events_table_pending ON okeyix_stat_private.events(table_id,id)
  WHERE processed_at IS NULL;
CREATE TABLE okeyix_stat_private.event_players (
  event_id bigint NOT NULL REFERENCES okeyix_stat_private.events(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL,
  seat_index smallint NOT NULL CHECK (seat_index >= 0),
  is_bot boolean NOT NULL,
  coin_entry bigint CHECK (coin_entry >= 0),
  coin_reward bigint CHECK (coin_reward >= 0),
  coin_refund bigint CHECK (coin_refund >= 0),
  coin_bonus bigint CHECK (coin_bonus >= 0),
  coin_penalty bigint CHECK (coin_penalty >= 0),
  rating_delta integer,
  PRIMARY KEY (event_id,user_id),
  UNIQUE (event_id,seat_index)
);
-- Deployment/rollback metadata only, never client accessible.
CREATE TABLE okeyix_stat_private.original_acl (
  name text PRIMARY KEY, arguments text NOT NULL, acl aclitem[]
);
ALTER TABLE okeyix_stat_private.events ENABLE ROW LEVEL SECURITY;
ALTER TABLE okeyix_stat_private.event_players ENABLE ROW LEVEL SECURITY;
ALTER TABLE okeyix_stat_private.original_acl ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA okeyix_stat_private FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA okeyix_stat_private FROM PUBLIC,anon,authenticated,service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA okeyix_stat_private
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

-- These tables already have participant SELECT policies. Remove inherited API DML,
-- REFERENCES and TRIGGER grants as well; do not broaden their SELECT policies.
REVOKE ALL ON public.okeyix_stat_sessions, public.okeyix_stat_rounds,
  public.okeyix_stat_players FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON public.okeyix_stat_sessions, public.okeyix_stat_rounds,
  public.okeyix_stat_players TO authenticated,service_role;

CREATE FUNCTION okeyix_stat_private.project_event(p_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $body$
DECLARE
  e okeyix_stat_private.events%ROWTYPE;
  s public.okeyix_stat_sessions%ROWTYPE;
  r public.okeyix_stat_rounds%ROWTYPE;
  old_round record;
  k text;
BEGIN
  SELECT * INTO STRICT e FROM okeyix_stat_private.events WHERE id = p_id FOR UPDATE;
  SELECT * INTO s FROM public.okeyix_stat_sessions WHERE table_id = e.table_id FOR UPDATE;
  IF e.kind = 'begin' THEN
    IF s.id IS NULL THEN
      INSERT INTO public.okeyix_stat_sessions(table_id,league_id,entry_coin,started_at)
      VALUES(e.table_id,e.league_id,e.entry_coin,e.occurred_at) RETURNING * INTO s;
    ELSIF s.ended_at IS NOT NULL OR s.league_id IS DISTINCT FROM e.league_id
      OR s.entry_coin IS DISTINCT FROM e.entry_coin OR s.started_at > e.occurred_at THEN
      RAISE EXCEPTION 'STAT_SESSION_CONFLICT';
    END IF;
    k := e.table_id::text || ':' || e.round_no::text || ':' || e.seed;
    SELECT * INTO r FROM public.okeyix_stat_rounds WHERE source_start_key = k FOR UPDATE;
    IF r.id IS NOT NULL THEN
      IF r.session_id <> s.id OR r.round_no <> e.round_no OR r.started_at <> e.occurred_at
        OR EXISTS (
          (SELECT user_id,seat_index,is_bot,coin_entry FROM okeyix_stat_private.event_players WHERE event_id=e.id
           EXCEPT SELECT user_id,seat_index,is_bot,coin_entry FROM public.okeyix_stat_players WHERE round_id=r.id)
          UNION ALL
          (SELECT user_id,seat_index,is_bot,coin_entry FROM public.okeyix_stat_players WHERE round_id=r.id
           EXCEPT SELECT user_id,seat_index,is_bot,coin_entry FROM okeyix_stat_private.event_players WHERE event_id=e.id)
        ) THEN RAISE EXCEPTION 'STAT_BEGIN_REPLAY_CONFLICT'; END IF;
      RETURN;
    END IF;
    IF (SELECT count(*) FROM okeyix_stat_private.event_players WHERE event_id=e.id) NOT IN (2,4)
      OR EXISTS (SELECT 1 FROM public.okeyix_stat_rounds WHERE session_id=s.id AND round_no>=e.round_no)
    THEN RAISE EXCEPTION 'STAT_INVALID_BEGIN'; END IF;
    -- A new real deal proves the previous hand cannot continue. This affects only
    -- statistics, never the source game. Money on an unresolved hand stays unknown.
    FOR old_round IN SELECT id,started_at FROM public.okeyix_stat_rounds
      WHERE session_id=s.id AND status='started' FOR UPDATE LOOP
      UPDATE public.okeyix_stat_players SET outcome='aborted' WHERE round_id=old_round.id;
      UPDATE public.okeyix_stat_rounds SET status='aborted',finished_at=e.occurred_at
        WHERE id=old_round.id;
    END LOOP;
    INSERT INTO public.okeyix_stat_rounds(session_id,source_start_key,round_no,started_at)
    VALUES(s.id,k,e.round_no,e.occurred_at) RETURNING * INTO r;
    INSERT INTO public.okeyix_stat_players(round_id,user_id,round_started_at,seat_index,is_bot,coin_entry)
    SELECT r.id,user_id,r.started_at,seat_index,is_bot,coin_entry
    FROM okeyix_stat_private.event_players WHERE event_id=e.id;
    RETURN;
  END IF;

  -- No fabricated historical rows when capture was enabled halfway through a hand.
  IF s.id IS NULL THEN RETURN; END IF;
  IF e.kind = 'close' THEN
    FOR old_round IN SELECT id,started_at FROM public.okeyix_stat_rounds
      WHERE session_id=s.id AND status='started' FOR UPDATE LOOP
      UPDATE public.okeyix_stat_players SET outcome='aborted' WHERE round_id=old_round.id;
      UPDATE public.okeyix_stat_rounds SET status='aborted',finished_at=e.occurred_at
        WHERE id=old_round.id;
    END LOOP;
    UPDATE public.okeyix_stat_sessions SET ended_at=COALESCE(ended_at,e.occurred_at) WHERE id=s.id;
    RETURN;
  END IF;
  k := e.table_id::text || ':' || e.round_no::text || ':' || e.seed;
  SELECT * INTO r FROM public.okeyix_stat_rounds WHERE source_start_key=k FOR UPDATE;
  IF r.id IS NULL THEN RETURN; END IF;
  IF r.started_at > e.occurred_at THEN RAISE EXCEPTION 'STAT_TIME_CONFLICT'; END IF;
  IF e.kind='abort' THEN
    IF r.status='completed' THEN RAISE EXCEPTION 'STAT_TERMINAL_CONFLICT'; END IF;
    IF r.status='aborted' THEN
      IF r.finished_at IS DISTINCT FROM e.occurred_at THEN RAISE EXCEPTION 'STAT_ABORT_REPLAY_CONFLICT'; END IF;
      RETURN;
    END IF;
    UPDATE public.okeyix_stat_players SET outcome='aborted' WHERE round_id=r.id;
    UPDATE public.okeyix_stat_rounds SET status='aborted',finished_at=e.occurred_at WHERE id=r.id;
    RETURN;
  END IF;

  IF NOT EXISTS(SELECT 1 FROM public.okeyix_stat_players WHERE round_id=r.id AND user_id=e.winner_user_id)
    OR EXISTS (
      (SELECT user_id,seat_index,is_bot FROM public.okeyix_stat_players WHERE round_id=r.id
       EXCEPT SELECT user_id,seat_index,is_bot FROM okeyix_stat_private.event_players WHERE event_id=e.id)
      UNION ALL
      (SELECT user_id,seat_index,is_bot FROM okeyix_stat_private.event_players WHERE event_id=e.id
       EXCEPT SELECT user_id,seat_index,is_bot FROM public.okeyix_stat_players WHERE round_id=r.id)
    ) THEN RAISE EXCEPTION 'STAT_PARTICIPANTS_CONFLICT'; END IF;
  IF r.status='completed' THEN
    IF r.winner_user_id IS DISTINCT FROM e.winner_user_id
      OR r.is_okey_finish IS DISTINCT FROM e.is_okey OR r.is_double_finish IS DISTINCT FROM e.is_double
      OR r.finished_at IS DISTINCT FROM e.occurred_at OR EXISTS (
        SELECT 1 FROM public.okeyix_stat_players p
        JOIN okeyix_stat_private.event_players q ON q.user_id=p.user_id AND q.event_id=e.id
        WHERE p.round_id=r.id AND (
          p.outcome IS DISTINCT FROM CASE WHEN p.user_id=e.winner_user_id THEN 'win' ELSE 'loss' END
          OR ROW(p.coin_reward,p.coin_refund,p.coin_bonus,p.coin_penalty,p.rating_delta)
             IS DISTINCT FROM ROW(q.coin_reward,q.coin_refund,q.coin_bonus,q.coin_penalty,q.rating_delta)
        )
      ) THEN RAISE EXCEPTION 'STAT_FINISH_REPLAY_CONFLICT'; END IF;
    RETURN;
  END IF;
  IF r.status<>'started' THEN RAISE EXCEPTION 'STAT_TERMINAL_CONFLICT'; END IF;
  UPDATE public.okeyix_stat_players p SET
    outcome=CASE WHEN p.user_id=e.winner_user_id THEN 'win' ELSE 'loss' END,
    coin_reward=q.coin_reward,coin_refund=q.coin_refund,coin_bonus=q.coin_bonus,
    coin_penalty=q.coin_penalty,rating_delta=q.rating_delta
  FROM okeyix_stat_private.event_players q WHERE q.event_id=e.id AND p.round_id=r.id AND q.user_id=p.user_id;
  UPDATE public.okeyix_stat_rounds SET status='completed',winner_user_id=e.winner_user_id,
    is_okey_finish=e.is_okey,is_double_finish=e.is_double,finished_at=e.occurred_at WHERE id=r.id;
END $body$;

CREATE FUNCTION okeyix_stat_private.process_events(p_limit integer DEFAULT 100)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, pg_temp AS $body$
DECLARE e record; n integer:=0; i integer;
BEGIN
  IF p_limit NOT BETWEEN 1 AND 1000 OR p_limit IS NULL THEN RAISE EXCEPTION 'STAT_INVALID_BATCH'; END IF;
  -- Only workers take this lock; game capture never waits for the projector.
  IF NOT pg_catalog.pg_try_advisory_xact_lock(214026,1) THEN RETURN 0; END IF;
  FOR i IN 1..p_limit LOOP
    SELECT x.id INTO e FROM okeyix_stat_private.events x
    WHERE x.processed_at IS NULL AND x.retry_at<=clock_timestamp()
      AND NOT EXISTS(SELECT 1 FROM okeyix_stat_private.events prior
        WHERE prior.table_id=x.table_id AND prior.id<x.id AND prior.processed_at IS NULL)
    ORDER BY x.id LIMIT 1 FOR UPDATE OF x SKIP LOCKED;
    IF NOT FOUND THEN EXIT; END IF;
    BEGIN
      PERFORM okeyix_stat_private.project_event(e.id);
      -- Surface the ONE deferred winner FK inside the retry boundary, not at COMMIT.
      SET CONSTRAINTS public.okeyix_stat_rounds_winner_participant_fk IMMEDIATE;
      SET CONSTRAINTS public.okeyix_stat_rounds_winner_participant_fk DEFERRED;
      UPDATE okeyix_stat_private.events SET processed_at=clock_timestamp(),error_code=NULL WHERE id=e.id;
      n:=n+1;
    EXCEPTION WHEN OTHERS THEN
      UPDATE okeyix_stat_private.events SET attempts=attempts+1,error_code=SQLSTATE,
        retry_at=clock_timestamp()+make_interval(secs=>least(300,5*(attempts+1))) WHERE id=e.id;
    END;
  END LOOP;
  RETURN n;
END $body$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA okeyix_stat_private FROM PUBLIC,anon,authenticated,service_role;
COMMIT;

-- ARCHIVED V1 DRAFT. DO NOT APPLY. Superseded by 20261020000100/00200/00300 migrations.
-- REVIEW DRAFT ONLY. NOT A MIGRATION. NOT EXECUTED.
-- Requires the three existing okeyix_stat_* tables described by the user.
-- Creates only two private statistics functions and their permissions.
-- No calls to these functions are added to any game RPC here.
-- Monetary/result JSON arguments are small, transient SERVER receipts, not stored JSON.
-- Never grant these functions to authenticated/anon to work around start_game's
-- SECURITY INVOKER context. That integration requires a separate approved decision.

BEGIN;

-- Fail deployment rather than silently running under an unexpected RLS context.
DO $preflight$
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'STAT_DRAFT_REQUIRES_POSTGRES_REVIEW_CONTEXT';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles
    WHERE rolname = 'postgres' AND (rolsuper OR rolbypassrls)
  ) THEN
    RAISE EXCEPTION 'STAT_OWNER_RLS_CONTEXT_REQUIRES_REVIEW';
  END IF;
END;
$preflight$;

CREATE FUNCTION public.okeyix_stat_begin_round(
  p_table_id uuid,
  p_shuffle_seed uuid,
  p_source_round bigint,
  p_started_at timestamptz,
  p_entry_receipts jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $body$
DECLARE
  v_source record;
  v_source_exists boolean;
  v_session public.okeyix_stat_sessions%ROWTYPE;
  v_round public.okeyix_stat_rounds%ROWTYPE;
  v_key text;
  v_players jsonb;
BEGIN
  IF p_table_id IS NULL OR p_shuffle_seed IS NULL
     OR p_source_round IS NULL OR p_source_round < 1
     OR p_started_at IS NULL THEN
    RAISE EXCEPTION 'STAT_INVALID_START_IDENTITY';
  END IF;
  v_key := p_table_id::text || ':' || p_source_round::text
           || ':' || p_shuffle_seed::text;

  IF jsonb_typeof(p_entry_receipts) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'STAT_INVALID_ENTRY_RECEIPTS';
  END IF;
  IF jsonb_array_length(p_entry_receipts) <> 2 OR EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_entry_receipts) AS e(value)
    WHERE jsonb_typeof(e.value) IS DISTINCT FROM 'object'
  ) THEN
    RAISE EXCEPTION 'STAT_INVALID_ENTRY_RECEIPTS';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_entry_receipts) AS e(value)
    WHERE NOT (e.value ?& ARRAY['user_id', 'coin_entry'])
       OR EXISTS (
         SELECT 1 FROM jsonb_object_keys(e.value) AS k(name)
         WHERE k.name NOT IN ('user_id', 'coin_entry')
       )
  ) THEN
    RAISE EXCEPTION 'STAT_INVALID_ENTRY_RECEIPTS';
  END IF;
  IF (SELECT count(DISTINCT e.user_id)
      FROM jsonb_to_recordset(p_entry_receipts)
        AS e(user_id uuid, coin_entry bigint)) <> 2
     OR EXISTS (
       SELECT 1 FROM jsonb_to_recordset(p_entry_receipts)
         AS e(user_id uuid, coin_entry bigint)
       WHERE e.coin_entry < 0
     ) THEN
    RAISE EXCEPTION 'STAT_INVALID_ENTRY_RECEIPTS';
  END IF;

  -- Shared lock order in BOTH functions: game table -> stat session -> stat round.
  -- No game data is written. Inside the approved game transaction this table
  -- lock is already owned by that transaction.
  SELECT t.id, t.status, t.max_players, t.league_id, t.entry_coin,
         t.round_count, t.shuffle_seed, t.turn_started_at
  INTO v_source
  FROM public.tables AS t WHERE t.id = p_table_id
  FOR UPDATE;
  v_source_exists := FOUND;

  SELECT s.* INTO v_session
  FROM public.okeyix_stat_sessions AS s WHERE s.table_id = p_table_id
  FOR UPDATE;

  IF FOUND THEN
    SELECT r.* INTO v_round
    FROM public.okeyix_stat_rounds AS r
    WHERE r.session_id = v_session.id AND r.source_start_key = v_key
    FOR UPDATE;

    IF FOUND THEN
      -- Check the original receipt, not the current live roster or balance.
      -- An exact replay also works after the game table has been deleted.
      IF v_round.round_no IS DISTINCT FROM p_source_round
         OR v_round.started_at IS DISTINCT FROM p_started_at
         OR (SELECT count(*) FROM public.okeyix_stat_players AS sp
             WHERE sp.round_id = v_round.id) <> 2
         OR EXISTS (
           SELECT 1
           FROM jsonb_to_recordset(p_entry_receipts)
             AS e(user_id uuid, coin_entry bigint)
           LEFT JOIN public.okeyix_stat_players AS sp
             ON sp.round_id = v_round.id AND sp.user_id = e.user_id
           WHERE sp.user_id IS NULL
              OR sp.coin_entry IS DISTINCT FROM e.coin_entry
         ) THEN
        RAISE EXCEPTION 'STAT_START_REPLAY_CONFLICT';
      END IF;
      RETURN v_round.id;
    END IF;
    IF v_session.ended_at IS NOT NULL THEN
      RAISE EXCEPTION 'STAT_SESSION_ALREADY_CLOSED';
    END IF;
  END IF;

  -- Only the actual new-distribution path may create a previously unknown round.
  -- The matching turn_started_at is valid HERE, immediately after distribution;
  -- it must never be read later to reconstruct a historical start time.
  IF NOT v_source_exists THEN
    RAISE EXCEPTION 'STAT_SOURCE_TABLE_MISSING';
  END IF;
  IF v_source.status IS DISTINCT FROM 'playing'
     OR v_source.max_players IS DISTINCT FROM 2
     OR v_source.round_count::bigint IS DISTINCT FROM p_source_round
     OR v_source.shuffle_seed IS DISTINCT FROM p_shuffle_seed::text
     OR v_source.turn_started_at IS DISTINCT FROM p_started_at THEN
    RAISE EXCEPTION 'STAT_SOURCE_START_MISMATCH';
  END IF;
  IF v_source.entry_coin < 0 OR v_source.league_id IS NULL
     OR length(btrim(v_source.league_id)) = 0 THEN
    RAISE EXCEPTION 'STAT_INVALID_SESSION_SNAPSHOT';
  END IF;

  -- Snapshot actual server participants and bot flags, never caller-supplied flags.
  SELECT jsonb_agg(jsonb_build_object(
           'user_id', tp.user_id, 'seat_index', tp.seat_index, 'is_bot', u.is_bot
         ) ORDER BY tp.seat_index)
  INTO v_players
  FROM public.table_players AS tp
  LEFT JOIN public.users AS u ON u.id = tp.user_id
  WHERE tp.table_id = p_table_id;

  IF v_players IS NULL OR jsonb_array_length(v_players) <> 2 THEN
    RAISE EXCEPTION 'STAT_EXPECTED_TWO_PLAYERS';
  END IF;
  IF (SELECT count(DISTINCT x.user_id) FROM jsonb_to_recordset(v_players)
        AS x(user_id uuid, seat_index integer, is_bot boolean)) <> 2
     OR (SELECT count(DISTINCT x.seat_index) FROM jsonb_to_recordset(v_players)
        AS x(user_id uuid, seat_index integer, is_bot boolean)) <> 2
     OR EXISTS (
       SELECT 1 FROM jsonb_to_recordset(v_players)
         AS x(user_id uuid, seat_index integer, is_bot boolean)
       WHERE x.user_id IS NULL OR x.is_bot IS NULL
          OR x.seat_index IS NULL OR x.seat_index NOT IN (0, 1)
     ) THEN
    RAISE EXCEPTION 'STAT_INVALID_SERVER_PARTICIPANTS';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_to_recordset(p_entry_receipts)
      AS e(user_id uuid, coin_entry bigint)
    WHERE e.coin_entry > v_source.entry_coin
       OR NOT EXISTS (
         SELECT 1 FROM jsonb_to_recordset(v_players)
           AS x(user_id uuid, seat_index integer, is_bot boolean)
         WHERE x.user_id = e.user_id
       )
  ) THEN
    RAISE EXCEPTION 'STAT_ENTRY_PARTICIPANT_OR_AMOUNT_MISMATCH';
  END IF;

  IF v_session.id IS NULL THEN
    INSERT INTO public.okeyix_stat_sessions(
      id, table_id, league_id, entry_coin, started_at
    ) VALUES (
      gen_random_uuid(), p_table_id, v_source.league_id,
      v_source.entry_coin, p_started_at
    ) RETURNING * INTO v_session;
  ELSIF v_session.league_id IS DISTINCT FROM v_source.league_id
     OR v_session.entry_coin IS DISTINCT FROM v_source.entry_coin
     OR p_started_at < v_session.started_at THEN
    RAISE EXCEPTION 'STAT_SESSION_SNAPSHOT_CHANGED';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.okeyix_stat_rounds AS r
    WHERE r.session_id = v_session.id AND r.status = 'started'
  ) THEN
    RAISE EXCEPTION 'STAT_PREVIOUS_ROUND_STILL_OPEN';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.okeyix_stat_rounds AS r
    WHERE r.session_id = v_session.id AND r.round_no >= p_source_round
  ) THEN
    RAISE EXCEPTION 'STAT_SOURCE_ROUND_CONFLICT';
  END IF;

  INSERT INTO public.okeyix_stat_rounds(
    id, session_id, source_start_key, round_no, status, started_at
  ) VALUES (
    gen_random_uuid(), v_session.id, v_key, p_source_round, 'started', p_started_at
  ) RETURNING * INTO v_round;

  INSERT INTO public.okeyix_stat_players(
    round_id, user_id, round_started_at, seat_index, is_bot, outcome, coin_entry
  )
  SELECT v_round.id, x.user_id, p_started_at, x.seat_index::smallint,
         x.is_bot, 'pending', e.coin_entry
  FROM jsonb_to_recordset(v_players)
    AS x(user_id uuid, seat_index integer, is_bot boolean)
  JOIN jsonb_to_recordset(p_entry_receipts)
    AS e(user_id uuid, coin_entry bigint) ON e.user_id = x.user_id;

  RETURN v_round.id;
END;
$body$;

CREATE FUNCTION public.okeyix_stat_finalize_round(
  p_table_id uuid,
  p_shuffle_seed uuid,
  p_source_round bigint,
  p_winner_user_id uuid,
  p_is_okey boolean,
  p_is_double boolean,
  p_finished_at timestamptz,
  p_player_results jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $body$
DECLARE
  v_source record;
  v_source_exists boolean;
  v_session public.okeyix_stat_sessions%ROWTYPE;
  v_round public.okeyix_stat_rounds%ROWTYPE;
  v_key text;
BEGIN
  IF p_table_id IS NULL OR p_shuffle_seed IS NULL
     OR p_source_round IS NULL OR p_source_round < 1
     OR p_winner_user_id IS NULL OR p_is_okey IS NULL OR p_is_double IS NULL
     OR p_finished_at IS NULL THEN
    RAISE EXCEPTION 'STAT_INVALID_FINISH_IDENTITY';
  END IF;
  v_key := p_table_id::text || ':' || p_source_round::text
           || ':' || p_shuffle_seed::text;

  IF jsonb_typeof(p_player_results) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'STAT_INVALID_RESULT_RECEIPTS';
  END IF;
  IF jsonb_array_length(p_player_results) <> 2 OR EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_player_results) AS e(value)
    WHERE jsonb_typeof(e.value) IS DISTINCT FROM 'object'
  ) THEN
    RAISE EXCEPTION 'STAT_INVALID_RESULT_RECEIPTS';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_player_results) AS e(value)
    WHERE NOT (e.value ?& ARRAY[
      'user_id', 'coin_reward', 'coin_refund', 'coin_bonus',
      'coin_penalty', 'rating_delta'
    ]) OR EXISTS (
      SELECT 1 FROM jsonb_object_keys(e.value) AS k(name)
      WHERE k.name NOT IN (
        'user_id', 'coin_reward', 'coin_refund', 'coin_bonus',
        'coin_penalty', 'rating_delta'
      )
    )
  ) THEN
    RAISE EXCEPTION 'STAT_INVALID_RESULT_RECEIPTS';
  END IF;
  IF (SELECT count(DISTINCT x.user_id)
      FROM jsonb_to_recordset(p_player_results) AS x(
        user_id uuid, coin_reward bigint, coin_refund bigint,
        coin_bonus bigint, coin_penalty bigint, rating_delta integer
      )) <> 2 OR EXISTS (
        SELECT 1 FROM jsonb_to_recordset(p_player_results) AS x(
          user_id uuid, coin_reward bigint, coin_refund bigint,
          coin_bonus bigint, coin_penalty bigint, rating_delta integer
        )
        WHERE x.coin_reward < 0 OR x.coin_refund < 0
           OR x.coin_bonus < 0 OR x.coin_penalty < 0
      ) THEN
    RAISE EXCEPTION 'STAT_INVALID_RESULT_RECEIPTS';
  END IF;

  SELECT t.id, t.status, t.round_count, t.shuffle_seed INTO v_source
  FROM public.tables AS t WHERE t.id = p_table_id FOR UPDATE;
  v_source_exists := FOUND;

  SELECT s.* INTO v_session
  FROM public.okeyix_stat_sessions AS s WHERE s.table_id = p_table_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'STAT_SESSION_NOT_FOUND';
  END IF;
  SELECT r.* INTO v_round
  FROM public.okeyix_stat_rounds AS r
  WHERE r.session_id = v_session.id AND r.source_start_key = v_key
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'STAT_ROUND_NOT_FOUND';
  END IF;
  IF v_round.round_no IS DISTINCT FROM p_source_round THEN
    RAISE EXCEPTION 'STAT_SOURCE_ROUND_CONFLICT';
  END IF;

  PERFORM sp.user_id FROM public.okeyix_stat_players AS sp
  WHERE sp.round_id = v_round.id ORDER BY sp.user_id FOR UPDATE;

  IF (SELECT count(*) FROM public.okeyix_stat_players AS sp
      WHERE sp.round_id = v_round.id) <> 2 THEN
    RAISE EXCEPTION 'STAT_EXPECTED_TWO_RECORDED_PLAYERS';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.okeyix_stat_players AS sp
    WHERE sp.round_id = v_round.id AND sp.user_id = p_winner_user_id
  ) THEN
    RAISE EXCEPTION 'STAT_WINNER_NOT_PARTICIPANT';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_to_recordset(p_player_results) AS x(
      user_id uuid, coin_reward bigint, coin_refund bigint,
      coin_bonus bigint, coin_penalty bigint, rating_delta integer
    )
    WHERE NOT EXISTS (
      SELECT 1 FROM public.okeyix_stat_players AS sp
      WHERE sp.round_id = v_round.id AND sp.user_id = x.user_id
    )
  ) THEN
    RAISE EXCEPTION 'STAT_RESULT_PARTICIPANTS_MISMATCH';
  END IF;

  IF v_round.status = 'completed' THEN
    IF v_round.winner_user_id IS DISTINCT FROM p_winner_user_id
       OR v_round.is_okey_finish IS DISTINCT FROM p_is_okey
       OR v_round.is_double_finish IS DISTINCT FROM p_is_double
       OR v_round.finished_at IS DISTINCT FROM p_finished_at
       OR EXISTS (
         SELECT 1 FROM public.okeyix_stat_players AS sp
         JOIN jsonb_to_recordset(p_player_results) AS x(
           user_id uuid, coin_reward bigint, coin_refund bigint,
           coin_bonus bigint, coin_penalty bigint, rating_delta integer
         ) ON x.user_id = sp.user_id
         WHERE sp.round_id = v_round.id AND (
           sp.outcome IS DISTINCT FROM
             CASE WHEN sp.user_id = p_winner_user_id THEN 'win' ELSE 'loss' END
           OR ROW(sp.coin_reward, sp.coin_refund, sp.coin_bonus,
                  sp.coin_penalty, sp.rating_delta)
              IS DISTINCT FROM
              ROW(x.coin_reward, x.coin_refund, x.coin_bonus,
                  x.coin_penalty, x.rating_delta)
         )
       ) THEN
      RAISE EXCEPTION 'STAT_RESULT_REPLAY_CONFLICT';
    END IF;
    RETURN v_round.id;
  END IF;
  IF v_round.status <> 'started' THEN
    RAISE EXCEPTION 'STAT_ROUND_ALREADY_CLOSED';
  END IF;
  IF v_session.ended_at IS NOT NULL THEN
    RAISE EXCEPTION 'STAT_SESSION_ALREADY_CLOSED';
  END IF;
  IF p_finished_at < v_round.started_at THEN
    RAISE EXCEPTION 'STAT_INVALID_FINISH_TIME';
  END IF;
  IF NOT v_source_exists THEN
    RAISE EXCEPTION 'STAT_SOURCE_TABLE_MISSING';
  END IF;
  IF v_source.status IS DISTINCT FROM 'playing'
     OR v_source.round_count::bigint IS DISTINCT FROM p_source_round
     OR v_source.shuffle_seed IS DISTINCT FROM p_shuffle_seed::text THEN
    RAISE EXCEPTION 'STAT_SOURCE_FINISH_MISMATCH';
  END IF;

  UPDATE public.okeyix_stat_players AS sp
  SET outcome = CASE WHEN sp.user_id = p_winner_user_id THEN 'win' ELSE 'loss' END,
      coin_reward = x.coin_reward, coin_refund = x.coin_refund,
      coin_bonus = x.coin_bonus, coin_penalty = x.coin_penalty,
      rating_delta = x.rating_delta
  FROM jsonb_to_recordset(p_player_results) AS x(
    user_id uuid, coin_reward bigint, coin_refund bigint,
    coin_bonus bigint, coin_penalty bigint, rating_delta integer
  )
  WHERE sp.round_id = v_round.id AND sp.user_id = x.user_id;

  -- Both participants exist before the deferred winner FK is populated.
  -- Status and winner change in the SAME statement to satisfy CHECK constraints.
  UPDATE public.okeyix_stat_rounds AS r
  SET status = 'completed', winner_user_id = p_winner_user_id,
      is_okey_finish = p_is_okey, is_double_finish = p_is_double,
      finished_at = p_finished_at
  WHERE r.id = v_round.id;

  RETURN v_round.id;
END;
$body$;

ALTER FUNCTION public.okeyix_stat_begin_round(uuid, uuid, bigint, timestamptz, jsonb)
  OWNER TO postgres;
ALTER FUNCTION public.okeyix_stat_finalize_round(
  uuid, uuid, bigint, uuid, boolean, boolean, timestamptz, jsonb
) OWNER TO postgres;

REVOKE ALL ON FUNCTION public.okeyix_stat_begin_round(
  uuid, uuid, bigint, timestamptz, jsonb
) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.okeyix_stat_finalize_round(
  uuid, uuid, bigint, uuid, boolean, boolean, timestamptz, jsonb
) FROM PUBLIC, anon, authenticated, service_role;

-- Owner postgres retains EXECUTE. No client/service API grant is made.
-- Existing source RPCs, their permissions and all table policies are untouched.
COMMIT;

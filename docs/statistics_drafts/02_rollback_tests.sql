-- REVIEW DRAFT ONLY. NOT EXECUTED.
-- Run ONLY in an isolated database after reviewing/installing 01_functions.sql.
-- Do not run game RPCs or load production user data for these tests.
-- Source fixture must be prepared separately using its actual full DDL:
-- tables.id = 00000000-0000-4000-8000-000000000001,
-- status=playing, max_players=2, round_count>=1, UUID shuffle_seed,
-- non-null turn_started_at, entry_coin>=0 and a nonempty league_id.
-- Exactly two table_players at seats 0 and 1 with users/profiles rows; exactly one bot.
-- No stat session may already exist for the fixture table.
-- Full source fixture INSERTs are deliberately NOT invented from partial column data.
-- This script changes only stat rows and rolls all of them back.

-- ARCHIVED V1 TEST. Use test/statistics/integration.sql on an isolated local fixture.
BEGIN;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '15s';

DO $test$
DECLARE
  v_table uuid := '00000000-0000-4000-8000-000000000001';
  v_seed uuid;
  v_number bigint;
  v_started timestamptz;
  v_finished timestamptz;
  v_winner uuid;
  v_entries jsonb;
  v_results jsonb;
  v_conflict jsonb;
  v_round uuid;
  v_again uuid;
  v_before jsonb;
  v_after jsonb;
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'TEST_REQUIRES_POSTGRES';
  END IF;
  SELECT t.shuffle_seed::uuid, t.round_count::bigint, t.turn_started_at
  INTO v_seed, v_number, v_started
  FROM public.tables AS t
  WHERE t.id = v_table AND t.status = 'playing' AND t.max_players = 2;
  IF NOT FOUND OR v_seed IS NULL OR v_number < 1 OR v_started IS NULL THEN
    RAISE EXCEPTION 'ISOLATED_SOURCE_FIXTURE_REQUIRED';
  END IF;
  IF EXISTS (SELECT 1 FROM public.okeyix_stat_sessions WHERE table_id = v_table) THEN
    RAISE EXCEPTION 'FRESH_STAT_FIXTURE_REQUIRED';
  END IF;
  IF (SELECT count(*) FROM public.table_players tp
      JOIN public.users u ON u.id = tp.user_id
      JOIN public.profiles pr ON pr.id = tp.user_id
      WHERE tp.table_id = v_table) <> 2
     OR (SELECT count(*) FROM public.table_players tp
         JOIN public.users u ON u.id = tp.user_id
         WHERE tp.table_id = v_table AND u.is_bot) <> 1 THEN
    RAISE EXCEPTION 'ISOLATED_TWO_PROFILES_AND_ONE_BOT_REQUIRED';
  END IF;
  SELECT tp.user_id INTO v_winner FROM public.table_players AS tp
  JOIN public.users AS u ON u.id = tp.user_id
  WHERE tp.table_id = v_table ORDER BY u.is_bot DESC, tp.seat_index LIMIT 1;
  v_finished := v_started + interval '1 minute';

  -- Record that neither balance/rating nor old counters are touched.
  SELECT jsonb_agg(jsonb_build_object(
    'id', u.id, 'wins', u.wins, 'losses', u.losses,
    'coins', pr.coins, 'rating', pr.rating
  ) ORDER BY u.id)
  INTO v_before
  FROM public.table_players AS tp
  JOIN public.users AS u ON u.id = tp.user_id
  JOIN public.profiles AS pr ON pr.id = tp.user_id
  WHERE tp.table_id = v_table;

  SELECT jsonb_agg(jsonb_build_object(
    'user_id', tp.user_id, 'coin_entry', NULL
  ) ORDER BY tp.user_id)
  INTO v_entries FROM public.table_players AS tp WHERE tp.table_id = v_table;

  v_round := public.okeyix_stat_begin_round(
    v_table, v_seed, v_number, v_started, v_entries
  );
  v_again := public.okeyix_stat_begin_round(
    v_table, v_seed, v_number, v_started, v_entries
  );
  IF v_round IS DISTINCT FROM v_again
     OR (SELECT count(*) FROM public.okeyix_stat_players WHERE round_id = v_round) <> 2
     OR (SELECT count(*) FROM public.okeyix_stat_rounds AS r
         JOIN public.okeyix_stat_sessions AS s ON s.id = r.session_id
         WHERE s.table_id = v_table) <> 1 THEN
    RAISE EXCEPTION 'TEST_BEGIN_IDEMPOTENCY_FAILED';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.okeyix_stat_players AS sp
    JOIN public.users AS u ON u.id = sp.user_id
    JOIN public.table_players AS tp
      ON tp.table_id = v_table AND tp.user_id = sp.user_id
    WHERE sp.round_id = v_round
      AND (sp.is_bot IS DISTINCT FROM u.is_bot OR sp.seat_index <> tp.seat_index)
  ) THEN
    RAISE EXCEPTION 'TEST_SERVER_PLAYER_SNAPSHOT_FAILED';
  END IF;

  -- Explicitly unknown is NULL, never an invented zero.
  IF EXISTS (SELECT 1 FROM public.okeyix_stat_players
             WHERE round_id = v_round AND coin_net IS NOT NULL) THEN
    RAISE EXCEPTION 'TEST_NULL_NET_FAILED';
  END IF;

  v_conflict := jsonb_set(v_entries, '{0,coin_entry}', '1'::jsonb);
  BEGIN
    PERFORM public.okeyix_stat_begin_round(
      v_table, v_seed, v_number, v_started, v_conflict
    );
    RAISE EXCEPTION 'TEST_EXPECTED_START_CONFLICT';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'STAT_START_REPLAY_CONFLICT' THEN RAISE; END IF;
  END;

  -- Synthetic test receipts, NOT a claim about any real game's money.
  SELECT jsonb_agg(jsonb_build_object(
    'user_id', sp.user_id,
    'coin_reward', CASE WHEN sp.user_id = v_winner THEN 900 ELSE 0 END,
    'coin_refund', NULL, 'coin_bonus', NULL, 'coin_penalty', NULL,
    'rating_delta', CASE WHEN sp.user_id = v_winner THEN 8 ELSE 0 END
  ) ORDER BY sp.user_id)
  INTO v_results FROM public.okeyix_stat_players AS sp WHERE sp.round_id = v_round;

  BEGIN
    PERFORM public.okeyix_stat_finalize_round(
      v_table, v_seed, v_number, '00000000-0000-4000-8000-000000000099',
      true, true, v_finished, v_results
    );
    RAISE EXCEPTION 'TEST_EXPECTED_NONPARTICIPANT_REJECTION';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'STAT_WINNER_NOT_PARTICIPANT' THEN RAISE; END IF;
  END;

  v_again := public.okeyix_stat_finalize_round(
    v_table, v_seed, v_number, v_winner, true, true, v_finished, v_results
  );
  IF v_again IS DISTINCT FROM v_round THEN
    RAISE EXCEPTION 'TEST_FINALIZE_ID_FAILED';
  END IF;
  v_again := public.okeyix_stat_finalize_round(
    v_table, v_seed, v_number, v_winner, true, true, v_finished, v_results
  );
  IF v_again IS DISTINCT FROM v_round OR NOT EXISTS (
    SELECT 1 FROM public.okeyix_stat_rounds
    WHERE id = v_round AND status = 'completed' AND winner_user_id = v_winner
      AND is_okey_finish AND is_double_finish
  ) OR (SELECT count(*) FROM public.okeyix_stat_players
        WHERE round_id = v_round AND outcome = 'win') <> 1
    OR (SELECT count(*) FROM public.okeyix_stat_players
        WHERE round_id = v_round AND outcome = 'loss') <> 1 THEN
    RAISE EXCEPTION 'TEST_FINAL_RESULT_FAILED';
  END IF;

  BEGIN
    PERFORM public.okeyix_stat_finalize_round(
      v_table, v_seed, v_number, v_winner, false, true, v_finished, v_results
    );
    RAISE EXCEPTION 'TEST_EXPECTED_RESULT_CONFLICT';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'STAT_RESULT_REPLAY_CONFLICT' THEN RAISE; END IF;
  END;

  -- Unknown-to-known changes are also conflicts, not silent backfills.
  v_conflict := jsonb_set(v_results, '{0,coin_refund}', '0'::jsonb);
  BEGIN
    PERFORM public.okeyix_stat_finalize_round(
      v_table, v_seed, v_number, v_winner, true, true, v_finished, v_conflict
    );
    RAISE EXCEPTION 'TEST_EXPECTED_MONEY_CONFLICT';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM <> 'STAT_RESULT_REPLAY_CONFLICT' THEN RAISE; END IF;
  END;

  v_again := public.okeyix_stat_begin_round(
    v_table, v_seed, v_number, v_started, v_entries
  );
  IF v_again IS DISTINCT FROM v_round THEN
    RAISE EXCEPTION 'TEST_BEGIN_AFTER_FINALIZE_FAILED';
  END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'id', u.id, 'wins', u.wins, 'losses', u.losses,
    'coins', pr.coins, 'rating', pr.rating
  ) ORDER BY u.id)
  INTO v_after
  FROM public.table_players AS tp
  JOIN public.users AS u ON u.id = tp.user_id
  JOIN public.profiles AS pr ON pr.id = tp.user_id
  WHERE tp.table_id = v_table;
  IF v_before IS DISTINCT FROM v_after THEN
    RAISE EXCEPTION 'TEST_EXISTING_MONEY_OR_COUNTER_CHANGED';
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_catalog.pg_proc AS p
    JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
    CROSS JOIN (VALUES ('anon'), ('authenticated'), ('service_role')) AS test_role(name)
    WHERE n.nspname = 'public'
      AND p.proname IN ('okeyix_stat_begin_round', 'okeyix_stat_finalize_round')
      AND pg_catalog.has_function_privilege(test_role.name, p.oid, 'EXECUTE')
  ) THEN
    RAISE EXCEPTION 'TEST_PRIVATE_FUNCTION_ACL_FAILED';
  END IF;
END;
$test$;

-- Force deferred FK checks before rolling the test back.
-- This checks deferred validation, but does NOT claim a real COMMIT was tested.
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;

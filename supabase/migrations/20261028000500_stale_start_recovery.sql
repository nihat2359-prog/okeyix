-- Apply on staging first. Reuses the existing watchdog schedule and leave RPC.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $$
DECLARE f record;
BEGIN
  IF current_user <> 'postgres' THEN RAISE EXCEPTION 'START_RECOVERY_REQUIRES_POSTGRES'; END IF;
  IF to_regnamespace('okeyix_start_private') IS NOT NULL THEN
    RAISE EXCEPTION 'START_RECOVERY_ALREADY_INSTALLED';
  END IF;
  IF to_regprocedure('okeyix_bot_wallet_private.trusted()') IS NULL
    OR to_regprocedure('public.leave_table(uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION 'START_RECOVERY_GAME_WRAPPERS_REQUIRED';
  END IF;
  SELECT * INTO f FROM pg_proc WHERE oid=to_regprocedure('public.run_okey_watchdog()');
  IF NOT FOUND OR f.proowner <> 'postgres'::regrole OR NOT f.prosecdef
    OR (length(f.prosrc)-length(replace(f.prosrc,
      'result:=okeyix_bot_wallet_private.source_watchdog();','')))
      /length('result:=okeyix_bot_wallet_private.source_watchdog();') <> 1 THEN
    RAISE EXCEPTION 'START_RECOVERY_WATCHDOG_CONTRACT_CHANGED';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE active AND username='postgres'
    AND database=current_database() AND command ~ 'public\.run_okey_watchdog\(\)') THEN
    RAISE EXCEPTION 'START_RECOVERY_EXISTING_SCHEDULER_REQUIRED';
  END IF;
END $$;

CREATE SCHEMA okeyix_start_private AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA okeyix_start_private FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE okeyix_start_private.pending (
  table_id uuid PRIMARY KEY REFERENCES public.tables(id) ON DELETE CASCADE,
  entered_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE okeyix_start_private.pending ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON okeyix_start_private.pending FROM PUBLIC,anon,authenticated,service_role;

-- A new grace period for each start attempt, independent of table creation age.
CREATE FUNCTION okeyix_start_private.track_start() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
BEGIN
  IF NEW.status IN ('start','starting') THEN
    IF TG_OP='INSERT' THEN
      INSERT INTO okeyix_start_private.pending(table_id) VALUES(NEW.id)
        ON CONFLICT(table_id) DO NOTHING;
    ELSIF OLD.status NOT IN ('start','starting') OR OLD.status IS NULL THEN
      INSERT INTO okeyix_start_private.pending(table_id) VALUES(NEW.id)
        ON CONFLICT(table_id) DO UPDATE SET entered_at=clock_timestamp();
    END IF;
  ELSE
    DELETE FROM okeyix_start_private.pending WHERE table_id=NEW.id;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER okeyix_track_start AFTER INSERT OR UPDATE OF status ON public.tables
  FOR EACH ROW EXECUTE FUNCTION okeyix_start_private.track_start();

-- Existing stuck tables also receive the full grace period at installation.
INSERT INTO okeyix_start_private.pending(table_id)
  SELECT id FROM public.tables WHERE status IN ('start','starting');

CREATE FUNCTION okeyix_start_private.recover() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE
  candidate record;
  player record;
  cutoff timestamptz := statement_timestamp()-interval '2 minutes';
  removed integer := 0;
  recovered integer := 0;
  errors integer := 0;
  table_removed integer;
BEGIN
  IF NOT okeyix_bot_wallet_private.trusted() THEN
    RAISE EXCEPTION 'START_RECOVERY_SERVER_ONLY' USING ERRCODE='42501';
  END IF;
  -- Same lock order as game dispatch: table -> participants -> profiles.
  -- Bounded work and SKIP LOCKED keep live games and overlapping runs moving.
  FOR candidate IN
    SELECT t.id FROM public.tables t
    JOIN okeyix_start_private.pending s ON s.table_id=t.id
    WHERE t.status IN ('start','starting') AND s.entered_at<=cutoff
    ORDER BY s.entered_at,t.id LIMIT 50 FOR UPDATE OF t SKIP LOCKED
  LOOP
    table_removed:=0;
    BEGIN
      -- Never recover a paid/dealt hand using this pre-game path.
      IF EXISTS (SELECT 1 FROM public.table_players WHERE table_id=candidate.id
        AND (hand IS NOT NULL AND hand <> '[]'::jsonb)) THEN CONTINUE; END IF;
      PERFORM tp.id FROM public.table_players tp WHERE tp.table_id=candidate.id
        ORDER BY tp.id FOR UPDATE;
      FOR player IN
        SELECT p.id FROM public.profiles p
        JOIN public.users u ON u.id=p.id
        JOIN public.table_players tp ON tp.user_id=p.id
        WHERE tp.table_id=candidate.id AND u.is_bot=false
          AND p.last_seen_at IS NOT NULL AND p.last_seen_at<=cutoff
        ORDER BY p.id FOR UPDATE OF p SKIP LOCKED
      LOOP
        -- The presence row stays locked so a reconnect cannot race the decision.
        -- An online flag alone is insufficient: abruptly closed apps leave it true.
        IF NOT EXISTS (SELECT 1 FROM public.tables t WHERE t.id=candidate.id
          AND t.status IN ('start','starting','waiting')) THEN EXIT; END IF;
        PERFORM public.leave_table(candidate.id,player.id);
        IF EXISTS (SELECT 1 FROM public.table_players
          WHERE table_id=candidate.id AND user_id=player.id) THEN
          RAISE EXCEPTION 'START_RECOVERY_LEAVE_DID_NOT_REMOVE_PLAYER';
        END IF;
        table_removed:=table_removed+1;
      END LOOP;
      -- Existing leave may delete an empty table or already reset its state.
      -- Reset only after a verified stale human departure, never solely by age.
      IF table_removed>0 THEN
        UPDATE public.tables t SET status='waiting',ready_since=NULL
        WHERE t.id=candidate.id AND t.status IN ('start','starting','waiting')
          AND (SELECT count(*) FROM public.table_players tp WHERE tp.table_id=t.id)<t.max_players
          AND NOT EXISTS (SELECT 1 FROM public.table_players tp WHERE tp.table_id=t.id
            AND tp.hand IS NOT NULL AND tp.hand<>'[]'::jsonb);
        removed:=removed+table_removed;
        recovered:=recovered+1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      -- Per-table savepoint: failures must not stop other recovery or the watchdog.
      errors:=errors+1;
      RAISE WARNING 'START_RECOVERY_FAILED table=% sqlstate=%',candidate.id,SQLSTATE;
    END;
  END LOOP;
  RETURN jsonb_build_object('recovered_tables',recovered,'removed_players',removed,'errors',errors);
END $$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA okeyix_start_private FROM PUBLIC,anon,authenticated,service_role;

-- Preserve the watchdog's existing cleanup, statistics, wallets and ready tables.
DO $$
DECLARE definition text;
BEGIN
  SELECT pg_get_functiondef('public.run_okey_watchdog()'::regprocedure) INTO definition;
  EXECUTE replace(definition,'result:=okeyix_bot_wallet_private.source_watchdog();',
    E'PERFORM okeyix_start_private.recover();\n  result:=okeyix_bot_wallet_private.source_watchdog();');
END $$;
COMMIT;

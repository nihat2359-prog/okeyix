-- NOT APPLIED. Upgrade the existing read endpoint only; no game/payment writer changes.
BEGIN;
DO $$ BEGIN
  IF current_user<>'postgres' OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles WHERE rolname=current_user AND rolbypassrls
  ) THEN RAISE EXCEPTION 'STAT_SCORE_UPGRADE_REQUIRES_POSTGRES'; END IF;
END $$;

CREATE OR REPLACE FUNCTION public.okeyix_my_table_score(p_table_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $body$
DECLARE v_user uuid:=auth.uid();
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE='42501'; END IF;
  IF p_table_id IS NULL THEN RAISE EXCEPTION 'TABLE_REQUIRED' USING ERRCODE='22004'; END IF;
  -- One statement/snapshot: the projector commits the permanent result and its
  -- processed marker atomically. Reads see either the queued result or history.
  RETURN (
    WITH own_results AS (
      SELECT p.outcome
      FROM public.okeyix_stat_sessions s
      JOIN public.okeyix_stat_rounds r ON r.session_id=s.id AND r.status='completed'
      JOIN public.okeyix_stat_players p ON p.round_id=r.id AND p.user_id=v_user
      WHERE s.table_id=p_table_id
      UNION ALL
      SELECT CASE WHEN e.winner_user_id=v_user THEN 'win' ELSE 'loss' END
      FROM okeyix_stat_private.events e
      JOIN okeyix_stat_private.event_players p ON p.event_id=e.id AND p.user_id=v_user
      WHERE e.table_id=p_table_id AND e.kind='complete' AND e.processed_at IS NULL
        AND NOT EXISTS (
          SELECT 1 FROM public.okeyix_stat_rounds r
          WHERE r.source_start_key=e.table_id::text||':'||e.round_no::text||':'||e.seed
            AND r.status IN ('completed','aborted','draw')
        )
    )
    SELECT jsonb_build_object('table_id',p_table_id,
      'wins',count(*) FILTER(WHERE outcome='win'),
      'losses',count(*) FILTER(WHERE outcome='loss'))
    FROM own_results
  );
END $body$;
ALTER FUNCTION public.okeyix_my_table_score(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.okeyix_my_table_score(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.okeyix_my_table_score(uuid) TO authenticated;
-- No client schema/table privileges are added for the private outbox.
NOTIFY pgrst,'reload schema';
COMMIT;

-- NOT APPLIED. Run after migration 007. Read-only aggregation; no counter writes.
BEGIN;
DO $$ BEGIN
  IF current_user <> 'postgres' OR NOT EXISTS(SELECT 1 FROM pg_catalog.pg_roles
    WHERE rolname=current_user AND rolbypassrls)
  THEN RAISE EXCEPTION 'STAT_PROFILE_REQUIRES_POSTGRES'; END IF;
END $$;
CREATE OR REPLACE FUNCTION public.okeyix_profile_statistics(p_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $body$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE='42501';
  END IF;
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'PLAYER_REQUIRED' USING ERRCODE='22004';
  END IF;
  -- Profiles are public to signed-in players; return no personal information,
  -- wallets, opponents, hands or source IDs, including when reading another user.
  IF NOT EXISTS(SELECT 1 FROM public.users WHERE id=p_user_id) THEN
    RAISE EXCEPTION 'PLAYER_NOT_FOUND' USING ERRCODE='P0002';
  END IF;
  RETURN (
    WITH results AS (
      SELECT p.outcome,r.is_okey_finish AS is_okey,r.is_double_finish AS is_double
      FROM public.okeyix_stat_players p
      JOIN public.okeyix_stat_rounds r ON r.id=p.round_id AND r.status='completed'
      WHERE p.user_id=p_user_id
      UNION ALL
      -- Same statement/snapshot as history: projection commits its result and
      -- processed marker atomically. A committed finish is visible immediately.
      SELECT CASE WHEN e.winner_user_id=p_user_id THEN 'win' ELSE 'loss' END,
        e.is_okey,e.is_double
      FROM okeyix_stat_private.event_players p
      JOIN okeyix_stat_private.events e ON e.id=p.event_id
      WHERE p.user_id=p_user_id AND e.kind='complete' AND e.processed_at IS NULL
        AND NOT EXISTS(SELECT 1 FROM public.okeyix_stat_rounds r
          WHERE r.source_start_key=e.table_id::text||':'||e.round_no::text||':'||e.seed
            AND r.status IN ('completed','aborted','draw'))
    )
    SELECT jsonb_build_object(
      'wins',count(*) FILTER(WHERE outcome='win'),
      'losses',count(*) FILTER(WHERE outcome='loss'),
      'normal_wins',count(*) FILTER(WHERE outcome='win' AND NOT is_okey AND NOT is_double),
      'okey_wins',count(*) FILTER(WHERE outcome='win' AND is_okey),
      'double_wins',count(*) FILTER(WHERE outcome='win' AND is_double),
      'okey_double_wins',count(*) FILTER(WHERE outcome='win' AND is_okey AND is_double),
      'career_wins',u.wins,
      'career_losses',u.losses,
      'previous_wins',CASE WHEN u.wins >= count(*) FILTER(WHERE outcome='win')
        THEN u.wins - count(*) FILTER(WHERE outcome='win') ELSE NULL END
    ) FROM public.users u LEFT JOIN results ON true
    WHERE u.id=p_user_id GROUP BY u.id,u.wins,u.losses
  );
END $body$;
ALTER FUNCTION public.okeyix_profile_statistics(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.okeyix_profile_statistics(uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.okeyix_profile_statistics(uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;

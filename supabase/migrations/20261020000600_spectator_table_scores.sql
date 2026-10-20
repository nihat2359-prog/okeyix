-- NOT APPLIED. Read-only scores for the two seats shown by the spectator screen.
BEGIN;
DO $$ BEGIN
  IF current_user<>'postgres' OR NOT EXISTS(SELECT 1 FROM pg_catalog.pg_roles
    WHERE rolname=current_user AND rolbypassrls)
  THEN RAISE EXCEPTION 'STAT_SPECTATOR_SCORE_REQUIRES_POSTGRES'; END IF;
END $$;
CREATE FUNCTION public.okeyix_spectator_table_scores(p_table_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $body$
DECLARE viewer uuid:=auth.uid();
BEGIN
  IF viewer IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE='42501'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.tables t WHERE t.id=p_table_id AND (
    EXISTS(SELECT 1 FROM public.table_players WHERE table_id=t.id AND user_id=viewer)
    OR (t.spectators_enabled AND EXISTS(SELECT 1 FROM public.table_spectators
      WHERE table_id=t.id AND user_id=viewer))))
  THEN RAISE EXCEPTION 'TABLE_VIEW_ACCESS_REQUIRED' USING ERRCODE='42501'; END IF;
  RETURN (
    WITH participants AS (
      SELECT tp.user_id,tp.seat_index,COALESCE(u.username,'Oyuncu') AS username
      FROM public.table_players tp JOIN public.users u ON u.id=tp.user_id
      WHERE tp.table_id=p_table_id AND tp.seat_index IN (0,1)
    ), results AS (
      SELECT p.user_id,p.outcome
      FROM public.okeyix_stat_sessions s
      JOIN public.okeyix_stat_rounds r ON r.session_id=s.id AND r.status='completed'
      JOIN public.okeyix_stat_players p ON p.round_id=r.id
      JOIN participants q ON q.user_id=p.user_id
      WHERE s.table_id=p_table_id
      UNION ALL
      SELECT p.user_id,CASE WHEN e.winner_user_id=p.user_id THEN 'win' ELSE 'loss' END
      FROM okeyix_stat_private.events e
      JOIN okeyix_stat_private.event_players p ON p.event_id=e.id
      JOIN participants q ON q.user_id=p.user_id
      WHERE e.table_id=p_table_id AND e.kind='complete' AND e.processed_at IS NULL
        AND NOT EXISTS(SELECT 1 FROM public.okeyix_stat_rounds r
          WHERE r.source_start_key=e.table_id::text||':'||e.round_no::text||':'||e.seed
            AND r.status IN ('completed','aborted','draw'))
    ), counts AS (
      SELECT user_id,count(*) FILTER(WHERE outcome='win') AS wins,
        count(*) FILTER(WHERE outcome='loss') AS losses FROM results GROUP BY user_id
    )
    SELECT jsonb_build_object('table_id',p_table_id,'players',COALESCE(jsonb_agg(
      jsonb_build_object('user_id',p.user_id,'seat_index',p.seat_index,'username',p.username,
        'wins',COALESCE(c.wins,0),'losses',COALESCE(c.losses,0)) ORDER BY p.seat_index),'[]'::jsonb))
    FROM participants p LEFT JOIN counts c ON c.user_id=p.user_id
  );
END $body$;
ALTER FUNCTION public.okeyix_spectator_table_scores(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.okeyix_spectator_table_scores(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.okeyix_spectator_table_scores(uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;

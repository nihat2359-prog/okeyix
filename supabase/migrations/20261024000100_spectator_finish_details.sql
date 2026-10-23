-- NOT APPLIED. Read-only finish details for authenticated table participants.
-- Uses durable events immediately and processed rounds after event cleanup.
BEGIN;
DO $$ BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'POSTGRES_REQUIRED'; END IF;
END $$;
CREATE OR REPLACE FUNCTION public.okeyix_spectator_last_finish(p_table_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE viewer uuid:=auth.uid();
BEGIN
  IF viewer IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE='42501'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.tables t WHERE t.id=p_table_id AND (
    EXISTS(SELECT 1 FROM public.table_players p WHERE p.table_id=t.id AND p.user_id=viewer)
    OR (t.spectators_enabled AND EXISTS(SELECT 1 FROM public.table_spectators s
      WHERE s.table_id=t.id AND s.user_id=viewer))))
  THEN RAISE EXCEPTION 'TABLE_VIEW_ACCESS_REQUIRED' USING ERRCODE='42501'; END IF;
  RETURN (
    WITH recent AS (
      (SELECT e.winner_user_id,e.occurred_at AS finished_at,
        e.is_okey AS is_okey_finish,e.is_double AS is_double_finish
       FROM okeyix_stat_private.events e
       WHERE e.table_id=p_table_id AND e.kind='complete'
       ORDER BY e.occurred_at DESC,e.id DESC LIMIT 1)
      UNION ALL
      (SELECT r.winner_user_id,r.finished_at,r.is_okey_finish,r.is_double_finish
       FROM public.okeyix_stat_rounds r
       JOIN public.okeyix_stat_sessions s ON s.id=r.session_id
       WHERE s.table_id=p_table_id AND r.status='completed'
       ORDER BY r.finished_at DESC LIMIT 1)
    )
    SELECT jsonb_build_object('winner_user_id',r.winner_user_id,
      'username',coalesce(u.username,'Oyuncu'),'finished_at',r.finished_at,
      'is_okey_finish',r.is_okey_finish,'is_double_finish',r.is_double_finish)
    FROM recent r LEFT JOIN public.users u ON u.id=r.winner_user_id
    ORDER BY r.finished_at DESC LIMIT 1
  );
END $$;
ALTER FUNCTION public.okeyix_spectator_last_finish(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.okeyix_spectator_last_finish(uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.okeyix_spectator_last_finish(uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;

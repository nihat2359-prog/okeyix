-- NOT APPLIED. Read-only HUD endpoint; no game/payment/statistics writers changed.
BEGIN;
CREATE FUNCTION public.okeyix_my_table_score(p_table_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER
SET search_path=pg_catalog,pg_temp AS $$
  SELECT jsonb_build_object(
    'table_id',p_table_id,
    'wins',count(*) FILTER(WHERE p.outcome='win'),
    'losses',count(*) FILTER(WHERE p.outcome='loss')
  )
  FROM public.okeyix_stat_sessions s
  JOIN public.okeyix_stat_rounds r ON r.session_id=s.id AND r.status='completed'
  JOIN public.okeyix_stat_players p ON p.round_id=r.id AND p.user_id=auth.uid()
  WHERE s.table_id=p_table_id;
$$;
REVOKE ALL ON FUNCTION public.okeyix_my_table_score(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.okeyix_my_table_score(uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;

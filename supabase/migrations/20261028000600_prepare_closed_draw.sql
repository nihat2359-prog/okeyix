-- Read-only preparation for a closed-pile drag. Does not draw or reserve a tile.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
CREATE FUNCTION public.okeyix_prepare_closed_draw(p_table_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
  SELECT jsonb_build_object(
    'table_id',t.id,'user_id',p.user_id,'round_count',t.round_count,
    'turn_started_at',t.turn_started_at,
    'tile',t.deck->(jsonb_array_length(t.deck)-1))
  FROM public.tables t
  JOIN public.table_players p ON p.table_id=t.id AND p.user_id=auth.uid()
  WHERE t.id=p_table_id AND t.status='playing'
    AND p.seat_index=t.current_turn AND auth.uid() IS NOT NULL
    AND jsonb_typeof(p.hand)='array' AND jsonb_array_length(p.hand)=14
    AND jsonb_typeof(t.deck)='array' AND jsonb_array_length(t.deck)>1;
$$;
REVOKE ALL ON FUNCTION public.okeyix_prepare_closed_draw(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.okeyix_prepare_closed_draw(uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;

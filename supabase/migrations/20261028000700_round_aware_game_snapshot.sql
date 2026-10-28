-- Preserve the existing hand projection, adding authoritative round metadata
-- under the same table lock. No dealing, payment, timer or reward changes.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $$ BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'SNAPSHOT_REQUIRES_POSTGRES'; END IF;
  IF to_regprocedure('public.get_full_table_state(uuid)') IS NULL THEN
    RAISE EXCEPTION 'SNAPSHOT_SOURCE_REQUIRED';
  END IF;
END $$;
CREATE FUNCTION public.okeyix_full_table_state(p_table_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE t public.tables%ROWTYPE; result jsonb;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'GAME_CALLER_NOT_SEATED' USING ERRCODE='42501';
  END IF;
  SELECT * INTO t FROM public.tables WHERE id=p_table_id FOR SHARE;
  IF NOT FOUND THEN RETURN NULL; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.table_players
      WHERE table_id=p_table_id AND user_id=auth.uid()) THEN
    RAISE EXCEPTION 'GAME_CALLER_NOT_SEATED' USING ERRCODE='42501';
  END IF;
  result:=public.get_full_table_state(p_table_id)::jsonb;
  IF result IS NULL THEN RETURN NULL; END IF;
  IF jsonb_typeof(result->'table') IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'GAME_SNAPSHOT_INVALID_TABLE';
  END IF;
  RETURN jsonb_set(result,'{table}',(result->'table')||jsonb_build_object(
    'round_count',t.round_count,
    'status',t.status,
    'current_turn',t.current_turn,
    'turn_started_at',t.turn_started_at
  ));
END $$;
REVOKE ALL ON FUNCTION public.okeyix_full_table_state(uuid)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.okeyix_full_table_state(uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;

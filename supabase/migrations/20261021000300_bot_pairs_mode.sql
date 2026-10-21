-- NOT APPLIED. Optional bot pairs declaration endpoint. Validate in staging.
-- No game/payment/statistics RPC is replaced, no new table privileges granted.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $$ BEGIN
  IF current_user <> 'postgres' OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles WHERE rolname=current_user AND rolbypassrls
  ) THEN RAISE EXCEPTION 'BOT_PAIRS_REQUIRES_POSTGRES'; END IF;
  IF pg_catalog.to_regprocedure('public._okey_is_pairs_finish(jsonb)') IS NULL
    THEN RAISE EXCEPTION 'BOT_PAIRS_VALIDATOR_REQUIRED'; END IF;
END $$;

CREATE FUNCTION public.okeyix_bot_confirm_pairs(
  p_table_id uuid,p_user_id uuid,p_last_tile_id text,p_expected_round bigint
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE caller uuid:=auth.uid(); t record; player record; remaining jsonb;
BEGIN
  IF caller IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE='42501'; END IF;
  SELECT * INTO t FROM public.tables WHERE id=p_table_id FOR UPDATE;
  IF NOT FOUND OR t.status<>'playing' OR p_expected_round IS NULL
    OR greatest(coalesce(t.round_count,1),1)::bigint IS DISTINCT FROM p_expected_round
    THEN RAISE EXCEPTION 'BOT_PAIRS_STALE_TABLE' USING ERRCODE='22023'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.table_players tp JOIN public.users u ON u.id=tp.user_id
    WHERE tp.table_id=p_table_id AND tp.user_id=caller AND NOT u.is_bot)
    THEN RAISE EXCEPTION 'GAME_CALLER_NOT_SEATED' USING ERRCODE='42501'; END IF;
  SELECT tp.id,tp.hand INTO player FROM public.table_players tp
    JOIN public.users u ON u.id=tp.user_id
    WHERE tp.table_id=p_table_id AND tp.user_id=p_user_id AND u.is_bot
      AND tp.seat_index=t.current_turn FOR UPDATE OF tp;
  IF NOT FOUND THEN RAISE EXCEPTION 'BOT_PAIRS_NOT_CURRENT_BOT' USING ERRCODE='42501'; END IF;
  IF player.hand IS NULL OR jsonb_typeof(player.hand)<>'array'
    OR jsonb_array_length(player.hand)<>15
    OR (SELECT count(DISTINCT x->>'id') FROM jsonb_array_elements(player.hand) x)<>15
    OR EXISTS(SELECT 1 FROM jsonb_array_elements(player.hand) x WHERE coalesce(btrim(x->>'id'),'')='')
    OR (SELECT count(*) FROM jsonb_array_elements(player.hand) x WHERE x->>'id'=p_last_tile_id)<>1
    THEN RAISE EXCEPTION 'BOT_PAIRS_INVALID_HAND' USING ERRCODE='22023'; END IF;
  SELECT jsonb_agg(x ORDER BY ord) INTO remaining
    FROM jsonb_array_elements(player.hand) WITH ORDINALITY e(x,ord)
    WHERE x->>'id'<>p_last_tile_id;
  -- Server-owned tiles, not caller-supplied pairs or joker flags.
  IF public._okey_is_pairs_finish(remaining) IS DISTINCT FROM true
    THEN RETURN jsonb_build_object('ok',false); END IF;
  UPDATE public.table_players SET is_double_mode=true WHERE id=player.id;
  RETURN jsonb_build_object('ok',true);
END $$;
ALTER FUNCTION public.okeyix_bot_confirm_pairs(uuid,uuid,text,bigint) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.okeyix_bot_confirm_pairs(uuid,uuid,text,bigint)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.okeyix_bot_confirm_pairs(uuid,uuid,text,bigint) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;

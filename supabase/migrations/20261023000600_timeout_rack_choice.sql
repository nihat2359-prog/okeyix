-- NOT APPLIED. Deploy before the matching Flutter timeout change.
-- Keeps the existing statistics dispatcher, expiry checks and timeout penalties.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $patch$
DECLARE fn regprocedure:=to_regprocedure('okeyix_stat_private.source_game_timeout_move(uuid,uuid)');
  body text; definition text; pick_block text;
  old_pick text:=$old$  select value
    into v_pick
  from jsonb_array_elements(v_hand)
  where not public._tile_is_joker(value)
  order by 1 desc
  limit 1;$old$;
  prior_pick text:=$prior$  -- Prefer an isolated tile: preserve pairs, sets, runs and nearby run candidates.
  -- Ordinality identifies physical copies even when tile values are identical.
  with tiles as (
    select value as tile, ord,
      value->>'color' as color,
      case when coalesce(value->>'value',value->>'number','') ~ '^[0-9]+$'
        then coalesce(value->>'value',value->>'number')::int end as number
    from jsonb_array_elements(v_hand) with ordinality as h(value,ord)
  )
  select t.tile into v_pick
  from tiles t
  where not public._tile_is_joker(t.tile)
  order by
    case when t.number between 1 and 13 and t.color is not null
      and not exists (
        select 1 from tiles other
        where other.ord<>t.ord
          and not public._tile_is_joker(other.tile)
          and (other.number=t.number
            or (other.color=t.color and abs(other.number-t.number) between 1 and 2))
      ) then 0 else 1 end,
    t.tile desc
  limit 1;$prior$;
  new_pick text:=$new$  -- With 14 tiles, the draw above already assigned the timeout discard.
  -- A real joker cannot be discarded: retain the existing legal fallback.
  if not v_timeout_drew_tile or public._tile_is_joker(v_pick) then
    v_pick := null;
    if not v_timeout_drew_tile and auth.uid()=p_user_id then
      select value into v_pick from jsonb_array_elements(v_hand)
      where value->>'id'=nullif(current_setting('okeyix.timeout_tile_id',true),'')
        and not public._tile_is_joker(value)
      limit 1;
    end if;
    if v_pick is null then
  -- Prefer an isolated tile: preserve pairs, sets, runs and nearby run candidates.
  -- Ordinality identifies physical copies even when tile values are identical.
  with tiles as (
    select value as tile, ord,
      value->>'color' as color,
      case when coalesce(value->>'value',value->>'number','') ~ '^[0-9]+$'
        then coalesce(value->>'value',value->>'number')::int end as number
    from jsonb_array_elements(v_hand) with ordinality as h(value,ord)
  )
  select t.tile into v_pick
  from tiles t
  where not public._tile_is_joker(t.tile)
  order by
    case when t.number between 1 and 13 and t.color is not null
      and not exists (
        select 1 from tiles other
        where other.ord<>t.ord
          and not public._tile_is_joker(other.tile)
          and (other.number=t.number
            or (other.color=t.color and abs(other.number-t.number) between 1 and 2))
      ) then 0 else 1 end,
    t.tile desc
  limit 1;
    end if;
  end if;$new$;
BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'TIMEOUT_REQUIRES_POSTGRES'; END IF;
  old_pick:=replace(old_pick,chr(13)||chr(10),chr(10));
  prior_pick:=replace(prior_pick,chr(13)||chr(10),chr(10));
  new_pick:=replace(new_pick,chr(13)||chr(10),chr(10));
  SELECT replace(prosrc,chr(13)||chr(10),chr(10)) INTO body FROM pg_catalog.pg_proc
    WHERE oid=fn AND proowner='postgres'::regrole AND prosecdef;
  IF NOT FOUND THEN RAISE EXCEPTION 'TIMEOUT_SOURCE_REQUIRED'; END IF;
  IF md5(body)='6a7502a90bcac888ca3fd1d2e1065418' THEN RETURN; END IF;
  IF md5(body)='3c4351ef37986a6c56300861520fe8f9' THEN pick_block:=old_pick;
  ELSIF md5(body)='5efa4da4ba060df01d168db5f00ba7cc' THEN pick_block:=prior_pick;
  ELSE RAISE EXCEPTION 'TIMEOUT_SOURCE_CHANGED_REVIEW_REQUIRED'; END IF;
  definition:=replace(pg_catalog.pg_get_functiondef(fn),chr(13)||chr(10),chr(10));
  definition:=replace(definition,'  v_pick jsonb;',E'  v_pick jsonb;\n  v_timeout_drew_tile boolean := false;');
  definition:=replace(definition,'    v_pick := v_deck -> (v_deck_count - 1);',
    E'    v_timeout_drew_tile := true;\n    v_pick := v_deck -> (v_deck_count - 1);');
  IF position(pick_block in definition)=0 THEN RAISE EXCEPTION 'TIMEOUT_PICK_BLOCK_MISSING'; END IF;
  EXECUTE replace(definition,pick_block,new_pick);
  IF (SELECT md5(replace(prosrc,chr(13)||chr(10),chr(10))) FROM pg_catalog.pg_proc WHERE oid=fn)<>'6a7502a90bcac888ca3fd1d2e1065418'
    THEN RAISE EXCEPTION 'TIMEOUT_PATCH_MISMATCH'; END IF;
END $patch$;

-- The preference is transaction-local and only honoured for the authenticated
-- player's own hand. The existing dispatcher remains the only game entrypoint.
CREATE OR REPLACE FUNCTION public.okeyix_timeout_move_with_tile(
  p_table_id uuid,p_user_id uuid,p_preferred_tile_id text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE result jsonb; previous text:=current_setting('okeyix.timeout_tile_id',true);
BEGIN
  IF auth.uid() IS NULL OR auth.uid()<>p_user_id THEN
    RAISE EXCEPTION 'TIMEOUT_OWN_HAND_REQUIRED' USING ERRCODE='42501'; END IF;
  PERFORM set_config('okeyix.timeout_tile_id',coalesce(p_preferred_tile_id,''),true);
  result:=public.game_timeout_move(p_table_id,p_user_id);
  PERFORM set_config('okeyix.timeout_tile_id',coalesce(previous,''),true);
  RETURN result;
END $$;
ALTER FUNCTION public.okeyix_timeout_move_with_tile(uuid,uuid,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.okeyix_timeout_move_with_tile(uuid,uuid,text)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.okeyix_timeout_move_with_tile(uuid,uuid,text) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;
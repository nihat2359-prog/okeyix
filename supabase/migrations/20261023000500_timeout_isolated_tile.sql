-- NOT APPLIED. Changes timeout tile selection only, using the supplied live source.
-- Time limits, removal after 3 timeouts, drawing and discard/statistics stay intact.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $patch$
DECLARE
  fn regprocedure := to_regprocedure('okeyix_stat_private.source_game_timeout_move(uuid,uuid)');
  body text;
  definition text;
  old_block text := $old$  select value
    into v_pick
  from jsonb_array_elements(v_hand)
  where not public._tile_is_joker(value)
  order by 1 desc
  limit 1;$old$;
  new_block text := $new$  -- Prefer an isolated tile: preserve pairs, sets, runs and nearby run candidates.
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
  limit 1;$new$;
BEGIN
  -- SQL Editor may submit CRLF inside dollar-quoted blocks as well.
  old_block:=replace(old_block,chr(13)||chr(10),chr(10));
  new_block:=replace(new_block,chr(13)||chr(10),chr(10));
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'TIMEOUT_REQUIRES_POSTGRES'; END IF;
  IF fn IS NULL THEN RAISE EXCEPTION 'TIMEOUT_SOURCE_REQUIRED'; END IF;
  SELECT replace(prosrc,chr(13)||chr(10),chr(10)) INTO body FROM pg_catalog.pg_proc
    WHERE oid=fn AND proowner='postgres'::regrole AND prosecdef;
  IF NOT FOUND THEN RAISE EXCEPTION 'TIMEOUT_SOURCE_OWNER_OR_MODE_MISMATCH'; END IF;
  IF md5(body)='5efa4da4ba060df01d168db5f00ba7cc' THEN RETURN; END IF;
  IF md5(body)<>'3c4351ef37986a6c56300861520fe8f9' THEN RAISE EXCEPTION 'TIMEOUT_SOURCE_CHANGED_REVIEW_REQUIRED'; END IF;
  definition:=replace(pg_catalog.pg_get_functiondef(fn),chr(13)||chr(10),chr(10));
  IF position(old_block in definition)=0 THEN RAISE EXCEPTION 'TIMEOUT_PICK_BLOCK_MISSING'; END IF;
  EXECUTE replace(definition,old_block,new_block);
  IF (SELECT md5(replace(prosrc,chr(13)||chr(10),chr(10))) FROM pg_catalog.pg_proc WHERE oid=fn)<>'5efa4da4ba060df01d168db5f00ba7cc'
    THEN RAISE EXCEPTION 'TIMEOUT_PATCH_MISMATCH'; END IF;
END $patch$;
COMMIT;

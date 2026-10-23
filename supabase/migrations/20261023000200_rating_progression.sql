-- NOT APPLIED. Staging first. Winner rating only; no coin or game-rule changes.
-- 1200 -> 3000: 30 wins at +60 in the first four leagues.
-- At rating >= 3000: +5 in EVERY league, preventing lower-league fast farming.
-- Elite wins also award +5. Losses remain unchanged.
-- Source guarded against the function supplied on 2026-10-23 (LF/CRLF independent).
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $migration$
DECLARE
  fn regprocedure := to_regprocedure('okeyix_stat_private.source_game_finish(uuid,uuid,jsonb,jsonb)');
  body text;
  definition text;
  old_block text;
  new_block text := $replacement$v_rating_reward :=
  case
    when exists (
      select 1 from public.profiles
      where id = p_user_id and coalesce(rating, 1200) >= 3000
    ) or v_table.league_id::text = 'elite' then 5
    when v_table.league_id::text in ('standard','bronze','silver','gold') then 60
    else 8
  end;$replacement$;
BEGIN
  IF current_user <> 'postgres' THEN RAISE EXCEPTION 'RATING_REQUIRES_POSTGRES'; END IF;
  IF fn IS NULL THEN RAISE EXCEPTION 'RATING_FINISH_SOURCE_REQUIRED'; END IF;
  SELECT prosrc INTO body FROM pg_catalog.pg_proc
    WHERE oid=fn AND proowner='postgres'::regrole AND prosecdef;
  IF NOT FOUND THEN RAISE EXCEPTION 'RATING_SOURCE_OWNER_OR_MODE_MISMATCH'; END IF;
  IF md5(replace(body,chr(13)||chr(10),chr(10)))='a1dc04c518156acc8a7057c06e43fe73' THEN RETURN; END IF;
  IF md5(replace(body,chr(13)||chr(10),chr(10)))<>'240f3ce7853806b4daee457c5a40e9a2' THEN
    RAISE EXCEPTION 'RATING_SOURCE_CHANGED_REVIEW_REQUIRED';
  END IF;
  old_block := $original$v_rating_reward :=
  case v_table.league_id::text
    when 'standard' then 8
    when 'bronze' then 12
    when 'silver' then 16
    when 'gold' then 20
    when 'elite' then 24
    else 8
  end;$original$;
  -- SQL Editor may convert pasted line endings. Match the original body style
  -- and normalize only the replacement; preserve the rest of the function.
  old_block := replace(old_block,chr(13)||chr(10),chr(10));
  new_block := replace(new_block,chr(13)||chr(10),chr(10));
  IF position(old_block in body)=0 THEN
    old_block := replace(old_block,chr(10),chr(13)||chr(10));
  END IF;
  IF position(old_block in body)=0 THEN RAISE EXCEPTION 'RATING_REWARD_BLOCK_NOT_FOUND'; END IF;
  definition := pg_catalog.pg_get_functiondef(fn);
  -- CREATE OR REPLACE preserves function identity, owner, existing grants and
  -- SECURITY DEFINER settings. No new RPC or execute privilege is introduced.
  EXECUTE replace(definition,old_block,new_block);
  IF (SELECT md5(replace(prosrc,chr(13)||chr(10),chr(10))) FROM pg_catalog.pg_proc WHERE oid=fn)<>'a1dc04c518156acc8a7057c06e43fe73' THEN
    RAISE EXCEPTION 'RATING_SOURCE_PATCH_MISMATCH';
  END IF;
END
$migration$;
COMMIT;

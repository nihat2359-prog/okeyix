-- LOCAL TEST ONLY: pg_temp.timeout_pick is loaded from the migration selector.
DO $$
DECLARE h jsonb; picked jsonb; expected jsonb;
BEGIN
  -- The old JSON ordering would discard the 13 from the existing run.
  h := '[{"id":"run1","color":"red","value":11},{"id":"run2","color":"red","value":12},{"id":"run3","color":"red","value":13},{"id":"alone","color":"blue","value":2}]';
  IF pg_temp.timeout_pick(h)->>'id'<>'alone' THEN RAISE EXCEPTION 'RUN_WAS_BROKEN'; END IF;
  h := '[{"id":"set1","color":"red","value":13},{"id":"set2","color":"blue","value":13},{"id":"set3","color":"black","value":13},{"id":"alone","color":"red","value":2}]';
  IF pg_temp.timeout_pick(h)->>'id'<>'alone' THEN RAISE EXCEPTION 'SET_WAS_BROKEN'; END IF;
  h := '[{"id":"pair1","color":"red","value":13},{"id":"pair2","color":"red","value":13},{"id":"alone","color":"blue","value":2}]';
  IF pg_temp.timeout_pick(h)->>'id'<>'alone' THEN RAISE EXCEPTION 'PAIR_WAS_BROKEN'; END IF;
  h := '[{"id":"near1","color":"red","number":11},{"id":"near2","color":"red","number":13},{"id":"alone","color":"blue","number":2}]';
  IF pg_temp.timeout_pick(h)->>'id'<>'alone' THEN RAISE EXCEPTION 'NEARBY_RUN_OR_NUMBER_ALIAS'; END IF;
  h := '[{"id":"run1","color":"red","value":11},{"id":"run2","color":"red","value":12},{"id":"run3","color":"red","value":13}]';
  SELECT value INTO expected FROM jsonb_array_elements(h) WHERE NOT public._tile_is_joker(value) ORDER BY 1 DESC LIMIT 1;
  IF pg_temp.timeout_pick(h)<>expected THEN RAISE EXCEPTION 'FALLBACK_CHANGED'; END IF;
  h := '[{"id":"joker","color":"blue","value":8,"is_joker":true},{"id":"alone","color":"red","value":2}]';
  IF pg_temp.timeout_pick(h)->>'id'<>'alone' THEN RAISE EXCEPTION 'JOKER_DISCARDED'; END IF;
  h := '[{"id":"joker","is_joker":true}]';
  IF pg_temp.timeout_pick(h)<>h->0 THEN RAISE EXCEPTION 'ALL_JOKER_FALLBACK_CHANGED'; END IF;
  IF pg_temp.timeout_pick('[]'::jsonb) IS NOT NULL THEN RAISE EXCEPTION 'EMPTY_HAND'; END IF;
END $$;
SELECT '8 timeout selector checks passed' AS result;

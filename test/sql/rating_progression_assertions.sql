-- Local isolated PostgreSQL only. Evaluate the actual patched CASE expression.
DO $$
DECLARE source text; expression text; reward integer; league text; i integer;
BEGIN
  SELECT prosrc INTO source FROM pg_proc WHERE oid=
    'okeyix_stat_private.source_game_finish(uuid,uuid,jsonb,jsonb)'::regprocedure;
  expression := split_part(split_part(source,'v_rating_reward :=',2),'end;',1)||'end';
  IF expression IS NULL THEN RAISE EXCEPTION 'NO_REWARD_EXPRESSION'; END IF;
  expression := replace(expression,'v_table.league_id::text','p_league');
  EXECUTE 'CREATE OR REPLACE FUNCTION public.test_reward(p_user_id uuid,p_league text) '
    ||'RETURNS integer LANGUAGE plpgsql AS '||quote_literal('BEGIN RETURN '||expression||'; END');
  FOR league IN SELECT unnest(ARRAY['standard','bronze','silver','gold']) LOOP
    UPDATE public.profiles SET rating=1200;
    SELECT public.test_reward(id,league) INTO reward FROM public.profiles;
    IF reward<>60 THEN RAISE EXCEPTION 'LOW_RATING_REWARD %',league; END IF;
    UPDATE public.profiles SET rating=2999;
    SELECT public.test_reward(id,league) INTO reward FROM public.profiles;
    IF reward<>60 THEN RAISE EXCEPTION 'BELOW_BOUNDARY_REWARD'; END IF;
  END LOOP;
  FOR league IN SELECT unnest(ARRAY['standard','bronze','silver','gold','elite']) LOOP
    UPDATE public.profiles SET rating=3000;
    SELECT public.test_reward(id,league) INTO reward FROM public.profiles;
    IF reward<>5 THEN RAISE EXCEPTION 'HIGH_RATING_FARMING %',league; END IF;
    UPDATE public.profiles SET rating=34000;
    SELECT public.test_reward(id,league) INTO reward FROM public.profiles;
    IF reward<>5 THEN RAISE EXCEPTION 'HIGH_RATING_REWARD'; END IF;
  END LOOP;
  UPDATE public.profiles SET rating=1200;
  SELECT public.test_reward(id,'elite') INTO reward FROM public.profiles;
  IF reward<>5 THEN RAISE EXCEPTION 'ELITE_REWARD'; END IF;
  FOR i IN 1..29 LOOP
    UPDATE public.profiles SET rating=rating+public.test_reward(id,'standard');
  END LOOP;
  IF (SELECT rating FROM public.profiles)<>2940 THEN RAISE EXCEPTION 'WIN_29'; END IF;
  UPDATE public.profiles SET rating=rating+public.test_reward(id,'standard');
  IF (SELECT rating FROM public.profiles)<>3000 THEN RAISE EXCEPTION 'WIN_30'; END IF;
  UPDATE public.profiles SET rating=rating+public.test_reward(id,'standard');
  IF (SELECT rating FROM public.profiles)<>3005 THEN RAISE EXCEPTION 'WIN_31'; END IF;
  IF EXISTS(SELECT 1 FROM public.original_function o JOIN pg_proc p ON p.oid=o.oid
    WHERE p.proacl IS DISTINCT FROM o.proacl OR p.proowner<>o.proowner
      OR p.prosecdef<>o.prosecdef) THEN RAISE EXCEPTION 'PRIVILEGES_CHANGED'; END IF;
END $$;
SELECT 'Rating boundary, 30 wins, post-Champions and grants checks passed' AS result;

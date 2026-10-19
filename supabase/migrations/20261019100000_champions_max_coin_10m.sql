-- Local migration only: retain league identity, minimum and access rules.
DO $$
DECLARE
  current_max bigint;
BEGIN
  SELECT max_coin INTO current_max
    FROM public.leagues WHERE id = 'elite' FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Champions league elite not found; verify league identity before applying';
  END IF;
  IF current_max IS NULL OR current_max NOT IN (5000000, 10000000) THEN
    RAISE EXCEPTION 'Unexpected Champions maximum: %; review before applying', current_max;
  END IF;
  UPDATE public.leagues SET max_coin = 10000000 WHERE id = 'elite';
END;
$$;

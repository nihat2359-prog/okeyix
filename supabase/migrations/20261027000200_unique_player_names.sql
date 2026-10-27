-- NOT APPLIED. No existing account is renamed. Duplicates stop installation.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $$ BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'POSTGRES_REQUIRED'; END IF;
  IF EXISTS(SELECT 1 FROM public.users WHERE nullif(btrim(username),'') IS NOT NULL
    GROUP BY lower(btrim(username)) HAVING count(*)>1) THEN
    RAISE EXCEPTION 'PLAYER_NAMES_EXISTING_DUPLICATES_REVIEW_REQUIRED'; END IF;
END $$;
CREATE UNIQUE INDEX IF NOT EXISTS okeyix_users_player_name_unique
  ON public.users(lower(btrim(username))) WHERE nullif(btrim(username),'') IS NOT NULL;
COMMIT;

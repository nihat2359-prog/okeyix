-- NOT APPLIED. Blocks new bot seats in Masters and Champions, including older clients.
-- Does not remove existing seats, restart games or modify balances.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $$ BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'POSTGRES_REQUIRED'; END IF;
  IF (SELECT count(*) FROM public.leagues WHERE id::text IN ('gold','elite'))<>2 THEN
    RAISE EXCEPTION 'HUMAN_ONLY_LEAGUES_REQUIRED'; END IF;
END $$;

CREATE SCHEMA IF NOT EXISTS okeyix_league_private AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA okeyix_league_private FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION okeyix_league_private.guard_human_only_league()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,pg_temp AS $$
DECLARE league text;
BEGIN
  IF TG_TABLE_NAME='tables' THEN
    IF NEW.league_id::text IN ('gold','elite') AND EXISTS(
      SELECT 1 FROM public.table_players p JOIN public.users u ON u.id=p.user_id
      WHERE p.table_id=NEW.id AND u.is_bot
    ) THEN
      RAISE EXCEPTION 'HUMAN_ONLY_LEAGUE' USING ERRCODE='23514';
    END IF;
  ELSE
    -- Serialize seating with a concurrent league change on this table.
    SELECT t.league_id::text INTO league FROM public.tables t
      WHERE t.id=NEW.table_id FOR SHARE;
    IF league IN ('gold','elite') AND EXISTS(
      SELECT 1 FROM public.users u WHERE u.id=NEW.user_id AND u.is_bot
    ) THEN
      RAISE EXCEPTION 'HUMAN_ONLY_LEAGUE' USING ERRCODE='23514';
    END IF;
  END IF;
  RETURN NEW;
END $$;
ALTER FUNCTION okeyix_league_private.guard_human_only_league() OWNER TO postgres;
REVOKE ALL ON FUNCTION okeyix_league_private.guard_human_only_league()
  FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER upper_leagues_human_seat_guard
  BEFORE INSERT OR UPDATE OF table_id,user_id ON public.table_players
  FOR EACH ROW EXECUTE FUNCTION okeyix_league_private.guard_human_only_league();
CREATE TRIGGER upper_leagues_human_league_guard
  BEFORE UPDATE OF league_id ON public.tables
  FOR EACH ROW EXECUTE FUNCTION okeyix_league_private.guard_human_only_league();
COMMIT;

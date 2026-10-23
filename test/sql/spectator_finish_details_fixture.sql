-- LOCAL TEST ONLY. Loaded after timeout_rack_choice_fixture.sql.
ALTER TABLE public.tables ADD COLUMN spectators_enabled boolean DEFAULT true;
ALTER TABLE public.users ADD COLUMN username text;
CREATE TABLE public.table_spectators(table_id uuid,user_id uuid);
CREATE SCHEMA okeyix_stat_private;
CREATE TABLE okeyix_stat_private.events(id bigint,table_id uuid,winner_user_id uuid,
  occurred_at timestamptz,is_okey boolean,is_double boolean,kind text);
CREATE TABLE public.okeyix_stat_sessions(id uuid,table_id uuid);
CREATE TABLE public.okeyix_stat_rounds(session_id uuid,winner_user_id uuid,
  finished_at timestamptz,is_okey_finish boolean,is_double_finish boolean,status text);

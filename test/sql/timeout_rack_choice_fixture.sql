-- LOCAL DATABASE ONLY. Stand-ins for unrelated game infrastructure.
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE ROLE service_role;
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$
  SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid;
$$;
CREATE TABLE public.tables(id uuid PRIMARY KEY,status text,current_turn int,
  max_players int,deck jsonb,turn_seconds int,turn_started_at timestamptz,ready_since timestamptz);
CREATE TABLE public.table_players(id uuid PRIMARY KEY,table_id uuid,user_id uuid,
  seat_index int,hand jsonb,consecutive_timeouts int,is_double_mode boolean);
CREATE TABLE public.users(id uuid PRIMARY KEY,is_bot boolean);
CREATE TABLE public.table_discards(table_id uuid);
CREATE FUNCTION public.game_discard(uuid,uuid,jsonb,boolean,jsonb,boolean)
RETURNS jsonb LANGUAGE sql AS $$ SELECT jsonb_build_object('tile',$3); $$;
CREATE FUNCTION public.game_timeout_move(p_table_id uuid,p_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql AS $$ BEGIN
  RETURN okeyix_stat_private.source_game_timeout_move(p_table_id,p_user_id);
END $$;

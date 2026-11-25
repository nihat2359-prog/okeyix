-- Local-only simplified schema with a captured production RPC definition.
DO $$ BEGIN IF current_database()<>'okeyix_invite_priority_test' THEN
  RAISE EXCEPTION 'LOCAL_ONLY'; END IF; END $$;
CREATE TABLE public.users(id uuid PRIMARY KEY,is_bot boolean NOT NULL,avatar_url text);
CREATE TABLE public.profiles(id uuid PRIMARY KEY,username text,rating integer,coins integer,
  avatar varchar,is_online boolean,allow_game_invites boolean);
CREATE TABLE public.leagues(id text PRIMARY KEY,min_rating integer);
CREATE TABLE public.tables(id uuid PRIMARY KEY,status text);
CREATE TABLE public.table_players(table_id uuid,user_id uuid);
CREATE TABLE public.table_invites(table_id uuid,to_user uuid,status text);
INSERT INTO public.leagues VALUES('standard',0),('gold',0),('elite',0),('silver',2000);
INSERT INTO public.users
SELECT md5('human-'||n)::uuid,false,NULL FROM generate_series(1,110) n;
INSERT INTO public.profiles
SELECT md5('human-'||n)::uuid,'Human '||n,5000,1000000,NULL,n<=10,true
FROM generate_series(1,110) n;
INSERT INTO public.users
SELECT md5('old-bot-'||n)::uuid,true,'old-avatar' FROM generate_series(1,14) n;
INSERT INTO public.profiles
SELECT md5('old-bot-'||n)::uuid,'Old bot '||n,3000,200000000,NULL,false,true
FROM generate_series(1,14) n;
INSERT INTO public.users
SELECT md5('new-bot-'||n)::uuid,true,'new-avatar' FROM generate_series(1,150) n;
INSERT INTO public.profiles
SELECT md5('new-bot-'||n)::uuid,'New bot '||n,round((n-1)*1800.0/149)::int,200025000,NULL,false,true
FROM generate_series(1,150) n;
CREATE FUNCTION public.fixture_assert(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'ASSERT: %',label; END IF; END $$;


CREATE OR REPLACE FUNCTION public.get_invitable_players(p_table_id uuid, p_user_id uuid, p_league_id text, p_entry_coin integer)
 RETURNS TABLE(id uuid, username text, rating integer, coins integer, avatar_url text, is_bot boolean, is_in_game boolean)
 LANGUAGE sql
 STABLE
AS $function$
with league_data as (
  select l.min_rating
  from public.leagues l
  where l.id = p_league_id
),
excluded as (
  select tp.user_id
  from public.table_players tp
  where tp.table_id = p_table_id

  union

  select ti.to_user
  from public.table_invites ti
  where ti.table_id = p_table_id
    and ti.status = 'pending'

  union

  select p_user_id
),
active_users as (
  select distinct tp.user_id
  from public.table_players tp
  join public.tables t on t.id = tp.table_id
  where t.status in ('waiting', 'playing')
)
select
  p.id,
  p.username,
  p.rating,
  p.coins,
  coalesce(u.avatar_url, p.avatar) as avatar_url,
  coalesce(u.is_bot, false) as is_bot,
  (p.id in (select au.user_id from active_users au)) as is_in_game
from public.profiles p
join public.users u on u.id = p.id
cross join league_data l
where
  p.id not in (select e.user_id from excluded e)
  and p.rating >= l.min_rating
  and p.coins >= p_entry_coin
order by p.rating desc
limit 80;
$function$
;

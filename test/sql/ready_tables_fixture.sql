-- Isolated local fixture only; real supplied source definitions are loaded next.
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE ROLE service_role;
CREATE SCHEMA auth;
CREATE SCHEMA cron;
CREATE SCHEMA okeyix_bot_wallet_private;
CREATE TABLE auth.users(id uuid PRIMARY KEY,created_at timestamptz DEFAULT now(),
 raw_app_meta_data jsonb,banned_until timestamptz,last_sign_in_at timestamptz);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$
 SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql AS $$
 SELECT nullif(current_setting('request.jwt.claim.role',true),'') $$;
CREATE FUNCTION okeyix_bot_wallet_private.trusted() RETURNS boolean LANGUAGE sql AS $$
 SELECT (session_user='postgres' AND current_setting('role') IN ('none','postgres')
   AND coalesce(auth.role(),'') IN ('','postgres'))
 OR (current_setting('role')='service_role' AND auth.role()='service_role') $$;
CREATE FUNCTION okeyix_bot_wallet_private.replenish(text) RETURNS integer LANGUAGE sql AS $$ SELECT 0 $$;
CREATE TABLE okeyix_bot_wallet_private.registry(user_id uuid PRIMARY KEY);
CREATE TABLE public.users(id uuid PRIMARY KEY,is_bot boolean NOT NULL,username text);
CREATE TABLE public.profiles(id uuid PRIMARY KEY,coins integer,rating integer,
 is_online boolean DEFAULT false,last_seen_at timestamptz);
CREATE TABLE public.leagues(id text PRIMARY KEY,min_coin bigint,max_coin bigint,
 entry_coin bigint,min_rating integer,display_order integer,min_rounds integer,turn_seconds integer);
CREATE TABLE public.tables(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),league_id text REFERENCES public.leagues,
 created_by uuid NOT NULL REFERENCES auth.users ON DELETE CASCADE,status text,max_players integer,entry_coin integer,
 min_rounds integer,turn_seconds integer,spectators_enabled boolean,chat_enabled boolean,
 ready_since timestamptz,created_at timestamptz DEFAULT now(),pot_amount integer DEFAULT 0,
 current_turn integer,turn_started_at timestamptz);
CREATE TABLE public.table_players(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 table_id uuid REFERENCES public.tables ON DELETE CASCADE,user_id uuid REFERENCES public.users,
 seat_index integer,hand jsonb,is_double_mode boolean,consecutive_timeouts integer,
 UNIQUE(table_id,seat_index));
CREATE TABLE public.table_discards(table_id uuid REFERENCES public.tables ON DELETE CASCADE);
CREATE TABLE public.match_moves(table_id uuid REFERENCES public.tables ON DELETE CASCADE);
CREATE TABLE public.system_settings(key text,value jsonb);
CREATE TABLE cron.job(jobid bigint,username text,database text,command text,active boolean);
INSERT INTO cron.job VALUES(4,'postgres',current_database(),'select public.run_okey_watchdog();',true);
INSERT INTO public.leagues VALUES
 ('standard',1000,50000,1000,0,1,2,60),
 ('bronze',50000,250000,50000,1500,2,2,50),
 ('silver',250000,1000000,250000,2000,3,4,40),
 ('gold',1000000,3000000,1000000,2500,4,4,35),
 ('elite',3000000,10000000,3000000,3000,5,6,30);
INSERT INTO public.users SELECT md5('ready-bot-'||i)::uuid,true,'Bot '||i FROM generate_series(1,14) i;
INSERT INTO public.profiles SELECT id,200000000,2500,false,NULL FROM public.users;
INSERT INTO okeyix_bot_wallet_private.registry SELECT id FROM public.users;
INSERT INTO auth.users(id) VALUES(md5('human')::uuid);
INSERT INTO public.users VALUES(md5('human')::uuid,false,'Human');
INSERT INTO public.profiles VALUES(md5('human')::uuid,1000000,1200,true,now());
-- One real waiting table should reduce standard's bot target to two.
INSERT INTO public.tables(id,league_id,created_by,status,max_players,entry_coin,
 ready_since,spectators_enabled,chat_enabled)
VALUES(md5('human-table')::uuid,'standard',md5('human')::uuid,'waiting',2,1000,now(),true,true);
INSERT INTO public.table_players(table_id,user_id,seat_index)
VALUES(md5('human-table')::uuid,md5('human')::uuid,0);
-- Mimics a brand-new admin-created system account and ordinary signup rows.
INSERT INTO auth.users(id,raw_app_meta_data,banned_until)
 VALUES(md5('system-owner')::uuid,'{"okeyix_system":"ready_tables_owner"}',now()+interval '100 years');
INSERT INTO public.users VALUES(md5('system-owner')::uuid,false,'System Owner');
INSERT INTO public.profiles VALUES(md5('system-owner')::uuid,10000,1200,true,now());

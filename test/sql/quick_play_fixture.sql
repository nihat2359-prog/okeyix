-- LOCAL TEST DOUBLE CONTRACTS. Never run this file against Supabase.
DO $$ BEGIN IF current_database()<>'okeyix_quick_play_test' THEN RAISE EXCEPTION 'LOCAL_ONLY'; END IF; END $$;
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
 SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid;
$$;
CREATE TABLE auth.users(id uuid PRIMARY KEY);
CREATE TABLE public.users(id uuid PRIMARY KEY,is_bot boolean NOT NULL DEFAULT false,username text);
CREATE TABLE public.profiles(id uuid PRIMARY KEY,coins integer,rating integer,is_online boolean,last_seen_at timestamptz);
CREATE TABLE public.leagues(id text PRIMARY KEY,min_coin bigint,max_coin bigint,min_rating integer,min_rounds integer);
CREATE TABLE public.tables(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),league_id text,
 max_players integer,entry_coin integer,min_rounds integer,status text,created_by uuid,
 turn_seconds integer,spectators_enabled boolean,chat_enabled boolean,
 is_private boolean DEFAULT false,visibility text DEFAULT 'public',password_hash text);
CREATE TABLE public.table_players(id uuid DEFAULT gen_random_uuid() PRIMARY KEY,table_id uuid REFERENCES public.tables(id),
 user_id uuid,seat_index integer,hand jsonb,UNIQUE(table_id,user_id),UNIQUE(table_id,seat_index));
CREATE FUNCTION public.leave_table(p_table_id uuid,p_user_id uuid) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN DELETE FROM public.table_players WHERE table_id=p_table_id AND user_id=p_user_id; END $$;
CREATE FUNCTION public.test_seat_trigger() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 UPDATE public.tables SET status='start' WHERE id=NEW.table_id AND
 (SELECT count(*) FROM public.table_players WHERE table_id=NEW.table_id)=2;
 RETURN NULL; END $$;
CREATE TRIGGER seats AFTER INSERT ON public.table_players FOR EACH ROW EXECUTE FUNCTION public.test_seat_trigger();
INSERT INTO public.leagues VALUES('standard',1000,50000,0,2),('elite',3000000,10000000,100,2);
INSERT INTO public.users(id,is_bot,username) SELECT ('00000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,false,'Human '||i FROM generate_series(1,12) i;
INSERT INTO auth.users SELECT id FROM public.users;
INSERT INTO public.profiles SELECT id,20000000,50,true,clock_timestamp() FROM public.users;
INSERT INTO public.users VALUES('00000000-0000-0000-0000-000000000090',true,'Bot');
INSERT INTO public.profiles VALUES('00000000-0000-0000-0000-000000000090',20000000,200,false,clock_timestamp());


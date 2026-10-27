-- LOCAL ONLY. Separate database from retention/game fixtures.
\set ON_ERROR_STOP on
DO $$ BEGIN
  IF current_database()<>'okeyix_chat_test' THEN RAISE EXCEPTION 'LOCAL_CHAT_TEST_REQUIRED'; END IF;
END $$;
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid;
$$;
CREATE TABLE public.users(id uuid PRIMARY KEY,username text,avatar_url text);
CREATE TABLE public.tables(id uuid PRIMARY KEY,chat_enabled boolean DEFAULT true,
  spectators_enabled boolean DEFAULT true);
CREATE TABLE public.table_players(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  table_id uuid REFERENCES public.tables ON DELETE CASCADE,
  user_id uuid REFERENCES public.users ON DELETE CASCADE,seat_index integer NOT NULL,
  hand jsonb,is_ready boolean DEFAULT false,joined_at timestamptz DEFAULT now());
CREATE TABLE public.table_spectators(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  table_id uuid NOT NULL REFERENCES public.tables ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users,joined_at timestamptz DEFAULT now(),
  UNIQUE(table_id,user_id));
CREATE TABLE public.table_messages(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  table_id uuid NOT NULL REFERENCES public.tables ON DELETE CASCADE,
  sender_id uuid NOT NULL REFERENCES public.users,role text NOT NULL,content text NOT NULL,
  created_at timestamptz DEFAULT now(),type text DEFAULT 'text',voice_url text,duration integer);
GRANT USAGE ON SCHEMA public,auth TO authenticated;
GRANT SELECT ON public.users,public.tables TO authenticated;
GRANT ALL ON public.table_players,public.table_spectators,public.table_messages TO authenticated;
CREATE PUBLICATION chat_test_realtime FOR TABLE public.table_messages
  (id,table_id,sender_id,role,content,created_at,type,voice_url,duration);
INSERT INTO public.users VALUES
  ('00000000-0000-4000-8000-000000000001','Serkan','assets/avatar.png'),
  ('00000000-0000-4000-8000-000000000002','Berkay',null),
  ('00000000-0000-4000-8000-000000000003','İzleyen',null),
  ('00000000-0000-4000-8000-000000000004','Dışarıdaki',null);
INSERT INTO public.tables(id) VALUES('10000000-0000-4000-8000-000000000001'),
  ('10000000-0000-4000-8000-000000000002');
INSERT INTO public.table_players(table_id,user_id,seat_index,joined_at)
VALUES('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001',0,now()-interval '1 hour');
INSERT INTO public.table_messages(table_id,sender_id,role,content,created_at)
VALUES('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001',
  'player','old conversation',now()-interval '30 minutes');

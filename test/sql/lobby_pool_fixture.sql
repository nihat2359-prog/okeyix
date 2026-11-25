-- Loaded after ready_tables_fixture and the existing quick-play migrations.
ALTER TABLE public.users ADD COLUMN avatar_url text;
ALTER TABLE public.profiles ADD COLUMN username text,ADD COLUMN avatar text;
UPDATE public.profiles p SET username=u.username FROM public.users u WHERE u.id=p.id;
ALTER TABLE public.tables ADD COLUMN is_fake boolean NOT NULL DEFAULT false;
CREATE SCHEMA okeyix_ready_private;
CREATE TABLE okeyix_ready_private.policy(singleton boolean PRIMARY KEY DEFAULT true,
  enabled boolean NOT NULL DEFAULT true,target integer NOT NULL DEFAULT 3,owner_id uuid);
CREATE TABLE okeyix_ready_private.managed(table_id uuid PRIMARY KEY REFERENCES public.tables ON DELETE CASCADE,
  bot_id uuid,created_at timestamptz DEFAULT now());
INSERT INTO auth.users(id) VALUES('c1788536-38fa-407a-8fdc-02bf4d94d3c1');
INSERT INTO okeyix_ready_private.policy(owner_id) VALUES('c1788536-38fa-407a-8fdc-02bf4d94d3c1');
CREATE FUNCTION okeyix_ready_private.valid_owner(uuid) RETURNS boolean LANGUAGE sql AS $$
 SELECT $1='c1788536-38fa-407a-8fdc-02bf4d94d3c1'::uuid $$;
CREATE FUNCTION okeyix_ready_private.is_managed(uuid) RETURNS boolean LANGUAGE sql AS $$
 SELECT EXISTS(SELECT 1 FROM okeyix_ready_private.managed WHERE table_id=$1) $$;
CREATE FUNCTION okeyix_ready_private.is_public(jsonb) RETURNS boolean LANGUAGE sql AS $$
 SELECT okeyix_quick_private.is_public($1) $$;
CREATE FUNCTION public.pool_assert(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'ASSERT: %',label; END IF; END $$;
-- Production's existing delete-voice trigger uses an unqualified public table.
CREATE TABLE public.table_messages(table_id uuid REFERENCES public.tables ON DELETE CASCADE);
CREATE FUNCTION public.fixture_delete_voice() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN PERFORM count(*) FROM table_messages WHERE table_id=OLD.id; RETURN OLD; END $$;
CREATE TRIGGER fixture_delete_voice BEFORE DELETE ON public.tables
 FOR EACH ROW EXECUTE FUNCTION public.fixture_delete_voice();
INSERT INTO auth.users(id) SELECT md5('pool-human-'||n)::uuid FROM generate_series(1,3) n;
INSERT INTO public.users SELECT md5('pool-human-'||n)::uuid,false,'Pool human '||n,NULL FROM generate_series(1,3) n;
INSERT INTO public.profiles(id,username,coins,rating,is_online,last_seen_at)
 SELECT md5('pool-human-'||n)::uuid,'Pool human '||n,1000000,2500,true,now() FROM generate_series(1,3) n;

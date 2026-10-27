-- NOT APPLIED. Based on the supplied live table_chat_membership_schema.
-- No game functions, hands, balances or existing messages are rewritten.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $$ BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'POSTGRES_REQUIRED'; END IF;
  IF EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public'
    AND tablename='table_messages' AND policyname NOT IN
      ('okeyix_chat_read','okeyix_chat_send')) THEN
    RAISE EXCEPTION 'CHAT_POLICIES_CHANGED_REVIEW_REQUIRED';
  END IF;
END $$;

-- Lock memberships while installing and seeding access windows.
LOCK TABLE public.table_players,public.table_spectators IN SHARE ROW EXCLUSIVE MODE;
ALTER TABLE public.table_messages ADD COLUMN IF NOT EXISTS membership_event jsonb;
CREATE INDEX IF NOT EXISTS okeyix_chat_table_time
  ON public.table_messages(table_id,created_at);
CREATE SCHEMA IF NOT EXISTS okeyix_chat_private AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA okeyix_chat_private FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE IF NOT EXISTS okeyix_chat_private.memberships(
  role text NOT NULL CHECK(role IN ('player','spectator')),
  membership_id uuid NOT NULL,
  table_id uuid NOT NULL REFERENCES public.tables(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  since timestamptz NOT NULL,
  PRIMARY KEY(role,membership_id)
);
CREATE INDEX IF NOT EXISTS chat_memberships_viewer
  ON okeyix_chat_private.memberships(user_id,table_id,since);
ALTER TABLE okeyix_chat_private.memberships ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA okeyix_chat_private
  FROM PUBLIC,anon,authenticated,service_role;

-- Existing participants keep their recorded participation start. Installation
-- does not manufacture join events. New windows use the server clock below.
INSERT INTO okeyix_chat_private.memberships
SELECT 'player',id,table_id,user_id,least(coalesce(joined_at,clock_timestamp()),clock_timestamp())
FROM public.table_players WHERE table_id IS NOT NULL AND user_id IS NOT NULL
ON CONFLICT DO NOTHING;
INSERT INTO okeyix_chat_private.memberships
SELECT 'spectator',id,table_id,user_id,least(coalesce(joined_at,clock_timestamp()),clock_timestamp())
FROM public.table_spectators ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public.okeyix_chat_can_read(p_table uuid,p_at timestamptz)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT EXISTS(SELECT 1 FROM okeyix_chat_private.memberships m
    JOIN public.tables t ON t.id=m.table_id
    WHERE m.table_id=p_table AND m.user_id=auth.uid() AND p_at>=m.since
      AND ((m.role='player' AND EXISTS(SELECT 1 FROM public.table_players p
          WHERE p.id=m.membership_id AND p.table_id=m.table_id AND p.user_id=m.user_id))
        OR (m.role='spectator' AND t.spectators_enabled AND EXISTS(
          SELECT 1 FROM public.table_spectators s WHERE s.id=m.membership_id
            AND s.table_id=m.table_id AND s.user_id=m.user_id))));
$$;
CREATE OR REPLACE FUNCTION public.okeyix_chat_can_send(p_table uuid,p_role text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
  SELECT EXISTS(SELECT 1 FROM public.tables t WHERE t.id=p_table
    AND coalesce(t.chat_enabled,true) AND (
      (p_role='player' AND EXISTS(SELECT 1 FROM public.table_players p
        WHERE p.table_id=t.id AND p.user_id=auth.uid())) OR
      (p_role='spectator' AND t.spectators_enabled AND EXISTS(
        SELECT 1 FROM public.table_spectators s
        WHERE s.table_id=t.id AND s.user_id=auth.uid()))));
$$;
ALTER FUNCTION public.okeyix_chat_can_read(uuid,timestamptz) OWNER TO postgres;
ALTER FUNCTION public.okeyix_chat_can_send(uuid,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.okeyix_chat_can_read(uuid,timestamptz),
  public.okeyix_chat_can_send(uuid,text) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.okeyix_chat_can_read(uuid,timestamptz),
  public.okeyix_chat_can_send(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION okeyix_chat_private.stamp_message()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
  IF NEW.membership_event IS NOT NULL THEN
    -- Only a nested membership trigger may write system identity metadata.
    IF pg_trigger_depth()<2 THEN RAISE EXCEPTION 'CHAT_SYSTEM_EVENT_SERVER_ONLY'; END IF;
  ELSE
    NEW.created_at:=clock_timestamp();
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS okeyix_chat_stamp ON public.table_messages;
CREATE TRIGGER okeyix_chat_stamp BEFORE INSERT ON public.table_messages
  FOR EACH ROW EXECUTE FUNCTION okeyix_chat_private.stamp_message();

CREATE OR REPLACE FUNCTION okeyix_chat_private.membership_changed()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE item record; v_role text; v_action text; v_at timestamptz;
  v_name text; v_avatar text;
BEGIN
  v_role:=CASE WHEN TG_TABLE_NAME='table_players' THEN 'player' ELSE 'spectator' END;
  -- Hand, readiness and joined_at updates are deliberately not membership changes.
  IF TG_OP='UPDATE' THEN
    IF NEW.id=OLD.id AND NEW.table_id IS NOT DISTINCT FROM OLD.table_id
      AND NEW.user_id IS NOT DISTINCT FROM OLD.user_id THEN RETURN NEW; END IF;
  END IF;
  FOR item IN SELECT OLD.id AS id,OLD.table_id AS table_id,OLD.user_id AS user_id,
      'leave'::text AS action WHERE TG_OP IN ('DELETE','UPDATE')
    UNION ALL SELECT NEW.id,NEW.table_id,NEW.user_id,'join'::text
      WHERE TG_OP IN ('INSERT','UPDATE')
  LOOP
    v_at:=clock_timestamp(); v_action:=item.action;
    IF item.table_id IS NULL OR item.user_id IS NULL THEN CONTINUE; END IF;
    IF v_action='leave' THEN
      DELETE FROM okeyix_chat_private.memberships
        WHERE role=v_role AND membership_id=item.id;
    ELSE
      INSERT INTO okeyix_chat_private.memberships
        VALUES(v_role,item.id,item.table_id,item.user_id,v_at)
        ON CONFLICT(role,membership_id) DO UPDATE SET
          table_id=excluded.table_id,user_id=excluded.user_id,since=excluded.since;
    END IF;
    -- Cascading deletion of a table/account must not recreate dangling messages.
    IF NOT EXISTS(SELECT 1 FROM public.tables WHERE id=item.table_id) THEN CONTINUE; END IF;
    SELECT coalesce(nullif(u.username,''),'Oyuncu'),u.avatar_url INTO v_name,v_avatar
      FROM public.users u WHERE u.id=item.user_id;
    IF NOT FOUND THEN CONTINUE; END IF;
    INSERT INTO public.table_messages(table_id,sender_id,role,content,type,created_at,membership_event)
    VALUES(item.table_id,item.user_id,v_role,
      v_name||CASE WHEN v_role='spectator' THEN
        CASE WHEN v_action='join' THEN ' izlemeye başladı' ELSE ' izlemekten ayrıldı' END
      ELSE CASE WHEN v_action='join' THEN ' masaya katıldı' ELSE ' masadan ayrıldı' END END,
      'text',v_at,jsonb_build_object('action',v_action,'role',v_role,
        'username',v_name,'avatar_url',v_avatar));
  END LOOP;
  IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END $$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA okeyix_chat_private
  FROM PUBLIC,anon,authenticated,service_role;
DROP TRIGGER IF EXISTS okeyix_chat_membership ON public.table_players;
CREATE TRIGGER okeyix_chat_membership AFTER INSERT OR DELETE OR UPDATE OF id,table_id,user_id
  ON public.table_players FOR EACH ROW EXECUTE FUNCTION okeyix_chat_private.membership_changed();
DROP TRIGGER IF EXISTS okeyix_chat_membership ON public.table_spectators;
CREATE TRIGGER okeyix_chat_membership AFTER INSERT OR DELETE OR UPDATE OF id,table_id,user_id
  ON public.table_spectators FOR EACH ROW EXECUTE FUNCTION okeyix_chat_private.membership_changed();

ALTER TABLE public.table_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS okeyix_chat_read ON public.table_messages;
CREATE POLICY okeyix_chat_read ON public.table_messages FOR SELECT TO authenticated
  USING(public.okeyix_chat_can_read(table_id,created_at));
DROP POLICY IF EXISTS okeyix_chat_send ON public.table_messages;
CREATE POLICY okeyix_chat_send ON public.table_messages FOR INSERT TO authenticated
  WITH CHECK(sender_id=auth.uid() AND membership_event IS NULL
    AND public.okeyix_chat_can_send(table_id,role));
REVOKE ALL ON public.table_messages FROM PUBLIC,anon;
GRANT SELECT,INSERT ON public.table_messages TO authenticated;

-- Supplied publication has no row filter. If it has an explicit column list,
-- re-add just this table with all columns so metadata reaches Realtime too.
DO $$ DECLARE p record; BEGIN
  FOR p IN SELECT pub.pubname,pr.prattrs,pr.prqual FROM pg_publication_rel pr
    JOIN pg_publication pub ON pub.oid=pr.prpubid
    WHERE pr.prrelid='public.table_messages'::regclass
  LOOP
    IF p.prqual IS NOT NULL THEN RAISE EXCEPTION 'CHAT_PUBLICATION_FILTER_REVIEW_REQUIRED'; END IF;
    IF p.prattrs IS NOT NULL THEN
      EXECUTE format('ALTER PUBLICATION %I DROP TABLE public.table_messages',p.pubname);
      EXECUTE format('ALTER PUBLICATION %I ADD TABLE public.table_messages',p.pubname);
    END IF;
  END LOOP;
END $$;
NOTIFY pgrst,'reload schema';
COMMIT;

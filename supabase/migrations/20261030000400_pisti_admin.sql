-- NOT APPLIED. Admin website authenticates its existing session, then calls
-- this service-only RPC. No admin access to hidden hands/stock is provided.
BEGIN;
ALTER TABLE public.okeyix_pisti_invites ADD COLUMN push_claimed boolean NOT NULL DEFAULT false, ADD COLUMN push_outcome jsonb;
CREATE FUNCTION public.okeyix_pisti_claim_push(p_invite uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 UPDATE public.okeyix_pisti_invites SET push_claimed=true WHERE id=p_invite AND NOT push_claimed AND status='pending' AND expires_at>clock_timestamp();
 RETURN FOUND;
END $$;
REVOKE ALL ON FUNCTION public.okeyix_pisti_claim_push(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.okeyix_pisti_claim_push(uuid) TO service_role;
CREATE TABLE okeyix_pisti_private.worker_lease(id boolean PRIMARY KEY DEFAULT true CHECK(id),token uuid,expires_at timestamptz NOT NULL DEFAULT '-infinity');
INSERT INTO okeyix_pisti_private.worker_lease DEFAULT VALUES;
REVOKE ALL ON okeyix_pisti_private.worker_lease FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.okeyix_pisti_worker_lease(p_token uuid,p_release boolean DEFAULT false) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF p_release THEN UPDATE okeyix_pisti_private.worker_lease SET expires_at='-infinity' WHERE id AND token=p_token;
 ELSE UPDATE okeyix_pisti_private.worker_lease SET token=p_token,expires_at=clock_timestamp()+interval '30 seconds' WHERE id AND expires_at<clock_timestamp(); END IF;
 RETURN FOUND;
END $$;
REVOKE ALL ON FUNCTION public.okeyix_pisti_worker_lease(uuid,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.okeyix_pisti_worker_lease(uuid,boolean) TO service_role;
CREATE FUNCTION public.okeyix_pisti_player_allowed(p_user uuid) RETURNS boolean
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM public.users WHERE id=p_user AND NOT is_bot AND
 (NOT coalesce(is_banned,false) OR ban_until<=clock_timestamp()))
$$;
REVOKE ALL ON FUNCTION public.okeyix_pisti_player_allowed(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.okeyix_pisti_player_allowed(uuid) TO service_role;

-- Membership exclusion uses the existing Okey table and the existing bot lock
-- namespace. It has no effect when the user has no active Pişti session.
CREATE FUNCTION okeyix_pisti_private.prevent_double_seat() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM public.users WHERE id=NEW.user_id AND is_bot) THEN
  PERFORM pg_advisory_xact_lock(hashtextextended('quick-bot:'||NEW.user_id::text,0));
 ELSE PERFORM pg_advisory_xact_lock(hashtextextended('pisti-user:'||NEW.user_id::text,0)); END IF;
 IF EXISTS(SELECT 1 FROM public.okeyix_pisti_rooms r WHERE r.status IN ('waiting','playing')
  AND okeyix_pisti_private.member(r.seats,NEW.user_id) IS NOT NULL) THEN RAISE EXCEPTION 'ALREADY_SEATED_PISTI'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER pisti_membership_exclusion BEFORE INSERT ON public.table_players
 FOR EACH ROW EXECUTE FUNCTION okeyix_pisti_private.prevent_double_seat();
REVOKE ALL ON FUNCTION okeyix_pisti_private.prevent_double_seat() FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.okeyix_pisti_maintenance() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r record;
BEGIN
 FOR r IN SELECT x.*,s.last_seen,s.settings FROM public.okeyix_pisti_rooms x JOIN okeyix_pisti_private.sessions s ON s.room_id=x.id
  WHERE x.status='waiting' FOR UPDATE OF x SKIP LOCKED LOOP
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(r.seats) p WHERE NOT (p->>'bot')::boolean
    AND coalesce((r.last_seen->>(p->>'id'))::timestamptz,r.created_at)<clock_timestamp()-make_interval(secs=>(r.settings->>'disconnect_seconds')::integer)) THEN
   UPDATE public.okeyix_pisti_rooms SET status='closed',version=version+1,updated_at=clock_timestamp() WHERE id=r.id;
   UPDATE public.okeyix_pisti_invites SET status='rejected' WHERE table_id=r.id AND status='pending';
  END IF;
 END LOOP;
 UPDATE public.okeyix_pisti_invites SET status='rejected' WHERE status='pending' AND expires_at<=clock_timestamp();
 -- Preserve financial/match receipts permanently; prune harmless heartbeat-free
 -- command receipts only after sessions have been closed for thirty days.
 DELETE FROM okeyix_pisti_private.timeout_receipts t USING public.okeyix_pisti_rooms expired
  WHERE expired.id=t.room_id AND expired.status IN ('closed','finished') AND expired.updated_at<clock_timestamp()-interval '30 days';
END $$;
REVOKE ALL ON FUNCTION public.okeyix_pisti_maintenance() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.okeyix_pisti_maintenance() TO service_role;
CREATE FUNCTION public.okeyix_pisti_admin(p_admin text,p_action text,p_room uuid DEFAULT NULL,p_settings jsonb DEFAULT '{}') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r public.okeyix_pisti_rooms%ROWTYPE; s jsonb;
BEGIN
 IF p_admin IS NULL OR length(p_admin)=0 THEN RAISE EXCEPTION 'ADMIN_REQUIRED'; END IF;
 IF p_action='close' THEN
  SELECT * INTO r FROM public.okeyix_pisti_rooms WHERE id=p_room FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'TABLE_NOT_FOUND'; END IF;
  IF r.status='playing' THEN
   SELECT state INTO s FROM okeyix_pisti_private.sessions WHERE room_id=r.id;
   s:=s||jsonb_build_object('status','finished','reason','admin_cancel','winner',NULL);
   PERFORM okeyix_pisti_private.settle(r,s);
   UPDATE okeyix_pisti_private.sessions SET state=s WHERE room_id=r.id;
  END IF;
  UPDATE public.okeyix_pisti_rooms SET status='closed',version=version+1,deadline=NULL,updated_at=clock_timestamp(),
   summary=CASE WHEN s IS NOT NULL THEN jsonb_build_object('reason','admin_cancel','total',s->'total') ELSE summary END WHERE id=r.id;
 ELSIF p_action='settings' THEN
  IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_settings) k WHERE k NOT IN ('enabled','stakes','target','turn_seconds','disconnect_seconds','timeout_limit')) THEN RAISE EXCEPTION 'INVALID_SETTINGS'; END IF;
  IF p_settings?'stakes' AND (jsonb_typeof(p_settings->'stakes')<>'array' OR jsonb_array_length(p_settings->'stakes') NOT BETWEEN 1 AND 10
   OR EXISTS(SELECT 1 FROM jsonb_array_elements_text(p_settings->'stakes') v WHERE v::integer NOT BETWEEN 1 AND 100000000)) THEN RAISE EXCEPTION 'INVALID_STAKES'; END IF;
  UPDATE public.okeyix_pisti_settings SET enabled=coalesce((p_settings->>'enabled')::boolean,enabled),
   stakes=CASE WHEN p_settings?'stakes' THEN ARRAY(SELECT value::integer FROM jsonb_array_elements_text(p_settings->'stakes')) ELSE stakes END,
   target=coalesce((p_settings->>'target')::integer,target),turn_seconds=coalesce((p_settings->>'turn_seconds')::integer,turn_seconds),
   disconnect_seconds=coalesce((p_settings->>'disconnect_seconds')::integer,disconnect_seconds),timeout_limit=coalesce((p_settings->>'timeout_limit')::integer,timeout_limit) WHERE id;
 ELSE RAISE EXCEPTION 'UNKNOWN_ACTION'; END IF;
 INSERT INTO public.okeyix_pisti_admin_audit(admin_id,action,room_id,details) VALUES(p_admin,p_action,p_room,p_settings);
 RETURN jsonb_build_object('ok',true);
END $$;
REVOKE ALL ON FUNCTION public.okeyix_pisti_admin(text,text,uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.okeyix_pisti_admin(text,text,uuid,jsonb) TO service_role;
NOTIFY pgrst,'reload schema';
COMMIT;

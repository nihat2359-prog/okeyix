-- NOT APPLIED. Apply after pisti.sql. Worker is scheduled disabled.
BEGIN;
CREATE FUNCTION public.okeyix_pisti_receipt(p_user uuid,p_request uuid) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
 SELECT to_jsonb(r) FROM okeyix_pisti_private.requests r WHERE user_id=p_user AND request_id=p_request
$$;
CREATE TABLE okeyix_pisti_private.timeout_receipts (
 room_id uuid NOT NULL, version bigint NOT NULL, count integer NOT NULL, PRIMARY KEY(room_id,version)
);
CREATE FUNCTION public.okeyix_pisti_timeout(p_room uuid,p_version bigint,p_seat integer) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE n integer;
BEGIN
 PERFORM 1 FROM public.okeyix_pisti_rooms WHERE id=p_room AND version=p_version AND status='playing' FOR UPDATE;
 IF NOT FOUND THEN RETURN NULL; END IF;
 SELECT count INTO n FROM okeyix_pisti_private.timeout_receipts WHERE room_id=p_room AND version=p_version;
 IF FOUND THEN RETURN n; END IF;
 UPDATE okeyix_pisti_private.sessions SET timeouts[p_seat+1]=timeouts[p_seat+1]+1 WHERE room_id=p_room RETURNING timeouts[p_seat+1] INTO n;
 INSERT INTO okeyix_pisti_private.timeout_receipts VALUES(p_room,p_version,n);
 RETURN n;
END $$;
CREATE FUNCTION public.okeyix_pisti_social(p_user uuid,p_request uuid,p_room uuid,p_kind text,p_body text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE r public.okeyix_pisti_rooms%ROWTYPE; name text; old record; price integer; recipient uuid;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('pisti-user:'||p_user::text,0));
 SELECT * INTO old FROM public.okeyix_pisti_messages WHERE id=p_request;
 IF FOUND THEN
  IF old.user_id<>p_user OR old.table_id<>p_room OR old.kind<>p_kind OR old.body<>p_body THEN RAISE EXCEPTION 'REQUEST_CONFLICT'; END IF;
  RETURN jsonb_build_object('id',p_request);
 END IF;
 SELECT * INTO r FROM public.okeyix_pisti_rooms WHERE id=p_room FOR UPDATE;
 IF r.status NOT IN ('waiting','playing') OR (okeyix_pisti_private.member(r.seats,p_user) IS NULL
  AND (p_kind<>'text' OR NOT public.okeyix_pisti_view_allowed(p_room,p_user))) THEN RAISE EXCEPTION 'NOT_A_MEMBER'; END IF;
 IF NOT r.chat_enabled AND p_kind IN ('text','voice') THEN RAISE EXCEPTION 'CHAT_DISABLED'; END IF;
 IF EXISTS(SELECT 1 FROM public.okeyix_pisti_messages WHERE user_id=p_user AND created_at>clock_timestamp()-interval '1 second') THEN RAISE EXCEPTION 'RATE_LIMITED'; END IF;
 IF p_body IS NULL OR length(trim(p_body))=0 OR length(p_body)>1000 THEN RAISE EXCEPTION 'INVALID_MESSAGE'; END IF;
 IF p_kind='gift' THEN
  IF r.status<>'playing' THEN RAISE EXCEPTION 'GIFT_NOT_AVAILABLE'; END IF;
  SELECT g.price INTO price FROM public.okeyix_gift_catalog g WHERE id=p_body AND enabled;
  IF price IS NULL THEN RAISE EXCEPTION 'GIFT_NOT_AVAILABLE'; END IF;
  recipient:=(r.seats->(1-okeyix_pisti_private.member(r.seats,p_user))->>'id')::uuid;
  PERFORM okeyix_pisti_private.wallet(p_request,p_user,'gift',-price);
 ELSIF p_kind='voice' THEN
  IF p_body<>p_user::text||'/'||p_request::text||'.wav' THEN RAISE EXCEPTION 'VOICE_INVALID'; END IF;
  IF NOT EXISTS(SELECT 1 FROM storage.objects obj WHERE obj.bucket_id='pisti-voice' AND obj.name=p_body) THEN RAISE EXCEPTION 'VOICE_INVALID'; END IF;
 ELSIF p_kind<>'text' THEN RAISE EXCEPTION 'INVALID_MESSAGE'; END IF;
 SELECT username INTO name FROM public.users WHERE id=p_user;
 IF okeyix_pisti_private.member(r.seats,p_user) IS NULL THEN name:='Seyirci · '||coalesce(name,'Oyuncu'); END IF;
 INSERT INTO public.okeyix_pisti_messages VALUES(p_request,p_room,p_user,coalesce(name,'Oyuncu'),p_kind,p_body,clock_timestamp());
 RETURN jsonb_build_object('id',p_request,'recipient_id',recipient);
END $$;
REVOKE ALL ON FUNCTION public.okeyix_pisti_receipt(uuid,uuid),public.okeyix_pisti_timeout(uuid,bigint,integer),
 public.okeyix_pisti_social(uuid,uuid,uuid,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.okeyix_pisti_receipt(uuid,uuid),public.okeyix_pisti_timeout(uuid,bigint,integer),
 public.okeyix_pisti_social(uuid,uuid,uuid,text,text) TO service_role;

-- Voice uses a private bucket. A path alone gives no access to another room.
INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 VALUES('pisti-voice','pisti-voice',false,1048576,ARRAY['audio/wav']) ON CONFLICT DO NOTHING;
CREATE POLICY pisti_voice_upload ON storage.objects FOR INSERT TO authenticated WITH CHECK(
 bucket_id='pisti-voice' AND (storage.foldername(name))[1]=auth.uid()::text
 AND EXISTS(SELECT 1 FROM public.okeyix_pisti_rooms r WHERE r.status IN ('waiting','playing') AND r.chat_enabled
 AND okeyix_pisti_private.member(r.seats,auth.uid()) IS NOT NULL));
CREATE POLICY pisti_voice_read ON storage.objects FOR SELECT TO authenticated USING(
 bucket_id='pisti-voice' AND EXISTS(SELECT 1 FROM public.okeyix_pisti_messages m
 WHERE m.kind='voice' AND m.body=name AND public.okeyix_pisti_can_view(m.table_id)));
CREATE POLICY pisti_voice_delete ON storage.objects FOR DELETE TO authenticated USING(
 bucket_id='pisti-voice' AND (storage.foldername(name))[1]=auth.uid()::text);

CREATE FUNCTION okeyix_pisti_private.invoke_worker() RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE endpoint text; secret text; request bigint;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.okeyix_pisti_rooms WHERE status IN ('waiting','playing')) THEN RETURN NULL; END IF;
 SELECT decrypted_secret INTO STRICT endpoint FROM vault.decrypted_secrets WHERE name='okeyix_pisti_project_url';
 SELECT decrypted_secret INTO STRICT secret FROM vault.decrypted_secrets WHERE name='okeyix_pisti_worker_secret';
 IF endpoint !~ '^https://[a-z0-9-]+\.supabase\.co$' OR length(secret)<32 THEN RAISE EXCEPTION 'PISTI_WORKER_CONFIG'; END IF;
 SELECT net.http_post(url:=endpoint||'/functions/v1/pisti',headers:=jsonb_build_object('Content-Type','application/json','x-pisti-worker',secret),
  body:='{"action":"tick"}'::jsonb,timeout_milliseconds:=5000) INTO request;
 RETURN request;
END $$;
REVOKE ALL ON FUNCTION okeyix_pisti_private.invoke_worker() FROM PUBLIC,anon,authenticated,service_role;
-- Supabase pg_cron supports seconds schedules. Validate extension version in staging.
SELECT cron.schedule('okeyix-pisti-tick','1 second','SELECT okeyix_pisti_private.invoke_worker();');
SELECT cron.alter_job(jobid,active:=false) FROM cron.job WHERE jobname='okeyix-pisti-tick';
NOTIFY pgrst,'reload schema';
COMMIT;

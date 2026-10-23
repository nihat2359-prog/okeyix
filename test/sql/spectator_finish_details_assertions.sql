-- LOCAL TEST ONLY. Event-first, processed-round fallback and access control.
DO $$
DECLARE t uuid:='10000000-0000-0000-0000-000000000001';
  u uuid:='20000000-0000-0000-0000-000000000001';
  w uuid:='30000000-0000-0000-0000-000000000001'; result jsonb;
BEGIN
  INSERT INTO public.tables(id,status) VALUES(t,'playing');
  INSERT INTO public.table_spectators VALUES(t,u);
  INSERT INTO public.users(id,username) VALUES(w,'Kazanan');
  INSERT INTO public.okeyix_stat_sessions VALUES(t,t);
  INSERT INTO public.okeyix_stat_rounds VALUES(t,w,now()-interval '1 minute',false,false,'completed');
  INSERT INTO okeyix_stat_private.events VALUES(1,t,w,now(),true,true,'complete');
  PERFORM set_config('request.jwt.claim.sub',u::text,true);
  result:=public.okeyix_spectator_last_finish(t);
  IF result->>'username'<>'Kazanan' OR result->>'is_okey_finish'<>'true'
    OR result->>'is_double_finish'<>'true' THEN RAISE EXCEPTION 'LATEST_EVENT_NOT_USED'; END IF;
  DELETE FROM okeyix_stat_private.events;
  result:=public.okeyix_spectator_last_finish(t);
  IF result->>'is_okey_finish'<>'false' OR result->>'is_double_finish'<>'false'
    THEN RAISE EXCEPTION 'PROCESSED_FALLBACK_FAILED'; END IF;
  PERFORM set_config('request.jwt.claim.sub',w::text,true);
  BEGIN
    PERFORM public.okeyix_spectator_last_finish(t);
    RAISE EXCEPTION 'OUTSIDER_ACCEPTED';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claim.sub','',true);
  BEGIN
    PERFORM public.okeyix_spectator_last_finish(t);
    RAISE EXCEPTION 'ANONYMOUS_ACCEPTED';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
SELECT 'Latest event, processed fallback and access controls passed' AS result;

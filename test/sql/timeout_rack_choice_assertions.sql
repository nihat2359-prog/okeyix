-- LOCAL DATABASE ONLY. Exercises the supplied timeout function after patching.
DO $$
DECLARE t uuid:='10000000-0000-0000-0000-000000000001';
  u uuid:='20000000-0000-0000-0000-000000000001'; h jsonb; r jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',u::text,true);
  SELECT jsonb_agg(jsonb_build_object('id','tile-'||n,'color','red','value',n))
    INTO h FROM generate_series(1,13) n;
  h:=h||'[{"id":"single","color":"blue","value":7},{"id":"other","color":"black","value":8}]';
  INSERT INTO public.tables VALUES(t,'playing',0,2,
    '[{"id":"indicator"},{"id":"drawn","color":"red","value":13}]',
    20,now()-interval '30 seconds',null);
  INSERT INTO public.table_players VALUES(u,t,u,0,h,0,false);
  r:=public.okeyix_timeout_move_with_tile(t,u,'single');
  IF r->'tile'->>'id'<>'single' THEN RAISE EXCEPTION 'RACK_PREFERENCE_IGNORED'; END IF;
  IF (SELECT consecutive_timeouts FROM public.table_players WHERE id=u)<>1
    THEN RAISE EXCEPTION 'TIMEOUT_COUNTER_CHANGED'; END IF;
  IF coalesce(current_setting('okeyix.timeout_tile_id',true),'')<>''
    THEN RAISE EXCEPTION 'PREFERENCE_LEAK'; END IF;

  UPDATE public.table_players SET hand=h-14,consecutive_timeouts=0 WHERE id=u;
  r:=public.okeyix_timeout_move_with_tile(t,u,'single');
  IF r->'tile'->>'id'<>'drawn' THEN RAISE EXCEPTION 'DRAWN_TILE_NOT_DISCARDED'; END IF;

  UPDATE public.table_players SET hand=h,consecutive_timeouts=0 WHERE id=u;
  r:=public.okeyix_timeout_move_with_tile(t,u,'not-in-hand');
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(h) x WHERE x=r->'tile')
    THEN RAISE EXCEPTION 'INVALID_PREFERENCE_ACCEPTED'; END IF;

  UPDATE public.table_players SET hand=h,consecutive_timeouts=0 WHERE id=u;
  UPDATE public.tables SET turn_started_at=now() WHERE id=t;
  BEGIN
    PERFORM public.okeyix_timeout_move_with_tile(t,u,'single');
    RAISE EXCEPTION 'EARLY_TIMEOUT_ACCEPTED';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'TURN_NOT_EXPIRED' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.okeyix_timeout_move_with_tile(t,'30000000-0000-0000-0000-000000000001','single');
    RAISE EXCEPTION 'OTHER_HAND_ACCEPTED';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
SELECT 'Rack preference, drawn tile, fallback, expiry and caller checks passed' AS result;

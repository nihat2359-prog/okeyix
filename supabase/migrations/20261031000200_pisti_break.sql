-- Pişti Molası: new sessions are private and free. Existing sessions/history stay intact.
BEGIN;
SET LOCAL lock_timeout='5s';
ALTER TABLE public.okeyix_pisti_rooms ADD COLUMN casual boolean NOT NULL DEFAULT false;
ALTER TABLE public.okeyix_pisti_rooms ADD COLUMN break_kind text CHECK(break_kind IN ('bot','friend'));
ALTER TABLE public.okeyix_pisti_rooms DROP CONSTRAINT okeyix_pisti_rooms_entry_coin_check;
ALTER TABLE public.okeyix_pisti_rooms ADD CONSTRAINT okeyix_pisti_rooms_entry_coin_check
 CHECK((casual AND entry_coin=0 AND private AND NOT spectators_enabled AND break_kind IS NOT NULL)
 OR (NOT casual AND entry_coin>0 AND entry_coin<=100000000));

CREATE FUNCTION pg_temp.break_replace(source text,needle text,replacement text) RETURNS text
LANGUAGE plpgsql AS $$ BEGIN
 IF position(needle IN source)=0 THEN RAISE EXCEPTION 'PISTI_BREAK_DEFINITION_MISMATCH: %',left(needle,80); END IF;
 RETURN replace(source,needle,replacement);
END $$;
DO $$
DECLARE d text;
BEGIN
 d:=pg_get_functiondef('okeyix_pisti_private.wallet(uuid,uuid,text,integer)'::regprocedure);
 d:=pg_temp.break_replace(d,'BEGIN',E'BEGIN\n IF amount=0 THEN RETURN; END IF;');
 EXECUTE d;
 d:=pg_get_functiondef('okeyix_pisti_private.settle(public.okeyix_pisti_rooms,jsonb)'::regprocedure);
 d:=pg_temp.break_replace(d,'IF n=0 THEN RETURN; END IF;','IF n=0 OR r.casual THEN RETURN; END IF;');
 EXECUTE d;
 d:=pg_get_functiondef('public.okeyix_pisti_commit(uuid,bigint,jsonb,uuid,uuid,integer,boolean)'::regprocedure);
 d:=pg_temp.break_replace(d,'SET paid=true, timeouts=','SET paid=NOT r.casual, timeouts=');
 EXECUTE d;
 d:=pg_get_functiondef('public.okeyix_pisti_command(uuid,uuid,text,jsonb)'::regprocedure);
 d:=pg_temp.break_replace(d,
  'IF NOT coalesce((p_args->>''entry_coin'')::integer,cfg.stakes[1])=ANY(cfg.stakes) THEN RAISE EXCEPTION ''INVALID_STAKES''; END IF;',
  'IF p_args ? ''entry_coin'' AND (p_args->>''entry_coin'')::integer<0 THEN RAISE EXCEPTION ''INVALID_STAKES''; END IF;');
 d:=pg_temp.break_replace(d,'(owner_id,private,entry_coin,spectators_enabled,chat_enabled)',
  '(owner_id,private,entry_coin,spectators_enabled,chat_enabled,casual,break_kind)');
 d:=pg_temp.break_replace(d,
  E'VALUES(p_user,coalesce((p_args->>''private'')::boolean,false),coalesce((p_args->>''entry_coin'')::integer,cfg.stakes[1]),\n      coalesce((p_args->>''spectators_enabled'')::boolean,true),coalesce((p_args->>''chat_enabled'')::boolean,true))',
  'VALUES(p_user,true,0,false,coalesce((p_args->>''chat_enabled'')::boolean,true),true,CASE WHEN p_args->>''mode''=''break_bot'' THEN ''bot'' ELSE ''friend'' END)');
 d:=pg_temp.break_replace(d,'ELSIF p_action=''bot'' THEN',
  E'ELSIF p_action=''bot'' THEN\n    IF r.casual AND r.break_kind=''friend'' THEN RAISE EXCEPTION ''FRIEND_REQUIRED''; END IF;');
 d:=pg_temp.break_replace(d,'IF p_action<>''heartbeat'' THEN INSERT INTO okeyix_pisti_private.requests',
  E'IF p_action=''create'' AND r.casual AND r.break_kind=''bot''\n  AND (SELECT jsonb_array_length(seats)=1 FROM public.okeyix_pisti_rooms WHERE id=r.id) THEN\n  PERFORM public.okeyix_pisti_command(p_user,gen_random_uuid(),''bot'',jsonb_build_object(''room_id'',r.id));\n END IF;\n IF p_action<>''heartbeat'' THEN INSERT INTO okeyix_pisti_private.requests');
 EXECUTE d;
 d:=pg_get_functiondef('public.okeyix_pisti_invitable_players(uuid)'::regprocedure);
 d:=pg_temp.break_replace(d,'WHERE u.id<>uid AND p.coins>=r.entry_coin',
  'WHERE u.id<>uid AND p.coins>=r.entry_coin AND (NOT r.casual OR (r.break_kind=''bot'' AND u.is_bot) OR (r.break_kind=''friend'' AND NOT u.is_bot))');
 EXECUTE d;
END $$;
NOTIFY pgrst,'reload schema';
COMMIT;

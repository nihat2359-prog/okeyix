BEGIN;
CREATE FUNCTION pg_temp.check_break(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAILED: %',label; END IF; END $$;
DO $$
DECLARE a uuid:='00000000-0000-0000-0000-000000000001'; b uuid:='00000000-0000-0000-0000-000000000002';
 outsider uuid:='00000000-0000-0000-0000-000000000003'; room uuid; req uuid:=gen_random_uuid();
 v bigint; result jsonb; inv uuid; state jsonb:='{"status":"playing","turn":0,"total":[0,0],"pistiTotal":[0,0],"rounds":[]}';
BEGIN
 UPDATE public.okeyix_pisti_settings SET enabled=true;
 UPDATE public.profiles SET coins=0;
 result:=public.okeyix_pisti_command(a,req,'create','{"mode":"break_bot","entry_coin":10000,"private":false}');
 room:=(result->>'room_id')::uuid;
 PERFORM pg_temp.check_break(public.okeyix_pisti_command(a,req,'create','{"mode":"break_bot","entry_coin":10000,"private":false}')=result,'retry same room');
 PERFORM pg_temp.check_break((SELECT casual AND private AND NOT spectators_enabled AND entry_coin=0 AND break_kind='bot' AND jsonb_array_length(seats)=2 AND (seats->1->>'bot')::boolean FROM public.okeyix_pisti_rooms WHERE id=room),'automatic bot, forced free/private');
 PERFORM public.okeyix_pisti_command(a,gen_random_uuid(),'ready',jsonb_build_object('room_id',room));
 SELECT version INTO v FROM public.okeyix_pisti_rooms WHERE id=room;
 PERFORM pg_temp.check_break(public.okeyix_pisti_commit(room,v,state,NULL,NULL,NULL,true),'start with zero balance');
 PERFORM pg_temp.check_break((SELECT NOT paid FROM okeyix_pisti_private.sessions WHERE room_id=room),'not a paid session');
 SELECT version INTO v FROM public.okeyix_pisti_rooms WHERE id=room;
 PERFORM public.okeyix_pisti_commit(room,v,state||'{"status":"finished","winner":0,"reason":"normal","total":[101,82],"pistiTotal":[2,1]}',NULL,NULL);
 PERFORM pg_temp.check_break((SELECT scores='[101,82]'::jsonb AND entry_coin=0 FROM public.okeyix_pisti_results WHERE room_id=room),'scores retained');
 PERFORM public.okeyix_pisti_command(a,gen_random_uuid(),'rematch',jsonb_build_object('room_id',room));
 SELECT version INTO v FROM public.okeyix_pisti_rooms WHERE id=room;
 PERFORM pg_temp.check_break(public.okeyix_pisti_commit(room,v,state,NULL,NULL,NULL,true),'free bot rematch');
 PERFORM public.okeyix_pisti_admin('local-test','close',room);
 room:=(public.okeyix_pisti_command(a,gen_random_uuid(),'create','{"mode":"break_friend"}')->>'room_id')::uuid;
 PERFORM set_config('request.jwt.claim.sub',a::text,true);
 result:=public.okeyix_pisti_invitable_players(room);
 PERFORM pg_temp.check_break(result @> jsonb_build_array(jsonb_build_object('id',b)) AND NOT result @> jsonb_build_array(jsonb_build_object('id',outsider)) AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(result) x WHERE (x->>'is_bot')::boolean),'only existing human friends');
 BEGIN
  PERFORM public.okeyix_pisti_command(a,gen_random_uuid(),'bot',jsonb_build_object('room_id',room));
  RAISE EXCEPTION 'bot accepted in friend mode';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'FRIEND_REQUIRED' THEN RAISE; END IF; END;
 result:=public.okeyix_pisti_command(a,gen_random_uuid(),'invite',jsonb_build_object('room_id',room,'to_user',b));
 inv:=(result->>'invite_id')::uuid;
 PERFORM public.okeyix_pisti_command(b,gen_random_uuid(),'accept',jsonb_build_object('invite_id',inv));
 PERFORM public.okeyix_pisti_command(a,gen_random_uuid(),'ready',jsonb_build_object('room_id',room));
 PERFORM public.okeyix_pisti_command(b,gen_random_uuid(),'ready',jsonb_build_object('room_id',room));
 SELECT version INTO v FROM public.okeyix_pisti_rooms WHERE id=room;
 PERFORM pg_temp.check_break(public.okeyix_pisti_commit(room,v,state,NULL,NULL,NULL,true),'friend start');
 SELECT version INTO v FROM public.okeyix_pisti_rooms WHERE id=room;
 PERFORM public.okeyix_pisti_commit(room,v,state||'{"status":"finished","winner":1,"reason":"forfeit","total":[0,0]}',NULL,NULL);
 PERFORM public.okeyix_pisti_command(a,gen_random_uuid(),'rematch',jsonb_build_object('room_id',room));
 PERFORM pg_temp.check_break((SELECT status='finished' FROM public.okeyix_pisti_rooms WHERE id=room),'friend rematch needs both');
 PERFORM public.okeyix_pisti_command(b,gen_random_uuid(),'rematch',jsonb_build_object('room_id',room));
 PERFORM pg_temp.check_break((SELECT status='waiting' AND casual AND entry_coin=0 FROM public.okeyix_pisti_rooms WHERE id=room),'friend rematch free');
 PERFORM pg_temp.check_break(NOT EXISTS(SELECT 1 FROM public.wallet_transactions) AND NOT EXISTS(SELECT 1 FROM okeyix_pisti_private.ledger),'no entries, prizes or refunds');
 PERFORM pg_temp.check_break(NOT EXISTS(SELECT 1 FROM public.okeyix_pisti_careers) AND NOT EXISTS(SELECT 1 FROM public.profiles WHERE coins<>0 OR rating<>1000),'no coins or rating changes');
 PERFORM pg_temp.check_break(NOT has_function_privilege('anon','public.okeyix_pisti_command(uuid,uuid,text,jsonb)','execute'),'RPC still service-only');
END $$;
SELECT 'PASS: free bot/friend, retry, privacy, scores, rematch, cancel/forfeit, zero ledger/rating';
DO $$
DECLARE a uuid:='00000000-0000-0000-0000-000000000004'; b uuid:='00000000-0000-0000-0000-000000000005';
 room uuid; v bigint; state jsonb:='{"status":"playing","turn":0,"total":[0,0],"pistiTotal":[0,0],"rounds":[]}';
BEGIN
 UPDATE public.profiles SET coins=10000 WHERE id IN(a,b);
 INSERT INTO public.okeyix_pisti_rooms(owner_id,entry_coin,private,seats)
 VALUES(a,1000,true,jsonb_build_array(jsonb_build_object('id',a,'ready',true,'bot',false),jsonb_build_object('id',b,'ready',true,'bot',false))) RETURNING id,version INTO room,v;
 INSERT INTO okeyix_pisti_private.sessions(room_id,settings) SELECT room,to_jsonb(s) FROM public.okeyix_pisti_settings s;
 PERFORM pg_temp.check_break(public.okeyix_pisti_commit(room,v,state,NULL,NULL,NULL,true),'legacy paid start');
 SELECT version INTO v FROM public.okeyix_pisti_rooms WHERE id=room;
 PERFORM public.okeyix_pisti_commit(room,v,state||'{"status":"finished","winner":0,"reason":"normal","total":[101,82]}',NULL,NULL);
 PERFORM pg_temp.check_break((SELECT coins=11000 FROM public.profiles WHERE id=a) AND (SELECT coins=9000 FROM public.profiles WHERE id=b),'legacy paid contracts unchanged');
 PERFORM pg_temp.check_break((SELECT count(*)=3 FROM public.wallet_transactions),'legacy ledger retained');
END $$;
SELECT 'PASS: existing paid-room contract retained';
ROLLBACK;

BEGIN;
DO $$
DECLARE a uuid:='00000000-0000-0000-0000-000000000001'; b uuid:='00000000-0000-0000-0000-000000000003';
 bot uuid:='00000000-0000-0000-0000-000000000090'; room uuid; rows jsonb; rejected boolean;
BEGIN
 UPDATE public.okeyix_pisti_settings SET enabled=true;
 room:=(public.okeyix_pisti_command(a,gen_random_uuid(),'create','{}')->>'room_id')::uuid;
 PERFORM set_config('request.jwt.claim.sub',a::text,true);
 rows:=public.okeyix_pisti_invitable_players(room);
 IF NOT rows @> jsonb_build_array(jsonb_build_object('id',bot,'is_bot',true)) OR
    NOT rows @> jsonb_build_array(jsonb_build_object('id',b,'is_bot',false)) THEN RAISE EXCEPTION 'public invite list'; END IF;
 PERFORM public.okeyix_pisti_command(a,gen_random_uuid(),'invite',jsonb_build_object('room_id',room,'to_user',b));
 rejected:=false;
 BEGIN PERFORM public.okeyix_pisti_command(a,gen_random_uuid(),'bot',jsonb_build_object('room_id',room,'bot_id',b));
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE '%NO_BOT_AVAILABLE%' THEN RAISE; END IF; rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'invalid selected bot accepted'; END IF;
 PERFORM public.okeyix_pisti_command(a,gen_random_uuid(),'bot',jsonb_build_object('room_id',room,'bot_id',bot));
 IF NOT EXISTS(SELECT 1 FROM public.okeyix_pisti_rooms WHERE id=room AND seats @> jsonb_build_array(jsonb_build_object('id',bot))) THEN RAISE EXCEPTION 'selected bot missing'; END IF;
 PERFORM public.okeyix_pisti_command(a,gen_random_uuid(),'leave',jsonb_build_object('room_id',room));
 room:=(public.okeyix_pisti_command(a,gen_random_uuid(),'create','{"private":true}')->>'room_id')::uuid;
 rows:=public.okeyix_pisti_invitable_players(room);
 IF rows @> jsonb_build_array(jsonb_build_object('id',b)) THEN RAISE EXCEPTION 'private non-friend leaked'; END IF;
 rejected:=false;
 BEGIN PERFORM public.okeyix_pisti_command(a,gen_random_uuid(),'invite',jsonb_build_object('room_id',room,'to_user',b));
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE '%FRIEND_REQUIRED%' THEN RAISE; END IF; rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'private non-friend accepted'; END IF;
 PERFORM set_config('request.jwt.claim.sub',b::text,true);
 rejected:=false;
 BEGIN PERFORM public.okeyix_pisti_invitable_players(room);
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE '%NOT_A_MEMBER%' THEN RAISE; END IF; rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'invite list exposed to non-member'; END IF;
 IF EXISTS(SELECT 1 FROM public.wallet_transactions) THEN RAISE EXCEPTION 'waiting room charged'; END IF;
 IF has_function_privilege('anon','public.okeyix_pisti_invitable_players(uuid)','execute') THEN RAISE EXCEPTION 'anonymous list access'; END IF;
END $$;
SELECT 'PASS: selected bot, public invite, private friendship, membership, no waiting-room charge';
ROLLBACK;

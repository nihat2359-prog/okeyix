\set ON_ERROR_STOP on
BEGIN;
DO $$ DECLARE a jsonb; b jsonb; tid uuid; BEGIN
 -- Cross-league scan: ignore selected elite tab; join an affordable standard table.
 INSERT INTO public.tables(league_id,max_players,entry_coin,status,created_by)
 VALUES('standard',2,1000,'waiting','00000000-0000-0000-0000-000000000001') RETURNING id INTO tid;
 INSERT INTO public.table_players(table_id,user_id,seat_index,hand)
 VALUES(tid,'00000000-0000-0000-0000-000000000001',0,'[]');
 PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
 a:=public.okeyix_quick_play('10000000-0000-0000-0000-000000000002','elite','start');
 IF a->>'state'<>'ready' OR (a->>'table_id')::uuid<>tid OR (a->>'bot')::boolean THEN RAISE EXCEPTION 'CROSS_LEAGUE_JOIN_FAILED'; END IF;
 b:=public.okeyix_quick_play('10000000-0000-0000-0000-000000000002',NULL,'start');
 IF a->>'table_id'<>b->>'table_id' OR (SELECT count(*) FROM public.tables)<>1 THEN RAISE EXCEPTION 'IDEMPOTENCY_FAILED'; END IF;
 b:=public.okeyix_quick_play('10000000-0000-0000-0000-000000000002',NULL,'cancel');
 IF b->>'state'<>'ready' OR (SELECT count(*) FROM public.table_players WHERE table_id=tid)<>2 THEN RAISE EXCEPTION 'CANCEL_MATCH_RACE_FAILED'; END IF;
 IF EXISTS(SELECT 1 FROM public.profiles WHERE coins<>20000000) THEN RAISE EXCEPTION 'UNEXPECTED_DEBIT'; END IF;
END $$;
ROLLBACK;

BEGIN;
DO $$ DECLARE a jsonb; tid uuid; BEGIN
 -- Higher eligible league is searched too, even if standard is the selected tab.
 INSERT INTO public.tables(league_id,max_players,entry_coin,status,created_by)
 VALUES('elite',2,3000000,'waiting','00000000-0000-0000-0000-000000000001') RETURNING id INTO tid;
 INSERT INTO public.table_players(table_id,user_id,seat_index,hand)
 VALUES(tid,'00000000-0000-0000-0000-000000000001',0,'[]');
 PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',true);
 UPDATE public.profiles SET rating=200 WHERE id IN(auth.uid(),'00000000-0000-0000-0000-000000000001');
 a:=public.okeyix_quick_play('20000000-0000-0000-0000-000000000003','standard','start');
 IF (a->>'table_id')::uuid<>tid OR (a->>'bot')::boolean THEN RAISE EXCEPTION 'HIGHER_LEAGUE_SKIPPED'; END IF;
END $$;
ROLLBACK;

BEGIN;
DO $$ DECLARE a jsonb; tid uuid; BEGIN
 -- No open human table: instantly seat a bot in the actual player league.
 PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000004',true);
 UPDATE public.profiles SET rating=200 WHERE id=auth.uid();
 a:=public.okeyix_quick_play('30000000-0000-0000-0000-000000000004','standard','start');
 tid:=(a->>'table_id')::uuid;
 IF a->>'state'<>'ready' OR NOT (a->>'bot')::boolean OR a->>'league_id'<>'elite'
   OR (a->>'entry')::integer<>3000000 THEN RAISE EXCEPTION 'INSTANT_CURRENT_LEAGUE_BOT_FAILED'; END IF;
 IF (SELECT count(*) FROM public.table_players WHERE table_id=tid)<>2 THEN RAISE EXCEPTION 'EMPTY_BOT_TABLE'; END IF;
 IF EXISTS(SELECT 1 FROM public.tables WHERE status='waiting') THEN RAISE EXCEPTION 'HUMAN_WAIT_TABLE_CREATED'; END IF;
END $$;
ROLLBACK;

BEGIN;
DO $$ DECLARE a jsonb; BEGIN
 PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000005',true);
 PERFORM public.okeyix_quick_play('40000000-0000-0000-0000-000000000005',NULL,'cancel');
 a:=public.okeyix_quick_play('40000000-0000-0000-0000-000000000005','standard','start');
 IF a->>'state'<>'cancelled' OR EXISTS(SELECT 1 FROM public.tables) THEN RAISE EXCEPTION 'CANCEL_BEFORE_START_FAILED'; END IF;
 UPDATE public.profiles SET coins=999 WHERE id=auth.uid();
 BEGIN
  PERFORM public.okeyix_quick_play(gen_random_uuid(),NULL,'start');
  RAISE EXCEPTION 'LOW_BALANCE_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'NOT_ENOUGH_COINS' THEN RAISE; END IF; END;
 IF EXISTS(SELECT 1 FROM public.tables) THEN RAISE EXCEPTION 'FAILED_REQUEST_LEFT_TABLE'; END IF;
END $$;
ROLLBACK;

BEGIN;
DO $$ DECLARE a jsonb; tid uuid; BEGIN
 -- Private human table is not a match; result must be a different bot table.
 INSERT INTO public.tables(league_id,max_players,entry_coin,status,created_by,is_private)
 VALUES('standard',2,1000,'waiting','00000000-0000-0000-0000-000000000006',true) RETURNING id INTO tid;
 INSERT INTO public.table_players(table_id,user_id,seat_index,hand) VALUES(tid,'00000000-0000-0000-0000-000000000006',0,'[]');
 PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000007',true);
 a:=public.okeyix_quick_play('50000000-0000-0000-0000-000000000007',NULL,'start');
 IF (a->>'table_id')::uuid=tid OR NOT (a->>'bot')::boolean THEN RAISE EXCEPTION 'PRIVATE_TABLE_JOINED'; END IF;
 IF has_function_privilege('anon','public.okeyix_quick_play(uuid,text,text)','EXECUTE') THEN RAISE EXCEPTION 'ANON_ACCESS'; END IF;
 IF has_schema_privilege('authenticated','okeyix_quick_private','USAGE') THEN RAISE EXCEPTION 'PRIVATE_SCHEMA_ACCESS'; END IF;
END $$;
ROLLBACK;

BEGIN;
DO $$ BEGIN
 PERFORM set_config('request.jwt.claim.sub','',true);
 BEGIN
  PERFORM public.okeyix_quick_play(gen_random_uuid(),NULL,'start');
  RAISE EXCEPTION 'UNAUTHENTICATED_ACCEPTED';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000008',true);
 UPDATE public.users SET is_bot=true WHERE id='00000000-0000-0000-0000-000000000009';
 UPDATE public.users SET is_bot=false WHERE id='00000000-0000-0000-0000-000000000090';
 BEGIN
  PERFORM public.okeyix_quick_play(gen_random_uuid(),NULL,'start');
  RAISE EXCEPTION 'SPOOFED_BOT_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'QUICK_PLAY_NO_BOT_AVAILABLE' THEN RAISE; END IF; END;
 IF EXISTS(SELECT 1 FROM public.tables) THEN RAISE EXCEPTION 'NO_BOT_LEFT_EMPTY_TABLE'; END IF;
END $$;
ROLLBACK;
SELECT 'QUICK_PLAY_SQL_TESTS_PASSED';
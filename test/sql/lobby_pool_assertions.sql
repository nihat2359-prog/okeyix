SELECT public.pool_assert((SELECT enabled AND target=1 FROM okeyix_ready_private.policy),'active target one');
SELECT public.pool_assert(NOT EXISTS(SELECT 1 FROM public.tables t JOIN okeyix_ready_private.managed m ON m.table_id=t.id
 WHERE t.league_id='standard'),'existing human prevents ready bot');
SELECT public.pool_assert((SELECT count(*)=2 FROM okeyix_ready_private.managed),'one bronze and silver ready table');
SELECT okeyix_bot_wallet_private.source_maintainer(1,true);
SELECT public.pool_assert((SELECT count(*)=2 FROM okeyix_ready_private.managed),'maintenance idempotent');
INSERT INTO public.tables(id,league_id,created_by,status,max_players,entry_coin)
 VALUES(md5('bronze-human-table')::uuid,'bronze',md5('pool-human-1')::uuid,'waiting',2,50000);
INSERT INTO public.table_players(table_id,user_id,seat_index)
 VALUES(md5('bronze-human-table')::uuid,md5('pool-human-1')::uuid,0);
SELECT public.pool_assert(NOT EXISTS(SELECT 1 FROM public.tables t JOIN okeyix_ready_private.managed m ON m.table_id=t.id
 WHERE t.league_id='bronze'),'human seat immediately prunes bot-only table');
-- A joined/playing managed table must NEVER be pruned.
INSERT INTO public.table_players(table_id,user_id,seat_index)
 SELECT t.id,md5('pool-human-2')::uuid,1 FROM public.tables t JOIN okeyix_ready_private.managed m ON m.table_id=t.id WHERE t.league_id='silver';
SELECT okeyix_bot_wallet_private.source_maintainer(1,true);
SELECT public.pool_assert(EXISTS(SELECT 1 FROM public.table_players WHERE user_id=md5('pool-human-2')::uuid),'joined human preserved');
SELECT public.pool_assert((SELECT count(*)=2 FROM public.tables t JOIN okeyix_ready_private.managed m ON m.table_id=t.id WHERE t.league_id='silver'),'full table plus one waiting seat');
-- Seven display tables per league; no real seats/tables or Auth rows are made.
SELECT set_config('request.jwt.claim.sub',md5('human')::uuid::text,false);
SELECT public.pool_assert(NOT EXISTS(SELECT 1 FROM public.leagues l
 WHERE jsonb_array_length(public.okeyix_lobby_showcase(l.id))<>7),'all five leagues have seven showcases');
SELECT public.pool_assert(NOT EXISTS(SELECT 1 FROM public.leagues l,
 jsonb_array_elements(public.okeyix_lobby_showcase(l.id)) x
 WHERE x->>'is_fake'<>'true' OR x->>'status'<>'playing' OR jsonb_array_length(x->'_players')<>2),'full display-only rows');
SELECT set_config('request.jwt.claim.sub','',false);
SELECT public.pool_assert(public.okeyix_lobby_showcase('standard')='[]'::jsonb,'no anonymous showcase');

BEGIN;
TRUNCATE public.tables,public.table_players,okeyix_ready_private.managed,
 okeyix_match_private.requests,okeyix_quick_private.requests CASCADE;
-- An affordable cross-league real waiting table beats the queue immediately.
INSERT INTO public.tables(id,league_id,created_by,status,max_players,entry_coin)
 VALUES(md5('pool-open')::uuid,'standard',md5('pool-human-1')::uuid,'waiting',2,1000);
INSERT INTO public.table_players(table_id,user_id,seat_index)
 VALUES(md5('pool-open')::uuid,md5('pool-human-1')::uuid,0);
SELECT set_config('request.jwt.claim.sub',md5('pool-human-3')::uuid::text,true);
DO $$ DECLARE r jsonb; BEGIN
 r:=public.okeyix_quick_play_v2(md5('open-request')::uuid,'start');
 PERFORM public.pool_assert(r->>'state'='ready' AND r->>'table_id'=md5('pool-open')::uuid::text,'open human table instant join');
END $$;
ROLLBACK;

BEGIN;
TRUNCATE public.tables,public.table_players,okeyix_ready_private.managed,
 okeyix_match_private.requests,okeyix_quick_private.requests CASCADE;
-- Two concurrent users' committed queue requests share one result/table.
DO $$ DECLARE first jsonb; second jsonb; again jsonb; BEGIN
 PERFORM set_config('request.jwt.claim.sub',md5('pool-human-1')::uuid::text,true);
 first:=public.okeyix_quick_play_v2(md5('pair-one')::uuid,'start');
 PERFORM public.pool_assert(first->>'state'='waiting','first human waits');
 PERFORM set_config('request.jwt.claim.sub',md5('pool-human-3')::uuid::text,true);
 second:=public.okeyix_quick_play_v2(md5('pair-two')::uuid,'start');
 PERFORM public.pool_assert(second->>'state'='ready' AND NOT (second->>'bot')::boolean,'second human pairs');
 PERFORM set_config('request.jwt.claim.sub',md5('pool-human-1')::uuid::text,true);
 again:=public.okeyix_quick_play_v2(md5('pair-one')::uuid,'refresh');
 PERFORM public.pool_assert(again->>'table_id'=second->>'table_id'
   AND (SELECT count(*) FROM public.tables)=1,'same atomic human match');
END $$;
ROLLBACK;

BEGIN;
TRUNCATE public.tables,public.table_players,okeyix_ready_private.managed,
 okeyix_match_private.requests,okeyix_quick_private.requests CASCADE;
-- A fake table with a human-shaped seat must never become a match candidate.
INSERT INTO public.tables(id,league_id,created_by,status,max_players,entry_coin,is_fake)
 VALUES(md5('pool-fake')::uuid,'standard',md5('pool-human-1')::uuid,'waiting',2,1000,true);
INSERT INTO public.table_players(table_id,user_id,seat_index)
 VALUES(md5('pool-fake')::uuid,md5('pool-human-1')::uuid,0);
SELECT set_config('request.jwt.claim.sub',md5('pool-human-3')::uuid::text,true);
DO $$ DECLARE r jsonb; BEGIN
 r:=public.okeyix_quick_play_v2(md5('fake-request')::uuid,'start');
 PERFORM public.pool_assert(r->>'state'='waiting' AND (r->>'remaining_ms')::int<=5000,'fake excluded and wait five seconds');
END $$;
ROLLBACK;

BEGIN;
TRUNCATE public.tables,public.table_players,okeyix_ready_private.managed,
 okeyix_match_private.requests,okeyix_quick_private.requests CASCADE;
-- Real elapsed five seconds, renewing the existing four-second lease.
SELECT set_config('request.jwt.claim.sub',md5('pool-human-3')::uuid::text,true);
UPDATE public.profiles SET rating=1200 WHERE id=auth.uid();
DO $$ DECLARE r jsonb; started timestamptz:=clock_timestamp(); BEGIN
 r:=public.okeyix_quick_play_v2(md5('five-second-request')::uuid,'start');
 PERFORM public.pool_assert(r->>'state'='waiting','initial queue state');
 LOOP
  PERFORM pg_sleep(0.5);
  r:=public.okeyix_quick_play_v2(md5('five-second-request')::uuid,'refresh');
  EXIT WHEN r->>'state'<>'waiting';
 END LOOP;
 PERFORM public.pool_assert(r->>'state'='ready' AND (r->>'bot')::boolean
   AND clock_timestamp()-started>=interval '5 seconds'
   AND clock_timestamp()-started<interval '8 seconds','bot fallback after real five seconds');
END $$;
ROLLBACK;

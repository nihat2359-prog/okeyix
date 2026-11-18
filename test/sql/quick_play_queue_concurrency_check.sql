SELECT :'scenario'='pair' AS is_pair \gset
\if :is_pair
DO $$ BEGIN
 IF (SELECT count(*) FROM public.tables)<>1 OR (SELECT count(*) FROM public.table_players)<>2 OR
    (SELECT count(*) FROM okeyix_match_private.requests WHERE state='matched')<>2 OR
    EXISTS(SELECT 1 FROM public.table_players p JOIN public.users u ON u.id=p.user_id WHERE u.is_bot) THEN
   RAISE EXCEPTION 'CONCURRENT_HUMANS_DID_NOT_SHARE_ONE_TABLE'; END IF;
END $$;
\else
DO $$ DECLARE seats int; s text; BEGIN
 SELECT count(*) INTO seats FROM public.table_players;
 SELECT state INTO s FROM okeyix_match_private.requests WHERE user_id='00000000-0000-0000-0000-000000000001';
 IF NOT ((seats=0 AND s='cancelled') OR (seats=2 AND s='matched')) THEN
   RAISE EXCEPTION 'CANCEL_MATCH_RACE_INCONSISTENT'; END IF;
 IF EXISTS(SELECT 1 FROM public.table_players p JOIN public.users u ON u.id=p.user_id WHERE u.is_bot) THEN
   RAISE EXCEPTION 'RACE_ALLOCATED_BOT'; END IF;
END $$;
\endif
DO $$ BEGIN
 IF EXISTS(SELECT user_id FROM public.table_players GROUP BY user_id HAVING count(*)>1) OR
    EXISTS(SELECT table_id FROM public.table_players GROUP BY table_id HAVING count(*)>2) OR
    EXISTS(SELECT 1 FROM public.profiles WHERE coins<>20000000) THEN
   RAISE EXCEPTION 'QUEUE_DUPLICATE_SEAT_OR_DEBIT'; END IF;
END $$;
SELECT 'QUICK_PLAY_QUEUE_CONCURRENCY_PASSED';

TRUNCATE okeyix_match_private.requests,okeyix_quick_private.requests,public.table_players,public.tables;
UPDATE public.profiles SET coins=20000000,rating=50,is_online=true,last_seen_at=clock_timestamp()
 WHERE id IN (SELECT id FROM public.users WHERE NOT is_bot);
SELECT :'scenario'='cancel' AS is_cancel \gset
\if :is_cancel
SET request.jwt.claim.sub='00000000-0000-0000-0000-000000000001';
SELECT public.okeyix_quick_play_v2('10000000-0000-0000-0000-000000000001','start');
\endif

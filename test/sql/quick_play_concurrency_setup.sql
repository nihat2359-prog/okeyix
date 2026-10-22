-- Disposable local fixture database only.
TRUNCATE okeyix_quick_private.requests,public.table_players,public.tables;
INSERT INTO public.tables(id,league_id,max_players,entry_coin,status,created_by)
 VALUES('90000000-0000-0000-0000-000000000001','standard',2,1000,'waiting','00000000-0000-0000-0000-000000000001');
INSERT INTO public.table_players(table_id,user_id,seat_index,hand)
 VALUES('90000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001',0,'[]');

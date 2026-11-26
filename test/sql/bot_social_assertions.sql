\set ON_ERROR_STOP on
SELECT okeyix_bot_social_tick('00000000-0000-0000-0000-000000000010');
UPDATE okeyix_bot_social_state SET started_at=now()-interval '10 seconds';
SELECT okeyix_bot_social_tick('00000000-0000-0000-0000-000000000010');
SELECT okeyix_bot_social_tick('00000000-0000-0000-0000-000000000010');
SELECT okeyix_bot_social_tick('00000000-0000-0000-0000-000000000010');
DO $$ BEGIN
 IF (SELECT count(*) FROM table_messages WHERE content='Bol şans')<>1 THEN RAISE EXCEPTION 'greeting'; END IF;
 IF (SELECT count(*) FROM okeyix_table_gift_purchases)<>1 THEN RAISE EXCEPTION 'tea duplicate'; END IF;
 IF (SELECT coins FROM profiles WHERE id='00000000-0000-0000-0000-000000000002')<>9000 THEN RAISE EXCEPTION 'wallet'; END IF;
END $$;
UPDATE tables SET last_winner_user_id='00000000-0000-0000-0000-000000000001',last_finish_at=now()-interval '5 seconds';
SELECT okeyix_bot_social_tick(id,NULL) FROM tables;
DO $$ BEGIN IF EXISTS(SELECT FROM table_messages WHERE content='Tebrikler') THEN RAISE EXCEPTION 'early congratulations'; END IF; END $$;
SELECT okeyix_bot_social_tick(id,last_finish_at) FROM tables;
SELECT okeyix_bot_social_tick(id,last_finish_at) FROM tables;
DO $$ BEGIN IF (SELECT count(*) FROM table_messages WHERE content='Tebrikler')<>1 THEN RAISE EXCEPTION 'congratulations duplicate'; END IF; END $$;
UPDATE okeyix_bot_social_state SET last_reply_at=now()-interval '20 seconds';
INSERT INTO table_messages(table_id,sender_id,role,type,content,created_at) VALUES('00000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000001','player','text','Nasılsın?',now()-interval '4 seconds');
SELECT okeyix_bot_social_tick(id,last_finish_at) FROM tables;
DO $$ BEGIN IF NOT EXISTS(SELECT FROM table_messages WHERE content='iyiyim sen nasılsın') THEN RAISE EXCEPTION 'reply'; END IF; END $$;
-- Congratulations take priority even when another conversational phrase is present.
UPDATE table_messages SET created_at=now()-interval '8 seconds' WHERE content='Nasılsın?';
UPDATE okeyix_bot_social_state SET last_reply_at=now()-interval '20 seconds';
INSERT INTO table_messages(table_id,sender_id,role,type,content,created_at)
VALUES('00000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000001','player','text','Tebrikler',now()-interval '4 seconds');
SELECT okeyix_bot_social_tick(id,last_finish_at) FROM tables;
SELECT okeyix_bot_social_tick(id,last_finish_at) FROM tables;
DO $$ BEGIN
 IF (SELECT count(*) FROM table_messages WHERE content='teşekkürler')<>1 THEN
   RAISE EXCEPTION 'congratulations must receive exactly one thank you';
 END IF;
END $$;

\set ON_ERROR_STOP on
-- Apply the fixture, 20261126000300 and 20261126000400 first, in a disposable cluster.
CREATE FUNCTION public.social_assert(p_ok boolean,p_label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'BOT_SOCIAL: %',p_label; END IF; END $$;
CREATE FUNCTION public.social_tick() RETURNS void LANGUAGE sql AS $$
 SELECT public.okeyix_bot_social_tick(id,last_finish_at) FROM public.tables;
$$;

-- A long lobby wait must not consume any of the actual game's opening delay.
UPDATE tables SET status='waiting';
SELECT social_tick();
UPDATE okeyix_bot_social_state SET started_at=clock_timestamp()-interval '10 minutes';
SELECT social_assert((SELECT play_started_at IS NULL FROM okeyix_bot_social_state),'waiting does not start timer');
UPDATE tables SET status='playing';
SELECT social_tick();
SELECT social_assert((SELECT greeting_due_at-play_started_at BETWEEN interval '5 seconds' AND interval '9 seconds'
 FROM okeyix_bot_social_state),'greeting waits 5-9 seconds after play');
SELECT social_assert(NOT EXISTS(SELECT FROM table_messages),'nothing sent at game start');
SELECT social_assert(NOT EXISTS(SELECT FROM okeyix_table_gift_purchases),'no instant tea');
UPDATE okeyix_bot_social_state SET greeting_due_at=clock_timestamp()-interval '1 second';
SELECT social_tick();
SELECT social_tick();
SELECT social_assert((SELECT count(*)=1 FROM table_messages WHERE content='Bol şans'),'one greeting');
SELECT social_assert((SELECT tea_due_at-last_reply_at BETWEEN interval '5 seconds' AND interval '9 seconds'
 FROM okeyix_bot_social_state),'tea is delayed after greeting');
SELECT social_assert(NOT EXISTS(SELECT FROM okeyix_table_gift_purchases),'tea does not accompany greeting');
UPDATE okeyix_bot_social_state SET tea_due_at=clock_timestamp()-interval '1 second';
SELECT social_tick();
SELECT social_tick();
SELECT social_assert((SELECT count(*)=1 FROM okeyix_table_gift_purchases),'one tea only');
SELECT social_assert((SELECT coins=9000 FROM profiles WHERE id='00000000-0000-0000-0000-000000000002'),'tea debits bot wallet once');

-- No human engagement means no unsolicited question, even after a long time.
UPDATE okeyix_bot_social_state SET question_due_at=clock_timestamp()-interval '2 minutes',last_reply_at=clock_timestamp()-interval '1 minute';
UPDATE table_messages SET created_at=clock_timestamp()-interval '1 minute';
SELECT social_tick();
SELECT social_assert((SELECT count(*)=1 FROM table_messages),'silent player is not pursued');

CREATE FUNCTION public.social_send(p_text text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE before_count integer; pending uuid;
BEGIN
 SELECT count(*) INTO before_count FROM table_messages WHERE sender_id='00000000-0000-0000-0000-000000000002';
 INSERT INTO table_messages(table_id,sender_id,role,type,content)
 VALUES('00000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000001','player','text',p_text);
 PERFORM social_tick();
 PERFORM social_assert((SELECT count(*)=before_count FROM table_messages WHERE sender_id='00000000-0000-0000-0000-000000000002'),'no instant reply');
 PERFORM social_assert((SELECT pending_due_at BETWEEN clock_timestamp()+interval '4 seconds' AND clock_timestamp()+interval '11 seconds'
 FROM okeyix_bot_social_state),'reading and typing delay');
 UPDATE okeyix_bot_social_state SET pending_due_at=clock_timestamp()-interval '1 second',last_reply_at=clock_timestamp()-interval '20 seconds';
 PERFORM social_tick();
 PERFORM social_assert((SELECT count(*)=before_count+1 FROM table_messages WHERE sender_id='00000000-0000-0000-0000-000000000002'),'exactly one reply');
 PERFORM social_tick();
 PERFORM social_assert((SELECT count(*)=before_count+1 FROM table_messages WHERE sender_id='00000000-0000-0000-0000-000000000002'),'no duplicate reply');
END $$;

SELECT social_send('selam');
-- Allow the bot's one proactive tiles question after an actual exchange.
UPDATE table_messages SET created_at=clock_timestamp()-interval '30 seconds';
UPDATE okeyix_bot_social_state SET last_reply_at=clock_timestamp()-interval '30 seconds';
SELECT social_tick();
SELECT social_assert((SELECT asked AND awaiting_answer AND topic='tiles' FROM okeyix_bot_social_state),'bot asks about tiles');
UPDATE table_messages SET created_at=clock_timestamp()-interval '30 seconds';
UPDATE okeyix_bot_social_state SET last_reply_at=clock_timestamp()-interval '30 seconds';
SELECT social_tick();
SELECT social_tick();
SELECT social_assert((SELECT count(*)=3 FROM table_messages WHERE sender_id='00000000-0000-0000-0000-000000000002'),'unanswered question gets no follow-up');
SELECT social_send('iyi sende nasıl');
SELECT social_assert((SELECT content IN ('bende daha karışık biraz :)','toparlamaya çalışıyom daha','bi taş bekliyom bakalım','fena değil bakalım nolcak')
 FROM table_messages WHERE sender_id='00000000-0000-0000-0000-000000000002' ORDER BY created_at DESC,id DESC LIMIT 1),'contextual answer to good, how about you');
SELECT social_send('Tebrikler');
SELECT social_assert((SELECT content='teşekkürler' FROM table_messages WHERE sender_id='00000000-0000-0000-0000-000000000002'
 ORDER BY created_at DESC,id DESC LIMIT 1),'congratulations receives thanks');
SELECT social_send('nasılsın');
SELECT social_assert((SELECT topic='wellbeing' AND awaiting_answer FROM okeyix_bot_social_state),'wellbeing remembers question');
SELECT social_send('iyiyim ya sen');
SELECT social_assert((SELECT NOT awaiting_answer AND topic IS NULL FROM okeyix_bot_social_state),'return answer closes question');
SELECT social_send('adın ne');
SELECT social_assert((SELECT topic='introduction' AND awaiting_answer FROM okeyix_bot_social_state),'name question context');
SELECT social_send('ahmet');
SELECT social_assert((SELECT content LIKE 'memnun oldum%' OR content LIKE 'hoş geldin%' FROM table_messages
 WHERE sender_id='00000000-0000-0000-0000-000000000002' ORDER BY created_at DESC,id DESC LIMIT 1),'bare name is understood');
SELECT social_send('mesaj atma');
SELECT social_assert((SELECT topic='quiet' AND NOT awaiting_answer FROM okeyix_bot_social_state),'quiet request honored');
UPDATE okeyix_bot_social_state SET asked=false,last_reply_at=clock_timestamp()-interval '30 seconds';
UPDATE table_messages SET created_at=clock_timestamp()-interval '30 seconds';
DO $$ DECLARE before_count integer;
BEGIN
 SELECT count(*) INTO before_count FROM table_messages;
 PERFORM social_tick();
 PERFORM social_assert((SELECT count(*)=before_count FROM table_messages),'no question after quiet request');
 UPDATE okeyix_bot_social_state SET topic='tiles',awaiting_answer=true;
 PERFORM social_tick();
 PERFORM social_assert((SELECT count(*)=before_count FROM table_messages),'unanswered question blocks new question');
END $$;

-- Newer messages postpone a pending response and replace its target.
INSERT INTO table_messages(table_id,sender_id,role,type,content)
VALUES('00000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000001','player','text','selam');
SELECT social_tick();
UPDATE okeyix_bot_social_state SET pending_due_at=clock_timestamp()-interval '1 second',last_reply_at=clock_timestamp()-interval '20 seconds';
INSERT INTO table_messages(table_id,sender_id,role,type,content)
VALUES('00000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000001','player','text','nasılsın');
SELECT social_tick();
SELECT social_assert((SELECT m.content='nasılsın' AND s.pending_due_at>clock_timestamp()
 FROM okeyix_bot_social_state s JOIN table_messages m ON m.id=s.pending_message_id),'latest message replaces pending reply');
UPDATE okeyix_bot_social_state SET pending_due_at=clock_timestamp()-interval '1 second';
SELECT social_tick();
SELECT social_assert((SELECT topic='wellbeing' FROM okeyix_bot_social_state),'latest topic is used');

-- Test a wider set of casual spellings and introduction topics without waiting.
DO $$
DECLARE sample record; result jsonb;
BEGIN
 FOR sample IN SELECT * FROM (VALUES
 ('slm',NULL,'hello'),('SA',NULL,'hello'),('nbr',NULL,'wellbeing'),('napıyon',NULL,'wellbeing'),
 ('iyi sende nasıl','tiles','tiles_return'),('iyiyim sen','wellbeing','wellbeing_return'),
 ('iyi','tiles','tiles_answer'),('kötü','tiles','tiles_answer'),('adın ne',NULL,'name'),
 ('ben ahmet','introduction','introduction'),('ahmet','introduction','introduction'),
 ('nerelisin',NULL,'location'),('nerden',NULL,'location'),('kaç yaşındasın',NULL,'age'),
 ('işin ne',NULL,'occupation'),('telefon numaran var mı',NULL,'contact'),('bot musun',NULL,'identity'),
 ('tebrikler selam',NULL,'congratulations'),('sağol',NULL,'thanks'),('bol şans',NULL,'luck'),
 ('çay için teşekkürler',NULL,'gift'),('rövanş',NULL,'rematch'),('yeniyim',NULL,'new_player'),
 ('ne zamandır oynuyorsun',NULL,'experience'),('hızlı oyna',NULL,'speed'),('bi dk bekle',NULL,'wait'),
 ('pardon',NULL,'sorry'),('görüşürüz',NULL,'bye'),('sus',NULL,'quiet'),('anlamadım','tiles','clarify'),
 ('evet','frequency','frequency_answer'),('bilinmeyen bir cümle',NULL,'unknown'),
 ('NERDEN?',NULL,'location'),('Nereden',NULL,'location'),('nrdn',NULL,'location'),
 ('nrden',NULL,'location'),('nerdn',NULL,'location'),('NERDESİN',NULL,'location'),
 ('NEREDE OTURUYORSUN',NULL,'location'),('MEMLEKET NERE',NULL,'location'),
 ('yaş kaç',NULL,'age'),('YAŞ KAÇ?',NULL,'age'),('YAŞIN KAÇ',NULL,'age'),
 ('yaşınkaç',NULL,'age'),('kc yas',NULL,'age'),('yasiniz kac',NULL,'age'),
 ('yaşın ne',NULL,'age'),('kacc yasindasin',NULL,'age'),
 ('MESLEK NE',NULL,'occupation'),('meslk ne',NULL,'occupation'),
 ('ne iş yapıyosun',NULL,'occupation'),('işin ne',NULL,'occupation'),
 ('çalışıyomusun',NULL,'occupation'),('EMEKLİ MİSİN',NULL,'occupation'),
 ('evli misin',NULL,'marital'),('EVLİMİSİN',NULL,'marital'),('ewli misin',NULL,'marital'),
 ('bekar mısın',NULL,'marital'),('BEKARMISIN',NULL,'marital'),('medeni halin ne',NULL,'marital'),
 ('çocuk var mı',NULL,'children'),('ÇOCUĞUN VAR MI?',NULL,'children'),
 ('kaç çocuğun var',NULL,'children'),('cocuun var mi',NULL,'children'),
 ('baba mısın',NULL,'children'),('kızın var mı',NULL,'children'),
 ('okuyonmu',NULL,'education'),('hangi bölüm',NULL,'education'),('öğrenci misin',NULL,'education'),
 ('ERKEK MİSİN',NULL,'gender'),('kızmısın',NULL,'gender'),
 ('sevgilin var mı',NULL,'relationship'),('kardeşin var mı',NULL,'family'),
 ('ailen nerde',NULL,'family'),('annen ne yapıyor',NULL,'family'),
 ('insta var mı',NULL,'contact'),('hobin ne',NULL,'hobbies'),('ne müzik dinlersin',NULL,'hobbies'),
 ('hangi takımı tutuyorsun',NULL,'sports'),('SLM',NULL,'hello'),('meraba',NULL,'hello'),
 ('NASILSIN',NULL,'wellbeing'),('NASILSİN',NULL,'wellbeing'),('naslsin',NULL,'wellbeing'),
 ('İYİ SENDE NASIL','tiles','tiles_return'),('ii snde nasıl','tiles','tiles_return'),
 ('iyiyim senn','wellbeing','wellbeing_return'),('tşk',NULL,'thanks'),
 ('tanışalım mı',NULL,'name'),('tanışabilir miyiz',NULL,'name'),('ismin',NULL,'name'),
 ('ne işle uğraşıyosun',NULL,'occupation'),('memur musun',NULL,'occupation'),
 ('boyun kaç',NULL,'appearance'),('burcun ne',NULL,'appearance'),
 ('buluşalım mı',NULL,'meet'),('s.a',NULL,'hello'),('a.s',NULL,'hello_return')
 ) AS v(message,topic,intent) LOOP
   result:=okeyix_bot_social_private.respond('00000000-0000-0000-0000-000000000002',0,sample.message,sample.topic,'Mert');
   PERFORM social_assert(result->>'intent'=sample.intent,'intent: '||sample.message||' got '||(result->>'intent'));
 END LOOP;
END $$;
SELECT social_assert((SELECT count(DISTINCT okeyix_bot_social_private.respond(
 ('00000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid,0,'nasılsın',NULL,'Mert')->>'text')>1
 FROM generate_series(1,20) i),'different bots have different replies');
SELECT social_assert((SELECT count(DISTINCT okeyix_bot_social_private.respond(
 '00000000-0000-0000-0000-000000000002',i,'nasılsın',NULL,'Mert')->>'text')=4
 FROM generate_series(0,3) i),'one bot varies repeated replies');
SELECT social_assert(NOT has_function_privilege('authenticated',
 'okeyix_bot_social_private.respond(uuid,integer,text,text,text)','EXECUTE'),'private responder is not an RPC');
DO $$
DECLARE bot_id uuid:='00000000-0000-0000-0000-000000000002'; hometown text; answer jsonb; question text; turn integer;
BEGIN
 hometown:=okeyix_bot_social_private.choose(bot_id,'hometown',0,
   ARRAY['istanbul','ankara','izmir','bursa','antalya','adana','mersin','samsun',
     'eskişehir','konya','kayseri','trabzon','balıkesir','denizli','sivas','gaziantep']);
 FOREACH question IN ARRAY ARRAY['nerden','nereden','NERELİSİN','nrdn','hangi şehir','memleket nere'] LOOP
   FOR turn IN 0..5 LOOP
     answer:=okeyix_bot_social_private.respond(bot_id,turn,question,NULL,'Mert');
     PERFORM social_assert(position(hometown IN answer->>'text')>0,'same hometown across questions and turns');
     PERFORM social_assert(answer->>'topic'='location' AND (answer->>'awaiting_answer')::boolean,'asks player hometown');
     PERFORM social_assert(answer->>'text' NOT LIKE '%bot%','hometown answer stays in character');
   END LOOP;
 END LOOP;
 answer:=okeyix_bot_social_private.respond(bot_id,0,'ben ankara','location','Mert');
 PERFORM social_assert(answer->>'intent'='location_answer' AND NOT (answer->>'awaiting_answer')::boolean,'acknowledges player city without another question');
 answer:=okeyix_bot_social_private.respond(bot_id,0,'bot musun','location','Mert');
 PERFORM social_assert(answer->>'intent'='identity' AND answer->>'text' LIKE '%oyun karakteriyim%'
   AND answer->>'text' !~* '(bot|robot)','identity uses game character wording');
END $$;

-- Not enough coins for tea must never block conversational replies.
UPDATE profiles SET coins=0 WHERE id='00000000-0000-0000-0000-000000000002';
UPDATE okeyix_bot_social_state SET tea_sent=false,tea_due_at=clock_timestamp()-interval '1 second';
SELECT social_send('teşekkürler');
SELECT social_assert((SELECT count(*)=1 FROM okeyix_table_gift_purchases),'insufficient coins never create another gift');

-- Finish events also wait after the client reports closing the presentation.
UPDATE tables SET last_winner_user_id='00000000-0000-0000-0000-000000000001',last_finish_at=clock_timestamp()-interval '5 seconds';
SELECT social_tick();
SELECT social_assert(NOT EXISTS(SELECT FROM table_messages WHERE content='Tebrikler'
 AND sender_id='00000000-0000-0000-0000-000000000002'),'finish has delayed reaction');
UPDATE okeyix_bot_social_state SET finish_due_at=clock_timestamp()-interval '1 second';
SELECT social_tick();
SELECT social_tick();
SELECT social_assert((SELECT count(*)=1 FROM table_messages WHERE content='Tebrikler'
 AND sender_id='00000000-0000-0000-0000-000000000002'),'one finish congratulations');
SELECT 'bot social conversation checks passed' AS result;

\set ON_ERROR_STOP on
-- This runs after the existing conversation tests, in the disposable local cluster.
CREATE SCHEMA okeyix_bot_avatar_private;
CREATE TABLE okeyix_bot_avatar_private.assignments(user_id uuid,gender text,assigned_at timestamptz DEFAULT now());
INSERT INTO okeyix_bot_avatar_private.assignments VALUES
 ('00000000-0000-0000-0000-000000000002','male',now()),
 ('00000000-0000-0000-0000-000000000003','female',now());
DO $$
DECLARE id uuid; p jsonb; a jsonb; sample record; turn integer; i integer;
BEGIN
 FOR i IN 1..40 LOOP
   id:=('00000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid;
   p:=okeyix_bot_social_private.persona(id);
   PERFORM social_assert(p=okeyix_bot_social_private.persona(id),'stable persona');
   PERFORM social_assert((p->>'age')::integer BETWEEN 27 AND 56,'adult character age');
   PERFORM social_assert((p->>'children')::integer=0 OR ((p->>'married')::boolean AND (p->>'age')::integer>=30),'coherent family background');
   PERFORM social_assert(NOT (p->>'married')::boolean OR p->>'relationship'='evliyim','married relationship is consistent');
   FOR turn IN 0..5 LOOP
     FOR sample IN SELECT * FROM (VALUES
       ('yaş kaç','age','age'),('mesleğin ne','occupation','occupation'),
       ('ne mezunusun','education','education'),('hangi takım','team','sports'),
       ('hobin ne','hobby','hobbies'),('ne müzik dinlersin','music','hobbies'),
       ('ne film izlersin','films','hobbies'),('ne kitap okursun','books','hobbies'),
       ('boyun kaç','height','appearance'),('kilon kaç','weight','appearance'),
       ('burcun ne','sign','appearance'),('ne zamandır oynuyorsun','experience','experience')
     ) AS v(message,field,intent) LOOP
       a:=okeyix_bot_social_private.respond(id,turn,sample.message,NULL,'Mert');
       PERFORM social_assert(a->>'intent'=sample.intent,'persona intent: '||sample.message);
       PERFORM social_assert(position(p->>sample.field IN a->>'text')>0,'stable answer: '||sample.field);
       PERFORM social_assert(a->>'text' !~ '(botum|botuyum|botu|oyun bot)','normal chat stays in character');
       PERFORM social_assert(a->>'text' !~ '(Ã|Å|Ä|�)','Turkish text encoding');
     END LOOP;
     a:=okeyix_bot_social_private.respond(id,turn,'evli misin',NULL,'Mert');
     PERFORM social_assert(position(CASE WHEN (p->>'married')::boolean THEN 'evliyim' ELSE 'bekar' END IN a->>'text')>0,'consistent marital answer');
     a:=okeyix_bot_social_private.respond(id,turn,'çocuk var mı',NULL,'Mert');
     PERFORM social_assert(CASE WHEN (p->>'children')::integer=0 THEN a->>'text' LIKE '%yok%'
       ELSE position(p->>'children' IN a->>'text')>0 END,'consistent child count');
     a:=okeyix_bot_social_private.respond(id,turn,'sevgilin var mı',NULL,'Mert');
     PERFORM social_assert(position(p->>'relationship' IN a->>'text')>0,'consistent relationship answer');
     FOR sample IN SELECT * FROM (VALUES
       ('adın ne'),('evli misin'),('çocuk var mı'),('kardeşin var mı'),('ailen nerde'),
       ('annen ne yapıyor'),('kiminle yaşıyorsun'),('telefon numaran'),('instagram var mı'),
       ('buluşalım mı'),('erkek misin'),('nerden'),('öğrenci misin')
     ) AS v(message) LOOP
       a:=okeyix_bot_social_private.respond(id,turn,sample.message,NULL,'Mert');
       PERFORM social_assert(a->>'text' !~ '(botum|botuyum|botu|oyun bot)','removed evasive bot reply: '||sample.message);
     END LOOP;
     a:=okeyix_bot_social_private.respond(id,turn,'adın ne',NULL,'Mert');
     PERFORM social_assert(a->>'text' LIKE '%Mert%','uses the avatar name');
     FOR sample IN SELECT * FROM (VALUES ('music'),('films'),('books'),('age'),('occupation'),('education'),('height'),('weight'),('sign'),('experience')) AS v(topic) LOOP
       a:=okeyix_bot_social_private.respond(id,turn,'ya sen',sample.topic,'Mert');
       PERFORM social_assert(a->>'intent'='profile_return' AND position(p->>sample.topic IN a->>'text')>0,'return question retains topic: '||sample.topic);
       PERFORM social_assert(NOT (a->>'awaiting_answer')::boolean,'return answer does not repeat question');
     END LOOP;
     FOR sample IN SELECT * FROM (VALUES ('bot musun'),('BOT MUSUN?'),('robot musun'),('gerçek misin'),('insan mısın'),('yapay zeka mısın')) AS v(message) LOOP
       a:=okeyix_bot_social_private.respond(id,turn,sample.message,NULL,'Mert');
       PERFORM social_assert(a->>'intent'='identity' AND a->>'text' LIKE '%oyun karakteriyim%'
         AND a->>'text' !~* '(bot|robot)','identity reply avoids bot wording and does not claim to be human');
     END LOOP;
     FOR sample IN SELECT * FROM (VALUES (NULL::text),('hobbies'),('location'),('age')) AS v(topic) LOOP
       a:=okeyix_bot_social_private.respond(id,turn,'zxcvbnm qwerty',sample.topic,'Mert');
       PERFORM social_assert(a->>'intent'='unknown' AND (a->>'awaiting_answer')::boolean,'unknown text asks for clarification');
       PERFORM social_assert(a->>'text' NOT IN ('anladım :)','hmm tamam','tamam :)'),'no fake understanding');
     END LOOP;
   END LOOP;
 END LOOP;
 a:=okeyix_bot_social_private.respond('00000000-0000-0000-0000-000000000002',0,'kadın mısın',NULL,'Mert');
 PERFORM social_assert(a->>'text' LIKE '%erkeğim%','male avatar gender matches');
 a:=okeyix_bot_social_private.respond('00000000-0000-0000-0000-000000000003',0,'erkek misin',NULL,'Ece');
 PERFORM social_assert(a->>'text' LIKE '%kadınım%','female avatar gender matches');
 a:=okeyix_bot_social_private.respond('00000000-0000-0000-0000-000000000002',0,'ben rock dinlerim','hobbies','Mert');
 PERFORM social_assert(a->>'intent'='hobbies_answer' AND NOT (a->>'awaiting_answer')::boolean,'hobby answer does not restart questioning');
 PERFORM social_assert(NOT has_function_privilege('authenticated','okeyix_bot_social_private.persona(uuid)','EXECUTE'),'persona helper stays private');
END $$;
SELECT 'bot persona consistency checks passed' AS result;

\set ON_ERROR_STOP on
DO $$
DECLARE sample text; topic text; a jsonb; id uuid; turn integer; i integer;
BEGIN
 FOR i IN 1..12 LOOP
   id:=('00000000-0000-0000-0000-'||lpad(i::text,12,'0'))::uuid;
   FOREACH topic IN ARRAY ARRAY[NULL,'location','introduction','tiles','hobbies','coins']::text[] LOOP
     FOR turn IN 0..2 LOOP
       FOREACH sample IN ARRAY ARRAY[
         'bu kadar çipi nereden aldın','BU KADAR ÇİPİ NEREDEN ALDIN?',
         'bu kadar cipi nerden aldin','bu kadar çip nerden','chipleri nereden aldın',
         'coinleri nerden aldın','coin mağazasından mı aldın','bakiye nasıl bu kadar çok',
         'parayı nereden buldun','coinleri nasıl kazandın','çiplerin çok fazla',
         'ne kadar coin var sende','chip nereden','bakiye','COİN','coin için para mı verdin'
       ] LOOP
         a:=okeyix_bot_social_private.respond(id,turn,sample,topic,'Mert');
         PERFORM social_assert(a->>'intent'='coins','coin question classified correctly: '||sample);
         PERFORM social_assert(a->>'text'='coin mağazasından paramla aldım','requested coin response');
         PERFORM social_assert(a->>'topic'='coins' AND NOT (a->>'awaiting_answer')::boolean,'no hometown counter-question');
       END LOOP;
     END LOOP;
   END LOOP;
 END LOOP;
 FOREACH sample IN ARRAY ARRAY['nerden','nereden','nerden aldın','nasıl aldın','ya sen'] LOOP
   a:=okeyix_bot_social_private.respond(id,0,sample,'coins','Mert');
   PERFORM social_assert(a->>'intent'='coins','short follow-up retains coin topic: '||sample);
 END LOOP;
 FOREACH sample IN ARRAY ARRAY['nerden','nereden','nerelisin','hangi şehir','hangi il','memleket nere',
   'sen nereden','peki nerelisin','nerede yaşıyorsun','nerde oturuyosun'] LOOP
   a:=okeyix_bot_social_private.respond(id,0,sample,NULL,'Mert');
   PERFORM social_assert(a->>'intent'='location','actual hometown question preserved: '||sample);
 END LOOP;
 FOREACH sample IN ARRAY ARRAY['bunu nereden buldun','nereden öğrendin','nerede çalışıyorsun',
   'hangi ilacı aldın','nereden oynanıyor','hediyeyi nereden aldın','bu taş nereden geldi'] LOOP
   a:=okeyix_bot_social_private.respond(id,0,sample,NULL,'Mert');
   PERFORM social_assert(a->>'intent'<>'location','where does not automatically mean hometown: '||sample);
 END LOOP;
 a:=okeyix_bot_social_private.respond(id,0,'coin için teşekkürler',NULL,'Mert');
 PERFORM social_assert(a->>'intent'='thanks','gratitude is not a coin-source question');
 a:=okeyix_bot_social_private.respond(id,0,'coin mağazası nerede',NULL,'Mert');
 PERFORM social_assert(a->>'intent'='coin_store','store navigation is not hometown or purchase history');
END $$;
SELECT 'bot coin intent checks passed' AS result;

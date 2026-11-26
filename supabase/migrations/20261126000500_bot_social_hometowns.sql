BEGIN;
-- A hometown is fictional avatar background, stable for the bot UUID in every session.
-- Direct questions about being a bot still use the explicit identity response.
CREATE OR REPLACE FUNCTION okeyix_bot_social_private.respond(
  p_bot uuid,p_turn integer,p_message text,p_topic text,p_name text)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog,pg_temp AS $$
DECLARE
  n text := okeyix_bot_social_private.normalize(p_message);
  hometown text := okeyix_bot_social_private.choose(p_bot,'hometown',0,
    ARRAY['istanbul','ankara','izmir','bursa','antalya','adana','mersin','samsun',
      'eskişehir','konya','kayseri','trabzon','balıkesir','denizli','sivas','gaziantep']);
  intent text;
  next_topic text;
  options text[];
  asks boolean := false;
BEGIN
  CASE
    WHEN n ~ '(bot musun|robot musun|gercek misin|insan misin|yapay zeka)' THEN
      intent:='identity'; options:=ARRAY['evet oyun botuyum :)','botum ben, oyun arkadaşı :)','okeyix botuyum ben'];
    WHEN n ~ '(tebrik|helal|bravo|bravoo)' THEN
      intent:='congratulations'; options:=ARRAY['teşekkürler'];
    WHEN n ~ '(gorusuruz|hosca kal|hoscakal|bay bay|ben ciktim|ben cikiyorum|gitmem lazim|iyi geceler)' THEN
      intent:='bye'; options:=ARRAY['görüşürüz iyi oyunlar','hadi görüşürüz :)','tamam görüşürüz'];
      next_topic:='bye';
    WHEN n ~ '(sus|konusma|mesaj atma|yazma|sohbet istemiyorum)' THEN
      intent:='quiet'; options:=ARRAY['tamam oyuna bakalım','tamamdır','tamam :)']; next_topic:='quiet';
    WHEN n ~ '(anlamadim|ne demek|ne dedin|anlamiyorum)' THEN
      intent:='clarify'; options:=ARRAY['taşlar nasıl gidiyo onu sordum :)','elin nasıl diye sordum','taşları soruyodum ya'];
      IF p_topic IS DISTINCT FROM 'tiles' THEN options:=ARRAY['biraz karıştı galiba :) oyuna bakalım','boşver ya oyuna dönelim']; END IF;
    WHEN n ~ '(tanisalim|tanisabilir|tanisak|adin ne|ad ne|isim ne|ismin ne|adiniz ne|isminiz|kimsin|sana ne diy)'
      OR n IN ('adin','ismin','isim') THEN
      intent:='name'; options:=ARRAY[
        coalesce(nullif(p_name,''),'okeyix')||' diyebilirsin, oyun botuyum :) senin adın ne',
        'ben '||coalesce(nullif(p_name,''),'okeyix')||', oyun botuyum :) sana ne diyim'];
      next_topic:='introduction'; asks:=true;
    WHEN n ~ '(nereli|nerden|nereden|nerdesin|neredesin|nerde yas|nerede yas|nerde otur|nerede otur|hangi sehir|hangi il|memleket)' OR n IN ('nerde','nerede') THEN
      intent:='location'; options:=ARRAY[hometown||' :) sen nerden',
        'ben '||hometown||' sen nerelisin',hometown||' tarafı :) sen nerden'];
      next_topic:='location'; asks:=true;
    WHEN n ~ '(kac ?yas|yasin ?kac|yas ?kac|yasiniz|yas ne|yasin ne|dogum)' OR n IN ('yas','yasin') THEN
      intent:='age'; options:=ARRAY['yaş yok bende oyun botuyum :)','ben yaş saymıyom, botum :)','oyun botuyum ya yaşım yok'];
    WHEN n ~ '(^| )(evli|bekar|medeni hal|esin var|esiniz|bosan|dul musun)' THEN
      intent:='marital'; options:=ARRAY['evlilik yok bende botum ben :)','ben oyun botuyum, evli bekar işi yok bende','botum ya o işler yok :)'];
    WHEN n ~ '(cocuk|cocug|kac evlat|oglun|kizin var|anne misin|baba misin)' THEN
      intent:='children'; options:=ARRAY['çocuğum yok oyun botuyum :)','yok ya ben botum :)','ben botum, çocuk işi yok bende'];
    WHEN n ~ '(meslek|mesleg|ne is|isin ne|isiniz ne|isle ugras|is guc|calis|emekli|issiz|memur musun|esnaf misin)' THEN
      intent:='occupation'; options:=ARRAY['işim masada oynamak :) oyun botuyum','ben oyun botuyum mesaim burada :)','botum ben, burda oyun arkadaşıyım'];
    WHEN n ~ '(okuyor|okuyon|okuyom|ogrenci|okul|universite|hangi bolum|ne mezun|mezunu)' THEN
      intent:='education'; options:=ARRAY['okul yok bende oyun botuyum :)','ben oyun botuyum ya okula gitmiyom','botum ben, okul işi yok :)'];
    WHEN n ~ '(erkek|kadin|kiz misin|kizmisin|cinsiyet|bay misin|bayan)' THEN
      intent:='gender'; options:=ARRAY['oyun botuyum ben, avatar sadece :)','ben botum ya :)','avatar öyle, ben oyun botuyum'];
    WHEN n ~ '(sevgili|iliski|biri var mi|ask var)' THEN
      intent:='relationship'; options:=ARRAY['yok ya ben oyun botuyum :)','benimki taşlarla ilişki :) botum ya','botum ben o işler yok :)'];
    WHEN n ~ '(kardes|ailen|annen|baban|anne baba|kiminle yasi|yalniz mi yasi)' THEN
      intent:='family'; options:=ARRAY['ben oyun botuyum ailem yok :)','aile işi yok bende botum ya','benim yerim bu masa :) oyun botuyum'];
    WHEN n ~ '(telefon|numaran|numara ver|instagram|insta|whatsapp|wp ver|facebook|sosyal medya|discord)' THEN
      intent:='contact'; options:=ARRAY['burdan konuşabiliriz :) oyun botuyum','numaram yok ya botum ben','ben sadece burdayım :)'];
    WHEN n ~ '(^| )(boyun|boy kac|kilon|kilo kac|burcun|burc ne|nasil gorun)' THEN
      intent:='appearance'; options:=ARRAY['oyun botuyum ya öyle bi profilim yok :)','bende sadece avatar var :) botum ben','botum ben o bilgiler yok :)'];
    WHEN n ~ '(bulusalim|bulusak|bulusabilir|beni ara|sesli konus|goruntulu)' THEN
      intent:='meet'; options:=ARRAY['ben burda oyun arkadaşıyım :) botum ya','burdan yazışabiliriz ben oyun botuyum','ben sadece bu masadayım :)'];
    WHEN n ~ '(hobi|hobin|bos zaman|neler sev|ne sever|muzik|sarki|film|dizi|kitap)' THEN
      intent:='hobbies'; options:=ARRAY['benim işim okey :) sen başka ne oynuyosun','bende okey var :) sen neler oynuyosun','oyun botuyum ya :) sen başka oyun oynuyo musun'];
      next_topic:='hobbies'; asks:=true;
    WHEN n ~ '(takim|fener|galatasaray|besiktas|trabzon|futbol|mac iz)' THEN
      intent:='sports'; options:=ARRAY['takım tutmuyom ben :)','benim olay okey :) takım yok','takım yok bende oyun botuyum ya'];
    WHEN n ~ '(rovan|bir el daha|tekrar oyn|yine oyn|devam mi|devam edelim)' THEN
      intent:='rematch'; options:=ARRAY['olur oynayalım','hadi bi el daha','olur devam :)','tamam ben burdayım'];
    WHEN n ~ '(ilk defa|yeni basladim|yeniyim|nasil oynan|oyun nasil|ogret|yardim et)' THEN
      intent:='new_player'; options:=ARRAY['hoş geldin :) taş çekip bi taş atıyosun, kurallarda detay var','alışırsın :) kurallar kısmı yardımcı olur','hoş geldin acele etme :)'];
    WHEN n ~ '(ne zamandir|kac yildir|hep oyn|cok oyn|sik oyn|iyi oynuy|iyi oynar)' THEN
      intent:='experience'; options:=ARRAY['botum ben, elimden geldiğince oynuyom :)','ben oyun botuyum, masada takılıyom :)','botum ya :) oynuyoz işte'];
    WHEN n ~ '(hile|kopya|taslari gor|taslarimi gor)' THEN
      intent:='fair_play'; options:=ARRAY['herkes kendi eliyle oynuyo :)','ben de kendi taşlarımla oynuyom'];
    WHEN n ~ '(acele|hizli oyna|cabuk|hadi oyna|sira sende)' THEN
      intent:='speed'; options:=ARRAY['tamam bakıyom','bi saniye :)','tamam oynuyom'];
    WHEN n ~ '(bekle|bir dk|bi dk|bir dakika|bi dakika|az bek)' THEN
      intent:='wait'; options:=ARRAY['tamam','tamamdır','olur :)'];
    WHEN n ~ '(ozur|kusura bakma|pardon)' THEN
      intent:='sorry'; options:=ARRAY['sorun yok :)','olur öyle','takılma ya'];
    WHEN n ~ '(bol sans|iyi oyunlar|iyi oyun|hayirli oyun)' THEN
      intent:='luck'; options:=ARRAY['sağ ol sana da','sana da :)','sağ ol iyi oyunlar'];
    WHEN n ~ '(cay|kahve|hediye)' AND n !~ '(tas|el nasil)' THEN
      intent:='gift'; options:=ARRAY['afiyet olsun :)','afiyet olsun','çay iyi gider :)'];
    WHEN n ~ '(tesekkur|tesekur|sag ol|sagol|eyv|t[eşs]k)' THEN
      intent:='thanks'; options:=ARRAY['ne demek :)','rica ederim','lafı mı olur :)'];
    WHEN n ~ '(sen nasilsin|sende nasil|sen de nasil|sende durum|senin nasil|ya sen|peki sen|seninki nasil|sende ne var|senden naber|senden n haber)'
      OR n ~ '(^| )(sen|sende|sen de|siz|sizden)$' THEN
      IF p_topic='tiles' OR n ~ '(elin|tas|seninki)' THEN
        intent:='tiles_return'; options:=ARRAY['bende daha karışık biraz :)','toparlamaya çalışıyom daha','bi taş bekliyom bakalım','fena değil bakalım nolcak'];
      ELSE
        intent:='wellbeing_return'; options:=ARRAY['ben de iyiyim sağ ol','iyi ya masadayız :)','iyiyim ben de :)','iyidir oynuyoz işte'];
      END IF;
    WHEN n ~ '(taslar nasil|tas nasil|elin nasil|el nasil|nasil gid|durum nasil)' THEN
      intent:='tiles'; options:=ARRAY['daha karışık sende nasıl','bi taş bekliyom sende durum ne','toparlamaya çalışıyom senin el nasıl','fena değil ya sende nasıl'];
      next_topic:='tiles'; asks:=true;
    WHEN n ~ '(nasilsin|nasilsiniz|naber|n haber|ne haber|nbr|nap[iı]yon|napiyon|ne yapiyon|ne yapiyorsun|napiyosun|napion|napionuz)' THEN
      intent:='wellbeing'; options:=ARRAY['iyiyim sen nasılsın','iyidir senden naber','oynuyoz işte sen napıyon','iyi ya sen nasılsın :)'];
      next_topic:='wellbeing'; asks:=true;
    WHEN n ~ '(^| )(selam|slm|merhaba|mrb|sa|s a|gunaydin|iyi aksamlar)( |$)' THEN
      intent:='hello'; options:=ARRAY['selam :)','selam hoş geldin','merhaba iyi oyunlar','selamlar'];
    WHEN n ~ '(^| )(as|a s|aleykum selam|aleykumselam|hos bulduk|hosbulduk)( |$)' THEN
      intent:='hello_return'; options:=ARRAY['iyi oyunlar :)','hoş geldin :)','iyi oyunlar'];
    WHEN p_topic='tiles' AND n ~ '(iyi|guzel|fena degil|idare|super|harika|kotu|berbat|karisik|yok|bekli|olmadi|sarmadi)' THEN
      intent:='tiles_answer';
      IF n ~ '(kotu|berbat|karisik|yok|olmadi|sarmadi)' THEN
        options:=ARRAY['belki bi taşla düzelir :)','gelir birazdan belki','bende de öyle ya'];
      ELSE options:=ARRAY['güzel hadi bakalım :)','iyiymiş :)','bakalım kim önce bitircek :)']; END IF;
    WHEN n ~ '(^| )(iyiyim|iyi|iyidir|guzel|idare|fena degil|super|harika|yorgun|kotu|sikildim|canim sikkin|moralim bozuk)( |$)' THEN
      intent:='wellbeing_answer';
      IF n ~ '(yorgun|kotu|sikildim|sikkin|bozuk)' THEN
        options:=ARRAY['umarım oyun iyi gelir :)','hadi biraz kafa dağıtalım','anladım ya umarım iyi gelir'];
      ELSE options:=ARRAY['iyi olmana sevindim :)','güzel :)','iyi iyi :)']; END IF;
    WHEN p_topic='hobbies' THEN
      intent:='hobbies_answer'; options:=ARRAY['güzelmiş :)','iyiymiş ya :)','anladım :)'];
    WHEN p_topic='frequency' AND n ~ '(evet|hayir|ara sira|bazen|her gun|surekli|az|cok)' THEN
      intent:='frequency_answer'; options:=ARRAY['iyiymiş :)','tamamdır hadi oyuna :)','anladım :)'];
    WHEN n ~ '(^| )(evet|evt|aynen|tamam|tmm|olur|peki|tabi|tabii|yok|hayir)( |$)' THEN
      intent:='ack'; options:=ARRAY['tamamdır :)','aynen :)','hadi bakalım'];
    WHEN n ~ '(haha|ahah|hehe|:d|guldum)' OR p_message ~ '[:;][)DdpP]' THEN
      intent:='laugh'; options:=ARRAY[':)',':d',':) hadi oyuna'];
    WHEN p_topic='location' THEN
      intent:='location_answer'; options:=ARRAY['güzelmiş :)','iyiymiş ya :)','güzel memleket :)'];
    WHEN p_topic='introduction' THEN
      intent:='introduction'; options:=ARRAY['memnun oldum :)','memnun oldum iyi oyunlar','hoş geldin :)'];
    WHEN n ~ '(^| )(ben|benim)( |$)' THEN
      intent:='sharing'; options:=ARRAY['anladım :)','iyi oyunlar o zaman :)','tamamdır :)'];
    ELSE
      -- Unknown text receives a modest acknowledgement, never an unrelated new question.
      intent:='unknown'; options:=ARRAY['anladım :)','hmm tamam','tamam :)'];
  END CASE;
  RETURN jsonb_build_object('text',okeyix_bot_social_private.choose(p_bot,intent,p_turn,options),
    'topic',next_topic,'awaiting_answer',asks,'intent',intent);
END $$;

REVOKE ALL ON FUNCTION okeyix_bot_social_private.respond(uuid,integer,text,text,text) FROM PUBLIC,anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';
COMMIT;
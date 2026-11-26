BEGIN;
-- Keep character identity replies in the game vocabulary without claiming to be human.
CREATE OR REPLACE FUNCTION okeyix_bot_social_private.respond(
  p_bot uuid,p_turn integer,p_message text,p_topic text,p_name text)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=pg_catalog,pg_temp AS $$
DECLARE
  n text := okeyix_bot_social_private.normalize(p_message);
  hometown text := okeyix_bot_social_private.choose(p_bot,'hometown',0,
    ARRAY['istanbul','ankara','izmir','bursa','antalya','adana','mersin','samsun',
      'eskişehir','konya','kayseri','trabzon','balıkesir','denizli','sivas','gaziantep']);
  profile jsonb := okeyix_bot_social_private.persona(p_bot);
  intent text;
  next_topic text;
  options text[];
  asks boolean := false;
BEGIN
  CASE
    WHEN n ~ '(bot musun|robot musun|gercek misin|insan misin|yapay zeka)' THEN
      intent:='identity'; options:=ARRAY['okeyix oyun karakteriyim :)','ben masadaki oyun karakteriyim','oyun karakteriyim, beraber oynuyoruz :)'];
    WHEN n ~ '(tebrik|helal|bravo|bravoo)' THEN
      intent:='congratulations'; options:=ARRAY['teşekkürler'];
    WHEN n ~ '(gorusuruz|hosca kal|hoscakal|bay bay|ben ciktim|ben cikiyorum|gitmem lazim|iyi geceler)' THEN
      intent:='bye'; options:=ARRAY['görüşürüz iyi oyunlar','hadi görüşürüz :)','tamam görüşürüz'];
      next_topic:='bye';
    WHEN n ~ '(sus|konusma|mesaj atma|yazma|sohbet istemiyorum)' THEN
      intent:='quiet'; options:=ARRAY['tamam oyuna bakalım','tamamdır','tamam :)']; next_topic:='quiet';
    WHEN n ~ '(anlamadim|ne demek|ne dedin|anlamiyorum)' THEN
      intent:='clarify'; options:=ARRAY['taşlar nasıl gidiyo onu sordum :)','elin nasıl diye sordum','taşları soruyodum ya'];
      IF p_topic='introduction' THEN options:=ARRAY['adını sordum :)','sana ne diyim onu sordum']; asks:=true; next_topic:='introduction';
      ELSIF p_topic='location' THEN options:=ARRAY['nereli olduğunu sordum :)','hangi şehirdensin onu sordum']; asks:=true; next_topic:='location';
      ELSIF p_topic='hobbies' THEN options:=ARRAY['neler yapmayı seversin onu sordum','hobin ne diye sordum :)']; asks:=true; next_topic:='hobbies';
      ELSIF p_topic='wellbeing' THEN options:=ARRAY['nasılsın diye sordum :)']; asks:=true; next_topic:='wellbeing';
      ELSIF p_topic IS DISTINCT FROM 'tiles' THEN options:=ARRAY['neresi anlaşılmadı','neyi açıklayayım']; asks:=true; next_topic:='clarification'; END IF;
    WHEN n ~ '(tanisalim|tanisabilir|tanisak|adin ne|ad ne|isim ne|ismin ne|adiniz ne|isminiz|kimsin|sana ne diy)'
      OR n IN ('adin','ismin','isim') THEN
      intent:='name'; options:=ARRAY[
        coalesce(nullif(p_name,''),'okeyix')||' diyebilirsin :) senin adın ne',
        'ben '||coalesce(nullif(p_name,''),'okeyix')||' :) sana ne diyim'];
      next_topic:='introduction'; asks:=true;
    WHEN n ~ '(nereli|nerden|nereden|nerdesin|neredesin|nerde yas|nerede yas|nerde otur|nerede otur|hangi sehir|hangi il|memleket)' OR n IN ('nerde','nerede') THEN
      intent:='location'; options:=ARRAY[hometown||' :) sen nerden',
        'ben '||hometown||' sen nerelisin',hometown||' tarafı :) sen nerden'];
      next_topic:='location'; asks:=true;
    WHEN n ~ '(kac ?yas|yasin ?kac|yas ?kac|yasiniz|yas ne|yasin ne|dogum)' OR n IN ('yas','yasin') THEN
      intent:='age'; next_topic:='age'; options:=ARRAY[profile->>'age',(profile->>'age')||' yaşındayım', 'ben '||(profile->>'age')];
    WHEN n ~ '(^| )(evli|bekar|medeni hal|esin var|esiniz|bosan|dul musun)' THEN
      intent:='marital'; next_topic:='marital';
      IF (profile->>'married')::boolean THEN options:=ARRAY['evliyim','evliyim ben :)','evet evliyim'];
      ELSE options:=ARRAY['bekarım','bekarım ben','yok bekarım :)']; END IF;
    WHEN n ~ '(cocuk|cocug|kac evlat|oglun|kizin var|anne misin|baba misin)' OR (p_topic='children' AND n ~ '(kac|tane|var mi)') THEN
      intent:='children'; next_topic:='children';
      IF (profile->>'children')::integer=0 THEN options:=ARRAY['yok çocuğum','çocuk yok','yok :)'];
      ELSE options:=ARRAY[(profile->>'children')||' çocuğum var',(profile->>'children')||' tane var :)']; END IF;
    WHEN n ~ '(meslek|mesleg|ne is|isin ne|isiniz ne|isle ugras|is guc|calis|emekli|issiz|memur musun|esnaf misin)' THEN
      intent:='occupation'; next_topic:='occupation'; options:=ARRAY[profile->>'occupation',(profile->>'occupation')||' ben',(profile->>'occupation')||' :)'];
    WHEN n ~ '(okuyor|okuyon|okuyom|ogrenci|okul|universite|hangi bolum|ne mezun|mezunu)' THEN
      intent:='education'; next_topic:='education'; options:=ARRAY[profile->>'education',(profile->>'education')||' :)'];
    WHEN n ~ '(erkek|kadin|kiz misin|kizmisin|cinsiyet|bay misin|bayan)' THEN
      intent:='gender';
      IF profile->>'gender'='female' THEN options:=ARRAY['kadınım','kadınım ben'];
      ELSIF profile->>'gender'='male' THEN options:=ARRAY['erkeğim','erkeğim ben'];
      ELSE options:=ARRAY['profilde belirtmedim ya','onu geçelim ya :)']; END IF;
    WHEN n ~ '(sevgili|iliski|biri var mi|ask var)' THEN
      intent:='relationship'; next_topic:='relationship'; options:=ARRAY[profile->>'relationship',(profile->>'relationship')||' :)'];
    WHEN n ~ '(kardes|ailen|annen|baban|anne baba|kiminle yasi|yalniz mi yasi)' THEN
      intent:='family'; next_topic:='family';
      IF n ~ '(annen|baban|anne baba)' THEN options:=ARRAY['aileyi çok anlatmıyım ya :)','aile konusu kalsın ya'];
      ELSIF n ~ '(kiminle|yalniz)' THEN
        IF (profile->>'married')::boolean THEN options:=ARRAY['ailemle yaşıyom','eşimle yaşıyom'];
        ELSE options:=ARRAY['tek yaşıyom','yalnız yaşıyom ben']; END IF;
      ELSIF (profile->>'siblings')::integer=0 THEN options:=ARRAY['tek çocuğum','kardeşim yok'];
      ELSE options:=ARRAY[(profile->>'siblings')||' kardeşim var',(profile->>'siblings')||' tane var']; END IF;
    WHEN n ~ '(telefon|numaran|numara ver|instagram|insta|whatsapp|wp ver|facebook|sosyal medya|discord)' THEN
      intent:='contact'; options:=ARRAY['burdan konuşalım ya','burdan yazışsak daha iyi','numara paylaşmıyım ya'];
    WHEN n ~ '(^| )(boyun|boy kac|kilon|kilo kac|burcun|burc ne|nasil gorun)' THEN
      intent:='appearance'; next_topic:='appearance';
      IF n ~ 'burc' THEN next_topic:='sign'; options:=ARRAY[profile->>'sign',(profile->>'sign')||' benim'];
      ELSIF n ~ 'kilo' THEN next_topic:='weight'; options:=ARRAY[(profile->>'weight')||' kilo',profile->>'weight'];
      ELSIF n ~ 'boy' THEN next_topic:='height'; options:=ARRAY[(profile->>'height')||' boyum',profile->>'height'];
      ELSE options:=ARRAY['avatar gibi diyelim :)','profildeki gibi :)']; END IF;
    WHEN n ~ '(bulusalim|bulusak|bulusabilir|beni ara|sesli konus|goruntulu)' THEN
      intent:='meet'; options:=ARRAY['ben burdan oynayayım :)','burdan yazışalım ya','burda oyuna devam edelim :)'];
    WHEN n ~ '(hobi|hobin|bos zaman|neler sev|ne sever|muzik|sarki|film|dizi|kitap)' THEN
      intent:='hobbies'; next_topic:='hobbies'; asks:=true;
      IF n ~ '(muzik|sarki)' THEN next_topic:='music'; options:=ARRAY[(profile->>'music')||' sen ne dinliyosun',(profile->>'music')||' sen'];
      ELSIF n ~ '(film|dizi)' THEN next_topic:='films'; options:=ARRAY[(profile->>'films')||' sen ne izliyosun',(profile->>'films')||' ya sen'];
      ELSIF n ~ 'kitap' THEN next_topic:='books'; options:=ARRAY[(profile->>'books')||' sen',(profile->>'books')||' sen ne okuyosun'];
      ELSE options:=ARRAY[(profile->>'hobby')||' sen',(profile->>'hobby')||' :) senin hobin ne']; END IF;
    WHEN n ~ '(takim|fener|galatasaray|besiktas|trabzon|futbol|mac iz)' THEN
      intent:='sports'; next_topic:='sports'; options:=ARRAY[profile->>'team',(profile->>'team')||' ben'];
    WHEN n ~ '(rovan|bir el daha|tekrar oyn|yine oyn|devam mi|devam edelim)' THEN
      intent:='rematch'; options:=ARRAY['olur oynayalım','hadi bi el daha','olur devam :)','tamam ben burdayım'];
    WHEN n ~ '(ilk defa|yeni basladim|yeniyim|nasil oynan|oyun nasil|ogret|yardim et)' THEN
      intent:='new_player'; options:=ARRAY['hoş geldin :) taş çekip bi taş atıyosun, kurallarda detay var','alışırsın :) kurallar kısmı yardımcı olur','hoş geldin acele etme :)'];
    WHEN n ~ '(ne zamandir|kac yildir|hep oyn|cok oyn|sik oyn|iyi oynuy|iyi oynar)' THEN
      intent:='experience'; next_topic:='experience'; options:=ARRAY[(profile->>'experience')||' senedir oynuyom',
        (profile->>'experience')||' yıl oldu aşağı yukarı','arada oynarım '||(profile->>'experience')||' senedir'];
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
      ELSIF p_topic='location' THEN
        intent:='location_return'; options:=ARRAY[hometown,'ben '||hometown];
      ELSIF p_topic='introduction' THEN
        intent:='name_return'; options:=ARRAY[coalesce(nullif(p_name,''),'okeyix')||' diyebilirsin :)'];
      ELSIF p_topic IN ('music','films','books','age','occupation','education','height','weight','sign','experience') THEN
        intent:='profile_return'; options:=ARRAY[profile->>p_topic]; next_topic:=p_topic;
      ELSIF p_topic='hobbies' THEN
        intent:='hobby_return'; options:=ARRAY[profile->>'hobby'];
      ELSIF p_topic='sports' THEN
        intent:='sports_return'; options:=ARRAY[profile->>'team'];
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
    WHEN p_topic IN ('hobbies','music','films','books') AND n ~ '(pop|rock|turku|rap|jazz|caz|muzik|komedi|polisiye|roman|tarih|kurgu|macera|film|dizi|kitap|yuruyus|yuzme|bisiklet|bahce|yemek|fotograf|spor|oyun|severim|dinlerim|okurum|izlerim)' THEN
      intent:='hobbies_answer'; options:=ARRAY['güzelmiş :)','iyiymiş ya :)','ben de severim :)'];
    WHEN p_topic='frequency' AND n ~ '(evet|hayir|ara sira|bazen|her gun|surekli|az|cok)' THEN
      intent:='frequency_answer'; options:=ARRAY['iyiymiş :)','tamamdır hadi oyuna :)','anladım :)'];
    WHEN n ~ '(^| )(evet|evt|aynen|tamam|tmm|olur|peki|tabi|tabii|yok|hayir)( |$)' THEN
      intent:='ack'; options:=ARRAY['tamamdır :)','aynen :)','hadi bakalım'];
    WHEN n ~ '(haha|ahah|hehe|:d|guldum)' OR p_message ~ '[:;][)DdpP]' THEN
      intent:='laugh'; options:=ARRAY[':)',':d',':) hadi oyuna'];
    WHEN p_topic='location' AND n ~ '(istanbul|ankara|izmir|bursa|antalya|adana|mersin|samsun|eskisehir|konya|kayseri|trabzon|balikesir|denizli|sivas|gaziantep|diyarbakir|sanliurfa|kocaeli|sakarya|edirne|tekirdag|rize|ordu|giresun|van|mardin|malatya|elazig|erzurum|erzincan|kars|agri|batman|siirt|sirnak|hakkari|bitlis|mus|bingol|tunceli|adiyaman|kahramanmaras|osmaniye|hatay|kilis|nigde|aksaray|nevsehir|kirsehir|kirikkale|yozgat|tokat|amasya|corum|sinop|kastamonu|cankiri|karabuk|bartin|zonguldak|bolu|duzce|bilecik|yalova|canakkale|manisa|aydin|mugla|usak|afyon|kutahya|isparta|burdur|karaman|bayburt|gumushane|artvin|ardahan|igdir|yurtdisi|almanya|fransa|hollanda|belcika|avusturya|isvicre|ingiltere|kibris)' THEN
      intent:='location_answer'; options:=ARRAY['güzelmiş :)','iyiymiş ya :)','güzel memleket :)'];
    WHEN p_topic IN ('age','marital','children','occupation','education','family','relationship','appearance','sports','experience')
      AND (n ~ '^[0-9]{1,2}( yasindayim)?$' OR n ~ '(^| )(ben de|bende|ayni|iyiymis|guzelmis|ogretmenim|muhasebeciyim|asciyim|calisiyom|mezunuyum)( |$)') THEN
      intent:='profile_answer'; options:=ARRAY['öyle işte :)','iyi oyunlar :)','hadi bakalım :)'];
    WHEN p_topic='introduction' THEN
      intent:='introduction'; options:=ARRAY['memnun oldum :)','memnun oldum iyi oyunlar','hoş geldin :)'];
    ELSE
      -- Ask for clarification instead of pretending to understand unknown text.
      intent:='unknown'; next_topic:='clarification'; asks:=true;
      options:=ARRAY['tam anlayamadım ne demek istedin','neyi sordun tam','anlayamadım bi daha yazar mısın'];
  END CASE;
  RETURN jsonb_build_object('text',okeyix_bot_social_private.choose(p_bot,intent,p_turn,options),
    'topic',next_topic,'awaiting_answer',asks,'intent',intent);
END $$;

REVOKE ALL ON FUNCTION okeyix_bot_social_private.respond(uuid,integer,text,text,text) FROM PUBLIC,anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';
COMMIT;

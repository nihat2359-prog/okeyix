BEGIN;

ALTER TABLE public.okeyix_bot_social_state
  ADD COLUMN play_started_at timestamptz,
  ADD COLUMN greeting_due_at timestamptz,
  ADD COLUMN tea_due_at timestamptz,
  ADD COLUMN question_due_at timestamptz,
  ADD COLUMN finish_seen_at timestamptz,
  ADD COLUMN finish_due_at timestamptz,
  ADD COLUMN pending_message_id uuid,
  ADD COLUMN pending_due_at timestamptz,
  ADD COLUMN topic text,
  ADD COLUMN awaiting_answer boolean NOT NULL DEFAULT false,
  ADD COLUMN engaged boolean NOT NULL DEFAULT false,
  ADD COLUMN reply_count integer NOT NULL DEFAULT 0;

-- These helpers have no client RPC access and never read private player data.
CREATE SCHEMA IF NOT EXISTS okeyix_bot_social_private;
REVOKE ALL ON SCHEMA okeyix_bot_social_private FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION okeyix_bot_social_private.normalize(p_text text) RETURNS text
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog,pg_temp AS $$
DECLARE n text; spelling record;
BEGIN
  n:=trim(regexp_replace(
    lower(translate(coalesce(p_text,''),'İIıŞşĞğÜüÖöÇç','iiissgguuoocc')),
    '[[:space:][:punct:]]+',' ','g'));
  -- Common chat spellings only: no fuzzy match that turns unrelated words into personal questions.
  FOR spelling IN SELECT * FROM (VALUES
    ('\m(nrdn|nrden|nerdn|nerdenn)\M','nerden'),
    ('\m(nrdesin|nerdesn|nerdesinn)\M','nerdesin'),
    ('\m(nerelisinz|nerelsin)\M','nerelisin'),
    ('\m(kc|kacc|kaccc)\M','kac'),
    ('\m(yass|yaas|yasiniz)\M','yas'),
    ('\m(meslk|mesleg|meslek)\M','meslek'),
    ('\m(ewli|evlii)\M','evli'),
    ('\m(bekarr|bekr)\M','bekar'),
    ('\m(cocug|cocugun|cocuun|cocugunuz)\M','cocugun'),
    ('\m(calisiyomusun|calisiyonmu|calisiyomusn)\M','calisiyor musun'),
    ('\m(okuyonmu|okuyomusun)\M','okuyor musun'),
    ('\m(nsl|naslsin|nasilsn|nasilsinn)\M','nasilsin'),
    ('\m(nbr|naberler)\M','naber'),
    ('\m(slm|selaam|selamm)\M','selam'),
    ('\m(mrb|meraba|merhabaa)\M','merhaba'),
    ('\m(tesekur|tesekkurler|tesekkurrr|tsk|tşk)\M','tesekkur'),
    ('\m(snde|sendde)\M','sende'),
    ('\m(snn|senn)\M','sen'),
    ('\m(ii|iyim|iyym|iiyim)\M','iyiyim')
  ) AS v(pattern,replacement) LOOP
    n:=regexp_replace(n,spelling.pattern,spelling.replacement,'g');
  END LOOP;
  RETURN n;
END;
$$;

CREATE FUNCTION okeyix_bot_social_private.choose(p_bot uuid,p_key text,p_turn integer,p_options text[])
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,pg_temp AS $$
  SELECT p_options[1+((hashtextextended(p_bot::text||':'||p_key,0) & 2147483647)
    +p_turn::bigint)%cardinality(p_options)::bigint];
$$;

-- The topic describes the bot's last question, so short answers retain meaning.
-- Profile questions disclose the game bot identity instead of inventing a human biography.
CREATE FUNCTION okeyix_bot_social_private.respond(
  p_bot uuid,p_turn integer,p_message text,p_topic text,p_name text)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog,pg_temp AS $$
DECLARE
  n text := okeyix_bot_social_private.normalize(p_message);
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
      intent:='location'; options:=ARRAY['benim memleket masa :) oyun botuyum','ben okeyix tarafındayım, botum ya :)','şehir yok bende, oyun botuyum :)'];
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

CREATE OR REPLACE FUNCTION public.okeyix_bot_social_tick(p_table_id uuid,p_closed_finish_at timestamptz DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE
  t public.tables%ROWTYPE;
  human public.table_players%ROWTYPE;
  bot public.table_players%ROWTYPE;
  s public.okeyix_bot_social_state%ROWTYPE;
  msg public.table_messages%ROWTYPE;
  previous_message public.table_messages%ROWTYPE;
  gift public.okeyix_gift_catalog%ROWTYPE;
  wallet_id uuid;
  purchase_seq bigint;
  moment timestamptz:=clock_timestamp();
  answer jsonb;
  bot_name text;
BEGIN
  IF auth.uid() IS NULL THEN RETURN; END IF;
  SELECT * INTO t FROM public.tables WHERE id=p_table_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  SELECT p.* INTO human FROM public.table_players p JOIN public.users u ON u.id=p.user_id
    WHERE p.table_id=t.id AND p.user_id=auth.uid() AND NOT u.is_bot;
  IF NOT FOUND THEN RETURN; END IF;
  SELECT p.* INTO bot FROM public.table_players p JOIN public.users u ON u.id=p.user_id
    WHERE p.table_id=t.id AND u.is_bot ORDER BY p.seat_index LIMIT 1;
  IF NOT FOUND THEN RETURN; END IF;
  INSERT INTO public.okeyix_bot_social_state(membership_id,bot_membership_id)
    VALUES(human.id,bot.id) ON CONFLICT DO NOTHING;
  SELECT * INTO s FROM public.okeyix_bot_social_state WHERE membership_id=human.id FOR UPDATE;
  IF s.bot_membership_id<>bot.id THEN RETURN; END IF;
  -- Waiting at a table must not eat the opening delay before the game starts.
  IF t.status='playing' AND s.play_started_at IS NULL THEN
    UPDATE public.okeyix_bot_social_state SET play_started_at=moment,
      greeting_due_at=moment+make_interval(secs=>5+floor(random()*5)::integer),
      tea_due_at=moment+make_interval(secs=>14+floor(random()*5)::integer),
      question_due_at=moment+make_interval(secs=>50+floor(random()*26)::integer)
      WHERE membership_id=human.id RETURNING * INTO s;
  END IF;
  IF t.status='playing' AND NOT s.greeted AND t.chat_enabled AND moment>=s.greeting_due_at THEN
    INSERT INTO public.table_messages(table_id,sender_id,role,type,content)
      VALUES(t.id,bot.user_id,'player','text','Bol şans');
    UPDATE public.okeyix_bot_social_state SET greeted=true,last_reply_at=moment,
      tea_due_at=moment+make_interval(secs=>5+floor(random()*5)::integer)
      WHERE membership_id=human.id;
    RETURN;
  END IF;
  IF t.status='playing' AND t.max_players=2 AND NOT s.tea_sent AND moment>=s.tea_due_at
      AND (SELECT count(*) FROM public.table_players WHERE table_id=t.id)=2 THEN
    SELECT * INTO gift FROM public.okeyix_gift_catalog WHERE id='cay' AND enabled;
    IF FOUND THEN
      UPDATE public.profiles SET coins=coins-gift.price WHERE id=bot.user_id AND coins>=gift.price;
      IF FOUND THEN
        INSERT INTO public.wallet_transactions(user_id,amount,reason,type,store,note)
          VALUES(bot.user_id,-gift.price,'table_gift','debit','system','cay') RETURNING id INTO wallet_id;
        INSERT INTO public.okeyix_table_gift_purchases(request_id,table_id,sender_id,recipient_id,gift_id,price,wallet_transaction_id)
          VALUES(gen_random_uuid(),t.id,bot.user_id,human.user_id,'cay',gift.price,wallet_id) RETURNING seq INTO purchase_seq;
        INSERT INTO public.okeyix_table_last_gifts(table_id,user_id,membership_id,purchase_seq,gift_id)
          VALUES(t.id,human.user_id,human.id,purchase_seq,'cay')
          ON CONFLICT(table_id,user_id) DO UPDATE SET membership_id=excluded.membership_id,
            purchase_seq=excluded.purchase_seq,gift_id=excluded.gift_id;
        UPDATE public.okeyix_bot_social_state SET tea_sent=true WHERE membership_id=human.id;
        -- A gift and a conversation response are never fired by the same tick.
        RETURN;
      END IF;
    END IF;
  END IF;
  IF NOT t.chat_enabled OR s.play_started_at IS NULL OR NOT s.greeted THEN RETURN; END IF;
  IF t.last_winner_user_id=human.user_id AND t.last_finish_at=p_closed_finish_at
      AND t.last_finish_at>=s.started_at AND s.congratulated_at IS DISTINCT FROM t.last_finish_at THEN
    IF s.finish_seen_at IS DISTINCT FROM t.last_finish_at THEN
      UPDATE public.okeyix_bot_social_state SET finish_seen_at=t.last_finish_at,
        finish_due_at=moment+make_interval(secs=>3+floor(random()*4)::integer) WHERE membership_id=human.id;
      RETURN;
    END IF;
    IF moment>=s.finish_due_at AND moment>=t.last_finish_at+interval '4 seconds' THEN
      INSERT INTO public.table_messages(table_id,sender_id,role,type,content)
        VALUES(t.id,bot.user_id,'player','text','Tebrikler');
      UPDATE public.okeyix_bot_social_state SET congratulated_at=t.last_finish_at,last_reply_at=moment
        WHERE membership_id=human.id;
      RETURN;
    END IF;
  END IF;
  -- Acknowledge only the most recent message in a burst. Seeing newer text resets
  -- the reading/typing delay; no older message is answered while a newer one waits.
  SELECT * INTO previous_message FROM public.table_messages WHERE id=s.last_message_id;
  SELECT * INTO msg FROM public.table_messages WHERE table_id=t.id AND sender_id=human.user_id
    AND role='player' AND type='text' AND created_at>s.started_at
    AND created_at>moment-interval '2 minutes'
    AND (previous_message.id IS NULL OR (created_at,id)>(previous_message.created_at,previous_message.id))
    ORDER BY created_at DESC,id DESC LIMIT 1;
  IF FOUND THEN
    IF s.pending_message_id IS DISTINCT FROM msg.id THEN
      UPDATE public.okeyix_bot_social_state SET pending_message_id=msg.id,
        pending_due_at=moment+make_interval(secs=>5+floor(random()*6)::integer)
        WHERE membership_id=human.id;
      RETURN;
    END IF;
    IF moment<s.pending_due_at OR moment<coalesce(s.last_reply_at,s.started_at)+interval '6 seconds' THEN RETURN; END IF;
    SELECT username INTO bot_name FROM public.users WHERE id=bot.user_id;
    answer:=okeyix_bot_social_private.respond(bot.user_id,s.reply_count,msg.content,s.topic,bot_name);
    INSERT INTO public.table_messages(table_id,sender_id,role,type,content)
      VALUES(t.id,bot.user_id,'player','text',answer->>'text');
    UPDATE public.okeyix_bot_social_state SET last_reply_at=moment,last_message_id=msg.id,
      pending_message_id=NULL,pending_due_at=NULL,topic=answer->>'topic',
      awaiting_answer=(answer->>'awaiting_answer')::boolean,engaged=true,reply_count=reply_count+1
      WHERE membership_id=human.id;
    RETURN;
  END IF;
  IF s.pending_message_id IS NOT NULL THEN
    UPDATE public.okeyix_bot_social_state SET pending_message_id=NULL,pending_due_at=NULL WHERE membership_id=human.id;
  END IF;
  -- One gentle question is allowed only after the human has engaged. An
  -- unanswered question, goodbye, or request for quiet never gets a follow-up.
  IF t.status='playing' AND s.greeted AND s.engaged AND NOT s.asked AND NOT s.awaiting_answer
      AND coalesce(s.topic,'') NOT IN ('bye','quiet') AND moment>=s.question_due_at
      AND moment>=s.last_reply_at+interval '25 seconds'
      AND NOT EXISTS(SELECT 1 FROM public.table_messages WHERE table_id=t.id AND created_at>moment-interval '20 seconds') THEN
    INSERT INTO public.table_messages(table_id,sender_id,role,type,content)
      VALUES(t.id,bot.user_id,'player','text',okeyix_bot_social_private.choose(bot.user_id,'question',s.reply_count,
        ARRAY['nasıl gidiyo taşlar iyi mi','taşlar nasıl sende','el nasıl gidiyo','geliyo mu beklediğin taşlar']));
    UPDATE public.okeyix_bot_social_state SET asked=true,awaiting_answer=true,topic='tiles',last_reply_at=moment
      WHERE membership_id=human.id;
  END IF;
END $$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA okeyix_bot_social_private FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.okeyix_bot_social_tick(uuid,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.okeyix_bot_social_tick(uuid,timestamptz) TO authenticated;
NOTIFY pgrst,'reload schema';
COMMIT;

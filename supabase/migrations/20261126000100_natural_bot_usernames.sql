-- Rename every bot-only identity, including the original and expanded pools.
-- Run as postgres. Auth identities are excluded even if incorrectly marked bot.
-- Only usernames change; balances, ratings, avatars and bot badges are preserved.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $rename$
DECLARE
  nicknames text[] := ARRAY[
    'MaviBoncuk','GeceKuşu','Kral34','Çaycı','SonTaş','Şanslı','GülKurusu',
    'KaraKedi','SarıLimon','DenizKızı','YorgunKaptan','DeliDolu','GönülDostu',
    'BirUmut','Papatya','SessizAdam','TatlıBela','KırÇiçeği','İnceElek',
    'UstaOyuncu','YolArkadaşı','EgeRüzgarı','AkşamSefası','ÇakılTaşı',
    'FındıkKurdu','Mahalleli','DemliÇay','Gurbetçi','KüçükHanım','Neşeli',
    'BoşKoltuk','İkiÇift','SonEl','Kısmet','Hayalperest','Yıldız',
    'Maviş','Kaptan','Güneş','Uykusuz'];
  first_names text[] := ARRAY[
    'Ahmet','Merve','Burak','Zeynep','Emre','Elif','Murat','Selin',
    'Mustafa','Ayşe','Mehmet','Derya','Ali','Ece','Hasan','Ceren',
    'Hüseyin','Seda','Can','Esra','Kerem','Bahar','Mert','Pelin',
    'Onur','Deniz','Arda','Aylin','Hakan','Özge','Serkan','Gizem',
    'Uğur','İrem','Fatih','Büşra','Oğuz','Tuğçe','Yusuf','Gamze'];
  lower_names text[] := ARRAY[
    'ahmet','merve','burak','zeynep','emre','elif','murat','selin',
    'mustafa','ayşe','mehmet','derya','ali','ece','hasan','ceren',
    'hüseyin','seda','can','esra','kerem','bahar','mert','pelin',
    'onur','deniz','arda','aylin','hakan','özge','serkan','gizem',
    'uğur','irem','fatih','büşra','oğuz','tuğçe','yusuf','gamze'];
  surnames text[] := ARRAY[
    'Yılmaz','Kaya','Demir','Çelik','Şahin','Yıldız','Yıldırım','Aydın',
    'Arslan','Doğan','Kılıç','Aslan','Çetin','Kara','Koç','Kurt',
    'Özdemir','Şimşek','Polat','Güneş','Yalçın','Aksoy','Tekin','Öztürk',
    'Acar','Bulut','Taş','Eren','Avcı','Duman'];
  cities text[] := ARRAY['ist','ank','izmir','bursa','antalya','adana','mersin','samsun'];
  left_marks text[] := ARRAY['★','ツ','•','♡','✿','彡','☆','ღ','✦','『'];
  right_marks text[] := ARRAY['★','ツ','•','♡','✿','彡','☆','ღ','✦','』'];
  bot record;
  total integer;
  nick_count integer;
  lower_end integer;
  decorated_end integer;
  name_category integer;
  counters integer[] := ARRAY[0,0,0,0];
  candidate text;
  k integer;
  cycle integer;
BEGIN
  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION 'BOT_NAMES_POSTGRES_REQUIRED';
  END IF;
  LOCK TABLE public.users, public.profiles IN SHARE ROW EXCLUSIVE MODE;
  CREATE TEMP TABLE bot_name_plan(
    id uuid PRIMARY KEY, position integer, category integer, username text,
    UNIQUE(username)
  ) ON COMMIT DROP;
  INSERT INTO bot_name_plan(id,position)
  SELECT u.id,row_number() OVER (ORDER BY md5(u.id::text),u.id)::integer
  FROM public.users u WHERE u.is_bot
    AND NOT EXISTS(SELECT 1 FROM auth.users a WHERE a.id=u.id);
  SELECT count(*) INTO total FROM bot_name_plan;
  nick_count := round(total * .4);
  lower_end := round(total * .7);
  decorated_end := round(total * .9);

  FOR bot IN SELECT * FROM bot_name_plan ORDER BY position LOOP
    name_category := CASE WHEN bot.position<=nick_count THEN 1
      WHEN bot.position<=lower_end THEN 2
      WHEN bot.position<=decorated_end THEN 3 ELSE 4 END;
    LOOP
      k := counters[name_category];
      counters[name_category] := k+1;
      IF k>=10000 THEN RAISE EXCEPTION 'BOT_NAMES_POOL_EXHAUSTED'; END IF;
      cycle := k/40;
      candidate := CASE name_category
        WHEN 1 THEN nicknames[1+k%40] || CASE WHEN cycle=0 THEN ''
          ELSE lpad(cycle::text,2,'0') END
        WHEN 2 THEN lower_names[1+k%40] || CASE
          WHEN cycle=0 THEN CASE k%3 WHEN 0 THEN '34'
            WHEN 1 THEN '_'||cities[1+k%8] ELSE '' END
          WHEN cycle<=81 THEN lpad(cycle::text,2,'0')
          ELSE '_'||cities[1+(cycle-82)%8] END
        WHEN 3 THEN left_marks[1+(cycle+k*3)%10] || nicknames[1+k%40]
          || CASE WHEN cycle<10 THEN '' ELSE (cycle/10)::text END
          || right_marks[1+(cycle+k*3)%10]
        WHEN 4 THEN first_names[1+k%40] || ' ' || surnames[1+(cycle+k*7)%30]
      END;
      EXIT WHEN NOT EXISTS(SELECT 1 FROM public.users u
          WHERE lower(btrim(u.username))=lower(candidate)
            AND NOT EXISTS(SELECT 1 FROM bot_name_plan p WHERE p.id=u.id))
        AND NOT EXISTS(SELECT 1 FROM bot_name_plan p
          WHERE lower(p.username)=lower(candidate));
    END LOOP;
    UPDATE bot_name_plan p SET username=candidate, category=name_category
      WHERE p.id=bot.id;
  END LOOP;

  -- Vacate old names first so immediate unique indexes allow name swaps.
  -- Abort on a staging collision rather than modifying any other identity.
  IF EXISTS(SELECT 1 FROM public.users u JOIN bot_name_plan p
    ON lower(btrim(u.username))='ox_'||substr(md5(p.id::text),1,20)) THEN
    RAISE EXCEPTION 'BOT_NAMES_STAGING_COLLISION';
  END IF;
  UPDATE public.users u SET username='ox_'||substr(md5(u.id::text),1,20)
    FROM bot_name_plan p WHERE p.id=u.id;
  IF EXISTS(SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='profiles' AND column_name='username') THEN
    EXECUTE 'UPDATE public.profiles p SET username=''ox_''||substr(md5(p.id::text),1,20)
      FROM bot_name_plan n WHERE n.id=p.id';
  END IF;
  UPDATE public.users u SET username=p.username FROM bot_name_plan p WHERE p.id=u.id;
  IF EXISTS(SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='profiles' AND column_name='username') THEN
    EXECUTE 'UPDATE public.profiles p SET username=n.username
      FROM bot_name_plan n WHERE n.id=p.id';
  END IF;
  RAISE NOTICE 'Renamed % bots: % nicknames, % lowercase, % decorated, % full names.',
    total,nick_count,lower_end-nick_count,decorated_end-lower_end,total-decorated_end;
END
$rename$;
COMMIT;

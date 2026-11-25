-- Adds 150 bot-only public identities; never creates Auth accounts.
-- Run as postgres after 20261021000400_bot_wallet_reserve.sql.
-- Does not call replenish/maintainer, alter policies, or touch existing bots.
-- Fixed IDs make a complete rerun a no-op, preserving played balances/ratings.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';

DO $seed$
DECLARE
  male_names text[] := ARRAY['Emre','Murat','Ahmet','Mehmet','Mustafa','Ali','Hasan','Hüseyin','İbrahim','Yusuf','Ömer','Osman','Burak','Can','Cem','Cenk','Kerem','Kaan','Arda','Berk','Berkay','Mert','Onur','Oğuz','Oğuzhan','Serkan','Hakan','Volkan','Tolga','Tolgahan','Uğur','Umut','Eren','Enes','Furkan','Batuhan','Barış','Çağrı','Çağatay','Alper','Alperen','Anıl','Atakan','Ayberk','Aykut','Bora','Buğra','Doğukan','Eray','Erdem','Ersin','Fatih','Gökhan','Göktuğ','Halil','İlker','İsmail','Koray','Levent','Mesut','Metin','Okan','Orhan','Selçuk','Sinan','Şahin','Taner','Tarık','Tayfun','Tuncay','Utku','Yasin','Yiğit','Zafer','Süleyman'];
  female_names text[] := ARRAY['Selin','Zeynep','Ayşe','Fatma','Emine','Hatice','Elif','Merve','Büşra','Esra','Kübra','Seda','Selen','Ceren','Ece','Ecem','İrem','İpek','Derya','Deniz','Dilan','Dilara','Duygu','Damla','Defne','Ada','Aslı','Aslıhan','Aylin','Ayça','Aysel','Aysu','Bahar','Banu','Başak','Begüm','Beril','Berrin','Betül','Beyza','Burcu','Cansu','Çağla','Çiğdem','Dicle','Dilek','Ebru','Eda','Efsun','Ezgi','Feyza','Fulya','Gamze','Gizem','Gonca','Gözde','Gül','Gülay','Gülsüm','Hande','Hilal','Hülya','Jale','Melis','Meltem','Nazlı','Neslihan','Nihan','Nilay','Nur','Özge','Pelin','Pınar','Sinem','Tuğçe'];
  initials text[] := ARRAY['K','Y','T','A','B','Ç','D','E','G','İ','M','Ö','S','Ş','U'];
  male_avatars integer[] := ARRAY[8,11,10,2,3,1,9,4,14,16,23,24];
  female_avatars integer[] := ARRAY[13,6,7,12,15,5,17,18,19,20,21,22];
  batch_ids uuid[];
  existing integer;
  maximum bigint;
  reserve numeric;
  coin_amount integer;
  initial_coins integer;
  bot_id uuid;
  bot_name text;
  avatar_ref text;
  bot_rating integer;
  payload jsonb;
  relation_name text;
  columns_sql text;
  values_sql text;
  updates_sql text;
  i integer;
BEGIN
  IF current_user <> 'postgres' THEN RAISE EXCEPTION 'BOT_POOL_POSTGRES_REQUIRED'; END IF;
  IF to_regclass('okeyix_bot_wallet_private.registry') IS NULL
    OR to_regclass('okeyix_bot_wallet_private.policy') IS NULL
    OR to_regclass('okeyix_bot_wallet_private.topups') IS NULL
    OR to_regprocedure('okeyix_bot_wallet_private.trusted()') IS NULL THEN
    RAISE EXCEPTION 'BOT_POOL_WALLET_MIGRATION_REQUIRED';
  END IF;
  IF NOT okeyix_bot_wallet_private.trusted() THEN
    RAISE EXCEPTION 'BOT_POOL_TRUSTED_SESSION_REQUIRED';
  END IF;
  -- Serialize this seed and exclude concurrent identity/profile changes.
  -- No trigger, RLS policy or constraint is disabled.
  PERFORM pg_advisory_xact_lock(hashtextextended('okeyix-bot-pool-20261125',0));
  LOCK TABLE public.users, public.profiles,
    okeyix_bot_wallet_private.registry, okeyix_bot_wallet_private.topups
    IN SHARE ROW EXCLUSIVE MODE;
  IF NOT EXISTS(SELECT 1 FROM pg_trigger
    WHERE tgrelid='public.users'::regclass AND tgname='okeyix_bot_identity_register'
      AND tgenabled IN ('O','A') AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'BOT_POOL_REGISTRATION_TRIGGER_REQUIRED';
  END IF;
  -- Core columns are mandatory. Optional legacy presentation columns are
  -- populated only when present; all other columns keep their actual defaults.
  IF EXISTS(
    SELECT 1 FROM (VALUES
      ('users','id'),('users','username'),('users','avatar_url'),('users','is_bot'),
      ('profiles','id'),('profiles','rating'),('profiles','coins')
    ) required_columns(relation_name,column_name)
    WHERE NOT EXISTS(SELECT 1 FROM information_schema.columns c
      WHERE c.table_schema='public' AND c.table_name=required_columns.relation_name
        AND c.column_name=required_columns.column_name)
  ) THEN RAISE EXCEPTION 'BOT_POOL_CORE_COLUMNS_MISSING'; END IF;

  SELECT array_agg(('b0251125-0150-4000-8000-'||lpad(n::text,12,'0'))::uuid ORDER BY n)
    INTO batch_ids FROM generate_series(1,150) n;
  IF EXISTS(SELECT 1 FROM auth.users WHERE id=ANY(batch_ids)) THEN
    RAISE EXCEPTION 'BOT_POOL_AUTH_ID_COLLISION';
  END IF;
  SELECT count(*) INTO existing FROM public.users WHERE id=ANY(batch_ids);
  IF existing=150 THEN
    IF EXISTS(
      SELECT 1 FROM generate_series(1,150) n
      JOIN public.users u ON u.id=batch_ids[n]
      WHERE NOT u.is_bot OR u.username IS DISTINCT FROM
        (CASE WHEN n<=75 THEN male_names[n] ELSE female_names[n-75] END
          ||' '||initials[1+((n-1)%15)]||'.')
        OR NOT EXISTS(SELECT 1 FROM public.profiles p WHERE p.id=u.id)
        OR NOT EXISTS(SELECT 1 FROM okeyix_bot_wallet_private.registry r WHERE r.user_id=u.id)
    ) THEN RAISE EXCEPTION 'BOT_POOL_EXISTING_BATCH_MISMATCH'; END IF;
    RAISE NOTICE 'Bot pool already installed; no rows changed.';
    RETURN;
  END IF;
  IF existing<>0 OR EXISTS(SELECT 1 FROM public.profiles WHERE id=ANY(batch_ids))
    OR EXISTS(SELECT 1 FROM okeyix_bot_wallet_private.registry WHERE user_id=ANY(batch_ids))
    OR EXISTS(SELECT 1 FROM okeyix_bot_wallet_private.topups WHERE user_id=ANY(batch_ids)) THEN
    RAISE EXCEPTION 'BOT_POOL_ID_COLLISION_OR_PARTIAL_BATCH';
  END IF;
  IF EXISTS(
    SELECT 1 FROM generate_series(1,150) n JOIN public.users u
      ON lower(btrim(u.username))=lower(
        CASE WHEN n<=75 THEN male_names[n] ELSE female_names[n-75] END
          ||' '||initials[1+((n-1)%15)]||'.')
  ) THEN RAISE EXCEPTION 'BOT_POOL_PLAYER_NAME_COLLISION'; END IF;

  -- Match the existing reserve economics. Lower initial balances would be
  -- replaced by the next watchdog. No existing wallet is replenished here.
  SELECT max(max_coin) INTO maximum FROM public.leagues;
  SELECT maximum::numeric*target_multiple INTO reserve
    FROM okeyix_bot_wallet_private.policy WHERE singleton;
  IF maximum IS NULL OR maximum<=0 OR reserve IS NULL OR reserve<maximum
    OR reserve+150*25000>2147483647 THEN
    RAISE EXCEPTION 'BOT_POOL_INVALID_RESERVE';
  END IF;

  FOR i IN 1..150 LOOP
    bot_id:=batch_ids[i];
    bot_name:=(CASE WHEN i<=75 THEN male_names[i] ELSE female_names[i-75] END)
      ||' '||initials[1+((i-1)%15)]||'.';
    avatar_ref:='assets/images/avatars/avatar'||
      CASE WHEN i<=75 THEN male_avatars[1+((i-1)%12)]
        ELSE female_avatars[1+((i-76)%12)] END||'.png';
    bot_rating:=round((i-1)*1800.0/149)::integer;
    coin_amount:=(reserve+i*25000)::integer;

    FOREACH relation_name IN ARRAY ARRAY['users','profiles'] LOOP
      payload:=jsonb_build_object('id',bot_id,'username',bot_name,
        'rating',bot_rating,'avatar_url',avatar_ref);
      IF relation_name='users' THEN
        payload:=payload||jsonb_build_object('is_bot',true,
          'email','okeyix-seed-20261125-'||i||'@bots.invalid',
          'is_banned',false,'is_suspended',false,'wins',0,'losses',0);
      ELSE
        -- Preserve the actual funding delta if a signup trigger supplied
        -- a default balance before this seed initializes the new profile.
        SELECT coins INTO initial_coins FROM public.profiles WHERE id=bot_id;
        initial_coins:=coalesce(initial_coins,0);
        IF initial_coins<0 OR initial_coins>=coin_amount THEN
          RAISE EXCEPTION 'BOT_POOL_UNEXPECTED_INITIAL_BALANCE';
        END IF;
        payload:=payload||jsonb_build_object('coins',coin_amount,'avatar',avatar_ref,
          'is_online',false,'allow_game_invites',true);
      END IF;
      SELECT string_agg(format('%I',c.column_name),',' ORDER BY c.ordinal_position),
        string_agg(format('r.%I',c.column_name),',' ORDER BY c.ordinal_position),
        string_agg(format('%I=EXCLUDED.%I',c.column_name,c.column_name),','
          ORDER BY c.ordinal_position) FILTER(WHERE c.column_name<>'id')
      INTO columns_sql,values_sql,updates_sql
      FROM information_schema.columns c
      WHERE c.table_schema='public' AND c.table_name=relation_name
        AND payload ? c.column_name AND c.is_generated='NEVER'
        AND c.is_identity='NO';
      -- An existing users-insert trigger may have created the NEW bot's
      -- profile already. Only that fresh UUID may be updated, never old bots.
      EXECUTE format(
        'INSERT INTO public.%I (%s) SELECT %s FROM jsonb_populate_record(NULL::public.%I,$1) r WHERE true%s',
        relation_name,columns_sql,values_sql,relation_name,
        CASE WHEN relation_name='profiles'
          THEN ' ON CONFLICT (id) DO UPDATE SET '||updates_sql ELSE '' END)
      USING payload;
    END LOOP;
    -- Registration is owned by the existing identity trigger.
    IF NOT EXISTS(SELECT 1 FROM okeyix_bot_wallet_private.registry WHERE user_id=bot_id) THEN
      RAISE EXCEPTION 'BOT_POOL_IDENTITY_NOT_REGISTERED';
    END IF;
    INSERT INTO okeyix_bot_wallet_private.topups
      (user_id,balance_before,balance_after,amount,maximum_entry,origin)
      VALUES(bot_id,initial_coins,coin_amount,coin_amount-initial_coins,maximum,'migration');
  END LOOP;

  IF (SELECT count(*) FROM public.users u
    JOIN public.profiles p ON p.id=u.id
    JOIN okeyix_bot_wallet_private.registry r ON r.user_id=u.id
    WHERE u.id=ANY(batch_ids) AND u.is_bot AND p.rating BETWEEN 0 AND 1800
      AND p.coins>=reserve AND u.avatar_url LIKE 'assets/images/avatars/avatar%.png')<>150
    OR (SELECT count(*) FROM okeyix_bot_wallet_private.topups WHERE user_id=ANY(batch_ids))<>150
    OR EXISTS(SELECT 1 FROM auth.users WHERE id=ANY(batch_ids)) THEN
    RAISE EXCEPTION 'BOT_POOL_POSTCHECK_FAILED';
  END IF;
  RAISE NOTICE 'Added 150 bots (75 male, 75 female), ratings 0..1800, reserve-based distinct balances.';
END
$seed$;
COMMIT;


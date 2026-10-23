-- BIR DEFA KURULUM. Once Authentication > Users > Add user > Create new user:
-- Email: ready-tables-owner@okeyix.invalid
-- Yeni/rastgele bir parola kullanin; bu hesapla oyuna giris YAPMAYIN.
-- Sonra bu dosyanin TAMAMINI ayni projenin SQL Editor'inda calistirin.
-- Yalnizca bu yeni sistem hesabini isaretler; oyun/bakiye verilerini degistirmez.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='15s';
DO $$
DECLARE a record;
BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'POSTGRES_REQUIRED'; END IF;
  SELECT id,created_at,last_sign_in_at,raw_app_meta_data INTO a
    FROM auth.users WHERE lower(email)='ready-tables-owner@okeyix.invalid' FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Once Authentication > Users ekraninda ready-tables-owner@okeyix.invalid hesabini olusturun';
  END IF;
  IF a.last_sign_in_at IS NOT NULL
    OR EXISTS(SELECT 1 FROM public.table_players WHERE user_id=a.id)
    OR EXISTS(SELECT 1 FROM okeyix_bot_wallet_private.registry WHERE user_id=a.id) THEN
    RAISE EXCEPTION 'Bu hesap kullanilmis; sistem sahibi yapilamaz'; END IF;
  IF coalesce(a.raw_app_meta_data->>'okeyix_system','')<>'ready_tables_owner' THEN
    IF a.created_at<now()-interval '24 hours'
      OR EXISTS(SELECT 1 FROM public.tables WHERE created_by=a.id)
      OR EXISTS(SELECT 1 FROM okeyix_ready_private.policy WHERE owner_id IS NOT NULL AND owner_id<>a.id) THEN
      RAISE EXCEPTION 'Yeni ve kullanilmamis ayri bir sistem hesabi gerekli'; END IF;
  END IF;
  -- Owner was created through Auth's normal Dashboard flow, never by SQL INSERT.
  -- No credentials are copied, printed or stored in this script.
  UPDATE auth.users SET
    raw_app_meta_data=coalesce(raw_app_meta_data,'{}'::jsonb)
      ||jsonb_build_object('okeyix_system','ready_tables_owner'),
    banned_until=now()+interval '100 years',updated_at=now()
    WHERE id=a.id;
  UPDATE okeyix_ready_private.policy SET owner_id=a.id,enabled=true WHERE singleton;
  IF NOT FOUND THEN RAISE EXCEPTION 'Hazir masa migration kurulumu bulunamadi'; END IF;
END $$;
COMMIT;
SELECT enabled AS aktif,target AS lig_basina_hedef FROM okeyix_ready_private.policy;
-- Existing minute watchdog now fills standard / bronze / silver automatically.

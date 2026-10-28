-- READ ONLY. Run in Supabase SQL Editor as postgres.
-- No tokens, credentials, usernames or message contents are returned.
-- Do not paste Vault contents, environment secrets or device tokens.
WITH inspected_columns AS (
  SELECT table_schema, table_name, column_name, data_type, udt_name,
         is_nullable, column_default
  FROM information_schema.columns
  WHERE (table_schema='public' AND table_name IN
    ('profiles','users','user_devices','devices'))
    OR (table_schema='public' AND (
      table_name ILIKE '%notification%'
      OR table_name ILIKE '%preference%'
      OR table_name ILIKE '%consent%'))
    OR (table_schema='auth' AND table_name='users'
      AND column_name IN ('id','banned_until','deleted_at'))
), device_summary AS (
  -- JSON access tolerates optional permission columns without assuming names.
  -- Values themselves are never returned here.
  SELECT count(*) AS devices,
    count(*) FILTER (WHERE nullif(btrim(d.push_token),'') IS NOT NULL) AS with_token,
    count(*) FILTER (WHERE d.last_seen IS NULL) AS without_device_last_seen,
    count(*) FILTER (WHERE lower(coalesce(to_jsonb(d)->>'platform',''))='ios') AS ios_devices,
    count(*) FILTER (WHERE lower(coalesce(to_jsonb(d)->>'platform',''))='android') AS android_devices
  FROM public.user_devices d
)
SELECT jsonb_build_object(
  'checked_at',statement_timestamp(),
  'columns',(SELECT jsonb_agg(to_jsonb(c) ORDER BY table_schema,table_name,column_name)
    FROM inspected_columns c),
  'indexes',(SELECT jsonb_agg(jsonb_build_object(
    'table',tablename,'name',indexname,'definition',indexdef))
    FROM pg_indexes WHERE schemaname='public'
      AND tablename IN ('profiles','users','user_devices')),
  'policies',(SELECT jsonb_agg(to_jsonb(p)) FROM pg_policies p
    WHERE schemaname='public' AND tablename IN ('profiles','users','user_devices')),
  'device_summary',(SELECT to_jsonb(d) FROM device_summary d),
  'activity_summary',(SELECT jsonb_build_object(
    'profiles',count(*),
    'missing_last_seen',count(*) FILTER (WHERE last_seen_at IS NULL),
    'future_last_seen',count(*) FILTER (WHERE last_seen_at>statement_timestamp()),
    'inactive_48h',count(*) FILTER (WHERE last_seen_at<=statement_timestamp()-interval '48 hours'))
    FROM public.profiles),
  'extensions',(SELECT jsonb_agg(jsonb_build_object('name',extname,'version',extversion))
    FROM pg_extension WHERE extname IN ('pg_cron','pg_net','supabase_vault','pgcrypto')),
  -- Cron commands / Vault secret values deliberately excluded.
  'cron_catalog_present',to_regclass('cron.job') IS NOT NULL,
  'vault_catalog_present',to_regclass('vault.secrets') IS NOT NULL
) AS reengagement_schema_diagnostics;

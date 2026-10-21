-- READ ONLY. Run AFTER migration as postgres. Aggregate-only.
WITH configuration AS (
  SELECT c.*,m.maximum,m.maximum::numeric*c.low_multiple AS low_balance,
    m.maximum::numeric*c.target_multiple AS target_balance
  FROM okeyix_bot_wallet_private.policy c
  CROSS JOIN (SELECT max(max_coin) AS maximum FROM public.leagues) m
), bots AS (
  SELECT b.user_id,p.id IS NOT NULL AS has_wallet,coalesce(p.coins,0) AS coins
  FROM okeyix_bot_wallet_private.registry b
  JOIN public.users u ON u.id=b.user_id AND u.is_bot
  LEFT JOIN public.profiles p ON p.id=b.user_id
  WHERE NOT EXISTS(SELECT 1 FROM auth.users a WHERE a.id=b.user_id)
)
SELECT jsonb_build_object(
  'configuration',(SELECT to_jsonb(c) FROM configuration c),
  'registered_eligible_bots',(SELECT count(*) FROM bots),
  'missing_wallets',(SELECT count(*) FROM bots WHERE NOT has_wallet),
  'below_threshold',(SELECT count(*) FROM bots CROSS JOIN configuration c WHERE coins<c.low_balance),
  'topup_receipts',(SELECT count(*) FROM okeyix_bot_wallet_private.topups),
  'identity_guards_enabled',(SELECT count(*)=2 FROM pg_trigger
    WHERE tgrelid='public.users'::regclass AND tgenabled='O'
      AND tgname IN ('okeyix_bot_identity_guard','okeyix_bot_identity_register')),
  'authenticated_can_call_watchdog',has_function_privilege('authenticated','public.run_okey_watchdog()','EXECUTE'),
  'anon_can_call_watchdog',has_function_privilege('anon','public.run_okey_watchdog()','EXECUTE'),
  'authenticated_can_call_maintainer',has_function_privilege('authenticated','public.run_standard_bot_table_maintainer(integer,boolean)','EXECUTE'),
  'authenticated_private_schema_access',has_schema_privilege('authenticated','okeyix_bot_wallet_private','USAGE'),
  'anon_private_schema_access',has_schema_privilege('anon','okeyix_bot_wallet_private','USAGE'),
  'watchdog_source_unchanged',EXISTS(SELECT 1 FROM pg_proc
    WHERE oid='okeyix_bot_wallet_private.source_watchdog()'::regprocedure
      AND md5(prosrc)='b60311af82a4e64d13541944d251149f'),
  'active_existing_jobs',(SELECT count(*) FROM cron.job WHERE active AND username='postgres'
    AND database=current_database() AND position('run_okey_watchdog' IN command)>0)
) AS bot_wallet_installation_check;

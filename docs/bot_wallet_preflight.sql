-- READ ONLY. Run BEFORE migration in staging/production as postgres.
-- Only configuration and aggregate readiness; no identities or balances.
SELECT jsonb_build_object(
  'maximum_entry',(SELECT max(max_coin) FROM public.leagues),
  'low_balance',(SELECT max(max_coin)::numeric*5 FROM public.leagues),
  'target_balance',(SELECT max(max_coin)::numeric*20 FROM public.leagues),
  'valid_league_ranges',NOT EXISTS(SELECT 1 FROM public.leagues
    WHERE min_coin IS NULL OR max_coin IS NULL OR min_coin<=0 OR max_coin<min_coin),
  'target_fits_integer',(SELECT max(max_coin)::numeric*20<=2147483647 FROM public.leagues),
  'eligible_bot_identities',(SELECT count(*) FROM public.users u WHERE u.is_bot
    AND NOT EXISTS(SELECT 1 FROM auth.users a WHERE a.id=u.id)),
  'auth_linked_bot_flags_require_review',(SELECT count(*) FROM public.users u WHERE u.is_bot
    AND EXISTS(SELECT 1 FROM auth.users a WHERE a.id=u.id)),
  'eligible_bots_missing_wallet',(SELECT count(*) FROM public.users u LEFT JOIN public.profiles p ON p.id=u.id
    WHERE u.is_bot AND p.id IS NULL AND NOT EXISTS(SELECT 1 FROM auth.users a WHERE a.id=u.id)),
  'eligible_bots_negative_wallet',(SELECT count(*) FROM public.users u JOIN public.profiles p ON p.id=u.id
    WHERE u.is_bot AND p.coins<0 AND NOT EXISTS(SELECT 1 FROM auth.users a WHERE a.id=u.id)),
  'watchdog_contract_matches',EXISTS(SELECT 1 FROM pg_proc
    WHERE oid=to_regprocedure('public.run_okey_watchdog()') AND md5(prosrc)='b60311af82a4e64d13541944d251149f'),
  'maintainer_contract_matches',EXISTS(SELECT 1 FROM pg_proc
    WHERE oid=to_regprocedure('public.run_standard_bot_table_maintainer(integer,boolean)') AND md5(prosrc)='b2d85bfb32b8057267a3fedce7421ecb'),
  'active_postgres_watchdog_jobs',(SELECT count(*) FROM cron.job
    WHERE active AND username='postgres' AND database=current_database()
      AND position('run_okey_watchdog' IN command)>0)
) AS bot_wallet_preflight;

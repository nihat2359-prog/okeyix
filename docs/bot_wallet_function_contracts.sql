-- READ ONLY. Needed to integrate with the actual server lifecycle, preserving
-- its existing debit/reward rules. No player/table rows or balances are read.
-- Function source is returned only for this explicit allowlist. Review before
-- sharing: if an existing function contains a credential, omit/redact it.
WITH wanted(signature) AS (VALUES
  ('public.run_standard_bot_table_maintainer(integer,boolean)'),
  ('public.run_okey_watchdog()'),
  ('public.join_table(uuid,uuid,integer)'),
  ('public.join_table(uuid,uuid)'),
  ('public.handle_table_player_change()'),
  ('okeyix_stat_private.source_start_game(uuid)')
)
SELECT jsonb_build_object(
  'functions',(SELECT jsonb_agg(jsonb_build_object(
    'signature',w.signature,'exists',p.oid IS NOT NULL,
    'definition',CASE WHEN p.oid IS NOT NULL THEN pg_get_functiondef(p.oid) END
  ) ORDER BY w.signature)
  FROM wanted w LEFT JOIN pg_proc p ON p.oid=to_regprocedure(w.signature)),
  'scheduled_bot_jobs',COALESCE((
    SELECT jsonb_agg(jsonb_build_object('name',jobname,'schedule',schedule,
      'active',active,'owner',username) ORDER BY jobname)
    FROM cron.job WHERE command ~* '(run_standard_bot_table_maintainer|run_okey_watchdog)'
  ),'[]'::jsonb)
) AS bot_wallet_function_contracts;

-- READ ONLY. Inspect the deployed legacy endpoint; no reward or balance changes.
SELECT pg_get_functiondef(p.oid) AS legacy_daily_bonus_definition
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname='claim_daily_bonus'
  AND p.oid=to_regprocedure('public.claim_daily_bonus(uuid,integer,text)');

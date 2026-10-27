-- READ ONLY. SQL Editor / postgres. Change only the UUID to inspect another player.
WITH target AS (
  SELECT 'd52e528c-5e2a-4f80-a718-9952e95a2de5'::uuid AS user_id,
    'daily_bonus:'||to_char(statement_timestamp() AT TIME ZONE 'Europe/Istanbul','YYYY-MM-DD') AS today
)
SELECT jsonb_build_object(
  'server_time_istanbul',statement_timestamp() AT TIME ZONE 'Europe/Istanbul',
  'today_key',(SELECT today FROM target),
  'profile',(SELECT jsonb_build_object('id',u.id,'username',u.username,'exact_coins',p.coins)
    FROM target x JOIN public.users u ON u.id=x.user_id LEFT JOIN public.profiles p ON p.id=u.id),
  'available_today',NOT EXISTS(SELECT 1 FROM public.wallet_transactions w JOIN target x ON x.user_id=w.user_id
    WHERE w.reason='daily_bonus' AND w.note=x.today),
  'progress',(SELECT jsonb_build_object('claimed_days',r.claims,'next_reward_day',(r.claims%7)+1,
    'last_claimed_day_key',r.last_day_key) FROM okeyix_retention_private.reward_progress r
    JOIN target x ON x.user_id=r.user_id),
  'recent_daily_credits',(SELECT jsonb_agg(to_jsonb(r)) FROM (
    SELECT w.created_at AT TIME ZONE 'Europe/Istanbul' AS at_istanbul,w.amount,w.note
    FROM public.wallet_transactions w JOIN target x ON x.user_id=w.user_id
    WHERE w.reason='daily_bonus' ORDER BY w.created_at DESC LIMIT 14) r),
  'installed_reward_functions',(SELECT jsonb_agg(jsonb_build_object('name',p.proname,
    'source_md5',md5(replace(p.prosrc,chr(13)||chr(10),chr(10)))))
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'
      AND p.proname IN ('claim_daily_bonus','okeyix_daily_reward_status','okeyix_claim_daily_reward'))
) AS daily_reward_diagnostics;

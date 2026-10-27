-- READ ONLY. Inspect the failed test account; never credits/refunds or changes a pot.
WITH person AS (
  SELECT u.id,u.username,p.coins FROM public.users u
  LEFT JOIN public.profiles p ON p.id=u.id
  WHERE u.id='d52e528c-5e2a-4f80-a718-9952e95a2de5'::uuid
)
SELECT jsonb_build_object(
  'profile',(SELECT to_jsonb(p) FROM person p),
  'current_tables',(SELECT jsonb_agg(jsonb_build_object('id',t.id,'status',t.status,
    'pot_amount',t.pot_amount,'round_count',t.round_count))
    FROM public.tables t WHERE EXISTS(SELECT 1 FROM public.table_players tp
      JOIN person p ON p.id=tp.user_id WHERE tp.table_id=t.id)),
  'recent_indicator_receipts',(SELECT jsonb_agg(to_jsonb(r)) FROM (
    SELECT w.created_at,w.amount,w.note FROM public.wallet_transactions w
    JOIN person p ON p.id=w.user_id WHERE w.reason='indicator_bonus'
    ORDER BY w.created_at DESC LIMIT 10) r)
) AS indicator_reward_diagnostics;

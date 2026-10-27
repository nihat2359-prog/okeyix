-- READ ONLY. SQL Editor: verifies this account without changing any counters.
WITH person AS (
  SELECT id,username,wins,losses FROM public.users WHERE username='Oyuncu_BT4PH'
), finishes AS (
  SELECT p.user_id,p.outcome FROM public.okeyix_stat_players p
  JOIN public.okeyix_stat_rounds r ON r.id=p.round_id AND r.status='completed'
  JOIN person u ON u.id=p.user_id
  UNION ALL
  SELECT p.user_id,CASE WHEN e.winner_user_id=p.user_id THEN 'win' ELSE 'loss' END
  FROM okeyix_stat_private.event_players p
  JOIN person u ON u.id=p.user_id
  JOIN okeyix_stat_private.events e ON e.id=p.event_id
  WHERE e.kind='complete' AND e.processed_at IS NULL
    AND NOT EXISTS(SELECT 1 FROM public.okeyix_stat_rounds r
      WHERE r.source_start_key=e.table_id::text||':'||e.round_no::text||':'||e.seed
        AND r.status IN ('completed','aborted','draw'))
)
SELECT u.id,u.username,u.wins AS career_wins,u.losses AS career_losses,p.coins,
  (SELECT count(*) FROM finishes f WHERE f.user_id=u.id AND f.outcome='win') AS recorded_wins,
  (SELECT count(*) FROM finishes f WHERE f.user_id=u.id AND f.outcome='loss') AS recorded_losses
FROM person u LEFT JOIN public.profiles p ON p.id=u.id;

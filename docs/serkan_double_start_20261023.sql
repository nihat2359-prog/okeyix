-- READ ONLY. 23 October 2026, Europe/Istanbul (UTC+3).
-- No game state, balance or transaction is changed.
WITH period AS (
  SELECT timestamptz '2026-10-23 00:00:00+03' AS since,
         timestamptz '2026-10-24 00:00:00+03' AS until
), people AS (
  SELECT id,username FROM public.users
  WHERE username ILIKE '%serkan%' AND NOT coalesce(is_bot,false)
), fees AS (
  SELECT w.user_id,w.created_at,w.amount
  FROM public.wallet_transactions w JOIN people p ON p.id=w.user_id
  CROSS JOIN period d
  WHERE w.reason='table_entry' AND w.created_at>=d.since-interval '1 minute'
    AND w.created_at<d.until+interval '1 minute'
), fee_history AS (
  SELECT f.*,lag(created_at) OVER w AS previous_fee_at,
    lag(amount) OVER w AS previous_fee_amount
  FROM fees f WINDOW w AS (PARTITION BY user_id ORDER BY created_at)
), rounds AS (
  SELECT p.user_id,u.username,s.table_id,r.id,r.round_no,r.status,
    r.started_at,r.finished_at,p.coin_entry,p.outcome,
    lag(r.started_at) OVER w AS previous_started_at,
    lag(r.finished_at) OVER w AS previous_finished_at,
    lag(s.table_id) OVER w AS previous_table_id
  FROM public.okeyix_stat_players p JOIN people u ON u.id=p.user_id
  JOIN public.okeyix_stat_rounds r ON r.id=p.round_id
  JOIN public.okeyix_stat_sessions s ON s.id=r.session_id
  CROSS JOIN period d
  WHERE r.started_at>=d.since-interval '1 minute'
    AND r.started_at<d.until+interval '1 minute'
  WINDOW w AS (PARTITION BY p.user_id ORDER BY r.started_at,r.round_no)
), details AS (
  SELECT r.*,
    extract(epoch FROM r.started_at-r.previous_started_at) AS seconds_between_starts,
    extract(epoch FROM r.finished_at-r.started_at) AS duration_seconds,
    (SELECT count(*) FROM fees f WHERE f.user_id=r.user_id
      AND f.created_at BETWEEN r.started_at-interval '3 seconds'
                           AND r.started_at+interval '3 seconds') AS nearby_entry_count,
    (SELECT jsonb_agg(jsonb_build_object('at_tr',f.created_at AT TIME ZONE 'Europe/Istanbul',
      'amount',f.amount) ORDER BY f.created_at)
     FROM fees f WHERE f.user_id=r.user_id
       AND f.created_at BETWEEN r.started_at-interval '3 seconds'
                            AND r.started_at+interval '3 seconds') AS nearby_entries,
    (SELECT jsonb_agg(jsonb_build_object('kind',e.kind,'reason',e.reason,
      'at_tr',e.occurred_at AT TIME ZONE 'Europe/Istanbul') ORDER BY e.id)
     FROM okeyix_stat_private.events e
     WHERE e.table_id=r.table_id AND e.round_no=r.round_no) AS events
  FROM rounds r CROSS JOIN period d WHERE r.started_at>=d.since AND r.started_at<d.until
)
SELECT jsonb_build_object(
  'matched_players',(SELECT jsonb_agg(to_jsonb(p)) FROM people p),
  'summary',(SELECT jsonb_agg(to_jsonb(s)) FROM (
    SELECT user_id,username,count(*) AS round_count,
      count(*) FILTER(WHERE status='aborted') AS aborted_rounds,
      sum(coin_entry) AS recorded_entry_total
    FROM details GROUP BY user_id,username) s),
  'suspect_rounds',coalesce((SELECT jsonb_agg(to_jsonb(r)||jsonb_build_object(
    'start_tr',r.started_at AT TIME ZONE 'Europe/Istanbul') ORDER BY r.started_at)
    FROM details r WHERE r.seconds_between_starts<60 OR r.nearby_entry_count<>1
      OR (r.status='aborted' AND r.duration_seconds<60)
      OR r.previous_finished_at>r.started_at),'[]'::jsonb),
  'close_entry_fees',coalesce((SELECT jsonb_agg(to_jsonb(f)||jsonb_build_object(
    'at_tr',f.created_at AT TIME ZONE 'Europe/Istanbul') ORDER BY f.created_at)
    FROM fee_history f CROSS JOIN period d
    WHERE f.created_at>=d.since AND f.created_at<d.until
      AND f.created_at-f.previous_fee_at<interval '60 seconds'),'[]'::jsonb),
  'entry_fees_without_round',coalesce((SELECT jsonb_agg(to_jsonb(f))
    FROM fees f CROSS JOIN period d
    WHERE f.created_at>=d.since AND f.created_at<d.until
      AND NOT EXISTS(SELECT 1 FROM rounds r WHERE r.user_id=f.user_id
        AND f.created_at BETWEEN r.started_at-interval '3 seconds'
                             AND r.started_at+interval '3 seconds')),'[]'::jsonb)
) AS serkan_double_start_report;

-- READ ONLY. Search all rounds in the last 48 hours before limiting output.
-- Short rounds are candidates for investigation, not proof of an incorrect fee.
WITH history AS (
  SELECT s.table_id,r.id,r.session_id,r.round_no,r.status,r.started_at,r.finished_at,
    lag(r.started_at) OVER w AS previous_started_at,
    lag(r.finished_at) OVER w AS previous_finished_at,
    lag(r.status) OVER w AS previous_status
  FROM public.okeyix_stat_rounds r
  JOIN public.okeyix_stat_sessions s ON s.id=r.session_id
  WINDOW w AS (PARTITION BY s.table_id ORDER BY r.started_at,r.round_no)
), candidates AS (
  SELECT h.*,extract(epoch FROM h.started_at-h.previous_started_at) AS seconds_between_starts,
    extract(epoch FROM h.finished_at-h.started_at) AS duration_seconds
  FROM history h
  WHERE h.started_at>now()-interval '48 hours'
    AND (
      h.started_at-h.previous_started_at<interval '30 seconds'
      OR (h.status='aborted' AND h.finished_at-h.started_at<interval '30 seconds')
      OR (h.previous_started_at IS NOT NULL AND
          (h.previous_finished_at IS NULL OR h.previous_finished_at>h.started_at))
    )
  ORDER BY h.started_at DESC LIMIT 40
)
SELECT coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object(
  'players',(SELECT jsonb_agg(jsonb_build_object('user_id',p.user_id,
    'username',u.username,'is_bot',p.is_bot,'entry_charged',p.coin_entry,'outcome',p.outcome))
    FROM public.okeyix_stat_players p LEFT JOIN public.users u ON u.id=p.user_id
    WHERE p.round_id=c.id),
  'events',(SELECT jsonb_agg(jsonb_build_object('kind',e.kind,'reason',e.reason,
    'at',e.occurred_at) ORDER BY e.id)
    FROM okeyix_stat_private.events e
    WHERE e.table_id=c.table_id AND e.round_no=c.round_no)
) ORDER BY c.started_at DESC),'[]'::jsonb) AS suspicious_rounds
FROM candidates c;

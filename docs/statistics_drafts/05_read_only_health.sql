-- After deployment only. SELECT-only; no source game RPC is called.
SELECT count(*) FILTER(WHERE processed_at IS NULL) AS pending_events,
       count(*) FILTER(WHERE processed_at IS NULL AND attempts>0) AS retrying_events,
       min(recorded_at) FILTER(WHERE processed_at IS NULL) AS oldest_pending_at,
       max(attempts) AS maximum_attempts
FROM okeyix_stat_private.events;

SELECT kind,count(*) AS events,
       count(*) FILTER(WHERE processed_at IS NOT NULL) AS processed,
       count(*) FILTER(WHERE processed_at IS NULL AND attempts>0) AS retrying
FROM okeyix_stat_private.events GROUP BY kind ORDER BY kind;

SELECT error_code,count(*) AS pending_failures
FROM okeyix_stat_private.events WHERE processed_at IS NULL AND attempts>0
GROUP BY error_code ORDER BY count(*) DESC;

SELECT status,count(*) AS rounds FROM public.okeyix_stat_rounds GROUP BY status ORDER BY status;

SELECT count(*) AS inconsistent_completed_rounds
FROM public.okeyix_stat_rounds r WHERE r.status='completed' AND (
  (SELECT count(*) FROM public.okeyix_stat_players p WHERE p.round_id=r.id AND p.outcome='win')<>1
  OR NOT EXISTS(SELECT 1 FROM public.okeyix_stat_players p
    WHERE p.round_id=r.id AND p.user_id=r.winner_user_id AND p.outcome='win')
  OR EXISTS(SELECT 1 FROM public.okeyix_stat_players p WHERE p.round_id=r.id AND p.outcome='pending')
);

SELECT jobid,jobname,schedule,active,username FROM cron.job WHERE jobname='okeyix-stat-projector';
SELECT d.status,d.start_time,d.end_time FROM cron.job_run_details d
JOIN cron.job j ON j.jobid=d.jobid WHERE j.jobname='okeyix-stat-projector'
ORDER BY d.start_time DESC LIMIT 10;

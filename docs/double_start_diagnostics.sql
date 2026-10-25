-- READ ONLY. Run in SQL Editor; does not start/reset a game or change balances.
-- Includes recent entry receipts and the terminal event of the previous deal.
WITH starts AS (
  SELECT e.* FROM okeyix_stat_private.events e
  WHERE e.kind='begin' AND e.occurred_at>now()-interval '48 hours'
  ORDER BY e.id DESC LIMIT 30
), details AS (
  SELECT e.id,e.table_id,e.round_no,e.occurred_at,e.entry_coin,
    previous.round_no AS previous_round,
    previous.occurred_at AS previous_started_at,
    extract(epoch FROM e.occurred_at-previous.occurred_at) AS seconds_between_starts,
    (SELECT jsonb_agg(jsonb_build_object('kind',x.kind,'reason',x.reason,
      'at',x.occurred_at) ORDER BY x.id)
     FROM okeyix_stat_private.events x
     WHERE x.table_id=previous.table_id AND x.round_no=previous.round_no
       AND x.seed=previous.seed AND x.kind IN ('complete','abort')) AS previous_round_end,
    (SELECT jsonb_agg(jsonb_build_object('user_id',p.user_id,'is_bot',p.is_bot,
      'entry_charged',p.coin_entry) ORDER BY p.seat_index)
     FROM okeyix_stat_private.event_players p WHERE p.event_id=e.id) AS charges
  FROM starts e
  LEFT JOIN LATERAL (
    SELECT p.* FROM okeyix_stat_private.events p
    WHERE p.table_id=e.table_id AND p.kind='begin' AND p.id<e.id
    ORDER BY p.id DESC LIMIT 1
  ) previous ON true
), processed AS (
  SELECT r.id,s.table_id,r.round_no,r.status,r.started_at,r.finished_at,
    r.started_at-lag(r.started_at) OVER (
      PARTITION BY r.session_id ORDER BY r.round_no) AS time_since_previous_start,
    (SELECT jsonb_agg(jsonb_build_object('user_id',p.user_id,
      'is_bot',p.is_bot,'entry_charged',p.coin_entry,'outcome',p.outcome)
      ORDER BY p.seat_index)
     FROM public.okeyix_stat_players p WHERE p.round_id=r.id) AS charges
  FROM public.okeyix_stat_rounds r
  JOIN public.okeyix_stat_sessions s ON s.id=r.session_id
  WHERE r.started_at>now()-interval '48 hours'
  ORDER BY r.started_at DESC LIMIT 30
), triggers AS (
  SELECT c.relname AS table_name,t.tgname AS trigger_name,
    pg_get_triggerdef(t.oid) AS trigger_definition,
    pg_get_functiondef(t.tgfoid) AS function_definition
  FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relname IN ('tables','table_players')
    AND NOT t.tgisinternal
)
SELECT jsonb_build_object(
  'recent_starts',coalesce((SELECT jsonb_agg(to_jsonb(d) ORDER BY d.id DESC)
    FROM details d),'[]'::jsonb),
  'processed_rounds',coalesce((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.started_at DESC)
    FROM processed p),'[]'::jsonb),
  'table_triggers',coalesce((SELECT jsonb_agg(to_jsonb(t)) FROM triggers t),'[]'::jsonb)
) AS double_start_diagnostics;

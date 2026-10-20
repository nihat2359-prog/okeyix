-- SQL Editor: run the WHOLE file once. Exactly one read-only SELECT result.
-- No writer/game RPC is called. No function bodies, cron commands, credentials,
-- player IDs, names, balances or other personal data are returned.
-- If a relation is missing, share the error; do not run corrective SQL blindly.
WITH
expected_tables(name) AS (VALUES
  ('public.okeyix_stat_sessions'),('public.okeyix_stat_rounds'),('public.okeyix_stat_players'),
  ('okeyix_stat_private.events'),('okeyix_stat_private.event_players'),('okeyix_stat_private.original_acl')
),
table_checks AS (
  SELECT w.name,c.oid IS NOT NULL AS exists,c.relrowsecurity AS rls_enabled,
    pg_catalog.pg_get_userbyid(c.relowner)='postgres' AS owner_is_postgres,
    CASE WHEN c.oid IS NOT NULL THEN
      pg_catalog.has_table_privilege('authenticated',c.oid,'INSERT') OR
      pg_catalog.has_table_privilege('authenticated',c.oid,'UPDATE') OR
      pg_catalog.has_table_privilege('authenticated',c.oid,'DELETE') OR
      pg_catalog.has_table_privilege('authenticated',c.oid,'TRUNCATE')
    END AS authenticated_can_write,
    CASE WHEN c.oid IS NOT NULL THEN
      pg_catalog.has_table_privilege('anon',c.oid,'INSERT') OR
      pg_catalog.has_table_privilege('anon',c.oid,'UPDATE') OR
      pg_catalog.has_table_privilege('anon',c.oid,'DELETE') OR
      pg_catalog.has_table_privilege('anon',c.oid,'TRUNCATE')
    END AS anon_can_write,
    CASE WHEN c.oid IS NOT NULL THEN
      pg_catalog.has_table_privilege('service_role',c.oid,'INSERT') OR
      pg_catalog.has_table_privilege('service_role',c.oid,'UPDATE') OR
      pg_catalog.has_table_privilege('service_role',c.oid,'DELETE') OR
      pg_catalog.has_table_privilege('service_role',c.oid,'TRUNCATE')
    END AS service_role_can_write
  FROM expected_tables w LEFT JOIN pg_catalog.pg_class c ON c.oid=pg_catalog.to_regclass(w.name)
),
expected_functions(signature,expected_definer) AS (VALUES
  ('public.start_game(uuid)',true),
  ('public.game_finish(uuid,uuid,jsonb,jsonb)',true),
  ('public.leave_table(uuid,uuid)',true),
  ('public.game_timeout_move(uuid,uuid)',true),
  ('public.game_discard(uuid,uuid,jsonb,boolean,jsonb,boolean)',true),
  ('okeyix_stat_private.source_start_game(uuid)',false),
  ('okeyix_stat_private.source_game_finish(uuid,uuid,jsonb,jsonb)',true),
  ('okeyix_stat_private.source_leave_table(uuid,uuid)',false),
  ('okeyix_stat_private.source_game_timeout_move(uuid,uuid)',true),
  ('okeyix_stat_private.source_game_discard(uuid,uuid,jsonb,boolean,jsonb,boolean)',true),
  ('okeyix_stat_private.project_event(bigint)',true),
  ('okeyix_stat_private.process_events(integer)',true),
  ('okeyix_stat_private.put_event(uuid,bigint,text,text,text,bigint,timestamp with time zone,uuid,boolean,boolean,text,jsonb)',true),
  ('okeyix_stat_private.abort_round(uuid,bigint,text,timestamp with time zone,text)',true),
  ('okeyix_stat_private.dispatch(text,uuid,uuid,jsonb,jsonb,boolean,boolean)',true),
  ('okeyix_stat_private.table_ended()',true)
),
function_checks AS (
  SELECT w.signature,p.oid IS NOT NULL AS exists,
    p.prosecdef=w.expected_definer AS security_mode_matches,
    pg_catalog.pg_get_userbyid(p.proowner)='postgres' AS owner_is_postgres,
    CASE WHEN p.oid IS NOT NULL THEN pg_catalog.has_function_privilege('anon',p.oid,'EXECUTE') END AS anon_execute,
    CASE WHEN p.oid IS NOT NULL THEN pg_catalog.has_function_privilege('authenticated',p.oid,'EXECUTE') END AS authenticated_execute,
    CASE WHEN p.oid IS NOT NULL THEN pg_catalog.has_function_privilege('service_role',p.oid,'EXECUTE') END AS service_role_execute,
    CASE WHEN w.signature LIKE '%source_%' THEN NULL ELSE
      COALESCE(p.proconfig @> ARRAY['search_path=pg_catalog, public, pg_temp'],false)
      OR COALESCE(p.proconfig @> ARRAY['search_path=pg_catalog, pg_temp'],false)
    END AS fixed_search_path
  FROM expected_functions w LEFT JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(w.signature)
),
trigger_checks AS (
  SELECT w.name,t.oid IS NOT NULL AS exists,t.tgenabled='O' AS enabled,
    t.tgdeferrable AS deferrable,t.tginitdeferred AS initially_deferred,
    t.tgfoid=pg_catalog.to_regprocedure('okeyix_stat_private.table_ended()') AS correct_handler
  FROM (VALUES ('okeyix_stat_table_reset'),('okeyix_stat_table_delete')) w(name)
  LEFT JOIN pg_catalog.pg_trigger t ON t.tgname=w.name
    AND t.tgrelid=pg_catalog.to_regclass('public.tables') AND NOT t.tgisinternal
),
index_checks AS (
  SELECT w.name,i.indexrelid IS NOT NULL AS exists,i.indisvalid AS valid,i.indisunique AS unique_index
  FROM (VALUES
    ('okeyix_stat_private.events_one_terminal'),('okeyix_stat_private.events_pending'),
    ('okeyix_stat_private.events_table_pending'),('public.okeyix_stat_rounds_one_open_idx'),
    ('public.okeyix_stat_players_one_winner_idx'),('public.okeyix_stat_players_history_idx')
  ) w(name) LEFT JOIN pg_catalog.pg_index i ON i.indexrelid=pg_catalog.to_regclass(w.name)
),
queue_by_kind AS (
  SELECT kind,count(*) AS total,
    count(*) FILTER(WHERE processed_at IS NOT NULL) AS processed,
    count(*) FILTER(WHERE processed_at IS NULL) AS pending,
    count(*) FILTER(WHERE processed_at IS NULL AND attempts>0) AS currently_failed,
    count(*) FILTER(WHERE attempts>0) AS ever_retried,
    min(recorded_at) FILTER(WHERE processed_at IS NULL) AS oldest_pending_at,
    max(processed_at) AS last_processed_at
  FROM okeyix_stat_private.events GROUP BY kind
),
cron_jobs AS (
  SELECT jobid,jobname,schedule,active,
    command='SELECT okeyix_stat_private.process_events(250);' AS command_matches,
    username='postgres' AS owner_is_postgres,
    database=current_database() AS correct_database
  FROM cron.job WHERE jobname='okeyix-stat-projector'
),
recent_cron_runs AS (
  SELECT d.runid,d.status,d.start_time,d.end_time
  FROM cron.job_run_details d JOIN cron_jobs j ON j.jobid=d.jobid
  ORDER BY d.start_time DESC,d.runid DESC LIMIT 10
)
SELECT pg_catalog.jsonb_build_object(
  'checked_at',CURRENT_TIMESTAMP,
  'installation',pg_catalog.jsonb_build_object(
    'tables',COALESCE((SELECT jsonb_agg(to_jsonb(t) ORDER BY name) FROM table_checks t),'[]'::jsonb),
    'functions',COALESCE((SELECT jsonb_agg(to_jsonb(f) ORDER BY signature) FROM function_checks f),'[]'::jsonb),
    'triggers',COALESCE((SELECT jsonb_agg(to_jsonb(t) ORDER BY name) FROM trigger_checks t),'[]'::jsonb),
    'indexes',COALESCE((SELECT jsonb_agg(to_jsonb(i) ORDER BY name) FROM index_checks i),'[]'::jsonb),
    'backed_up_source_functions',(SELECT count(*) FROM okeyix_stat_private.original_acl),
    'private_schema_exists',pg_catalog.to_regnamespace('okeyix_stat_private') IS NOT NULL,
    'authenticated_private_schema_access',pg_catalog.has_schema_privilege('authenticated','okeyix_stat_private','USAGE'),
    'anon_private_schema_access',pg_catalog.has_schema_privilege('anon','okeyix_stat_private','USAGE'),
    'service_role_private_schema_access',pg_catalog.has_schema_privilege('service_role','okeyix_stat_private','USAGE'),
    'winner_fk',(
      SELECT jsonb_build_object('exists',count(*)=1,
        'deferrable',bool_and(condeferrable),'initially_deferred',bool_and(condeferred),'validated',bool_and(convalidated))
      FROM pg_catalog.pg_constraint WHERE conrelid=pg_catalog.to_regclass('public.okeyix_stat_rounds')
        AND conname='okeyix_stat_rounds_winner_participant_fk' AND contype='f'
    ),
    'statistics_fk_to_live_game_tables',(
      SELECT count(*) FROM pg_catalog.pg_constraint c
      WHERE c.contype='f' AND c.conrelid IN (
        pg_catalog.to_regclass('public.okeyix_stat_sessions'),pg_catalog.to_regclass('public.okeyix_stat_rounds'),
        pg_catalog.to_regclass('public.okeyix_stat_players'))
      AND c.confrelid NOT IN (pg_catalog.to_regclass('public.okeyix_stat_sessions'),
        pg_catalog.to_regclass('public.okeyix_stat_rounds'),pg_catalog.to_regclass('public.okeyix_stat_players'))
    )
  ),
  'queue',pg_catalog.jsonb_build_object(
    'total',COALESCE((SELECT sum(total) FROM queue_by_kind),0),
    'processed',COALESCE((SELECT sum(processed) FROM queue_by_kind),0),
    'pending',COALESCE((SELECT sum(pending) FROM queue_by_kind),0),
    'currently_failed',COALESCE((SELECT sum(currently_failed) FROM queue_by_kind),0),
    'ever_retried',COALESCE((SELECT sum(ever_retried) FROM queue_by_kind),0),
    'oldest_pending_at',(SELECT min(oldest_pending_at) FROM queue_by_kind),
    'last_processed_at',(SELECT max(last_processed_at) FROM queue_by_kind),
    'by_kind',COALESCE((SELECT jsonb_agg(to_jsonb(q) ORDER BY kind) FROM queue_by_kind q),'[]'::jsonb),
    'event_player_receipts',(SELECT count(*) FROM okeyix_stat_private.event_players),
    'error_summary',COALESCE((SELECT jsonb_agg(to_jsonb(e) ORDER BY error_code) FROM (
      SELECT error_code,count(*) AS pending_events,max(attempts) AS maximum_attempts
      FROM okeyix_stat_private.events WHERE processed_at IS NULL AND attempts>0 GROUP BY error_code
    ) e),'[]'::jsonb),
    'recent_failed_events',COALESCE((SELECT jsonb_agg(to_jsonb(e) ORDER BY id DESC) FROM (
      SELECT id,kind,attempts,error_code,recorded_at,retry_at
      FROM okeyix_stat_private.events WHERE processed_at IS NULL AND attempts>0 ORDER BY id DESC LIMIT 20
    ) e),'[]'::jsonb)
  ),
  'statistics',pg_catalog.jsonb_build_object(
    'sessions',(SELECT count(*) FROM public.okeyix_stat_sessions),
    'closed_sessions',(SELECT count(*) FROM public.okeyix_stat_sessions WHERE ended_at IS NOT NULL),
    'rounds',(SELECT count(*) FROM public.okeyix_stat_rounds),
    'player_results',(SELECT count(*) FROM public.okeyix_stat_players),
    'rounds_by_status',COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY status) FROM (
      SELECT status,count(*) AS count FROM public.okeyix_stat_rounds GROUP BY status
    ) r),'[]'::jsonb),
    'players_by_outcome',COALESCE((SELECT jsonb_agg(to_jsonb(p) ORDER BY outcome) FROM (
      SELECT outcome,count(*) AS count FROM public.okeyix_stat_players GROUP BY outcome
    ) p),'[]'::jsonb),
    'inconsistent_completed_rounds',(
      SELECT count(*) FROM public.okeyix_stat_rounds r WHERE r.status='completed' AND (
        (SELECT count(*) FROM public.okeyix_stat_players p WHERE p.round_id=r.id AND p.outcome='win')<>1
        OR NOT EXISTS(SELECT 1 FROM public.okeyix_stat_players p
          WHERE p.round_id=r.id AND p.user_id=r.winner_user_id AND p.outcome='win')
        OR EXISTS(SELECT 1 FROM public.okeyix_stat_players p WHERE p.round_id=r.id AND p.outcome NOT IN ('win','loss')))
    )
  ),
  'cron',pg_catalog.jsonb_build_object(
    'extension_installed',EXISTS(SELECT 1 FROM pg_catalog.pg_extension WHERE extname='pg_cron'),
    'job_count',(SELECT count(*) FROM cron_jobs),
    'jobs',COALESCE((SELECT jsonb_agg(to_jsonb(j) ORDER BY jobid) FROM cron_jobs j),'[]'::jsonb),
    'recent_runs',COALESCE((SELECT jsonb_agg(to_jsonb(r) ORDER BY start_time DESC,runid DESC) FROM recent_cron_runs r),'[]'::jsonb)
  )
) AS statistics_installation_check;

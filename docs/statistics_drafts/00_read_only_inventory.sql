-- Run this file once in Supabase SQL Editor and share the result.
-- SELECT/catalog inspection ONLY. No game RPC is invoked; no rows are changed.
-- No player rows, balances, credentials, cron commands or full schema dump.
-- Missing relations/functions are reported as missing, not assumed to exist.
WITH
wanted_tables(name) AS (
  VALUES ('tables'), ('table_players'), ('users'), ('profiles'),
         ('wallet_transactions'), ('rating_transactions'), ('recent_opponents'),
         ('match_moves'), ('table_discards'), ('table_finish_snapshots'),
         ('matches'), ('rounds'), ('okeyix_stat_sessions'),
         ('okeyix_stat_rounds'), ('okeyix_stat_players')
),
rels AS (
  SELECT c.oid, c.relname, c.relowner, c.relrowsecurity,
         c.relforcerowsecurity, c.relacl
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  JOIN wanted_tables w ON w.name = c.relname
  WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
),
wanted_functions(name) AS (
  VALUES ('start_game'), ('game_finish'), ('leave_table'),
         ('game_timeout_move'), ('game_discard'), ('game_discard_fast'),
         ('cleanup_stale_waiting_tables'), ('get_full_table_state'),
         ('okeyix_stat_begin_round'), ('okeyix_stat_finalize_round')
),
triggers AS (
  SELECT t.oid, t.tgrelid, t.tgname, t.tgenabled, t.tgfoid
  FROM pg_catalog.pg_trigger t
  JOIN rels r ON r.oid = t.tgrelid
  WHERE NOT t.tgisinternal
),
funcs AS (
  SELECT p.*, n.nspname
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE p.prokind = 'f' AND (
    (n.nspname = 'public' AND p.proname IN (SELECT name FROM wanted_functions))
    OR p.oid IN (SELECT tgfoid FROM triggers)
  )
)
SELECT pg_catalog.jsonb_build_object(
  'tables', COALESCE((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'name', w.name,
      'exists', r.oid IS NOT NULL,
      'owner', pg_catalog.pg_get_userbyid(r.relowner),
      'rls', r.relrowsecurity,
      'force_rls', r.relforcerowsecurity,
      'acl', r.relacl::text,
      'columns', COALESCE((
        SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'name', a.attname,
          'type', pg_catalog.format_type(a.atttypid, a.atttypmod),
          'not_null', a.attnotnull,
          'generated', a.attgenerated,
          'identity', a.attidentity,
          'default_or_expression', pg_catalog.pg_get_expr(d.adbin, d.adrelid),
          'acl', a.attacl::text
        ) ORDER BY a.attnum)
        FROM pg_catalog.pg_attribute a
        LEFT JOIN pg_catalog.pg_attrdef d
          ON d.adrelid = a.attrelid AND d.adnum = a.attnum
        WHERE a.attrelid = r.oid AND a.attnum > 0 AND NOT a.attisdropped
      ), '[]'::jsonb)
    ) ORDER BY w.name)
    FROM wanted_tables w LEFT JOIN rels r ON r.relname = w.name
  ), '[]'::jsonb),
  'constraints_including_incoming_fks', COALESCE((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'table', c.conrelid::regclass::text,
      'name', c.conname,
      'type', c.contype,
      'definition', pg_catalog.pg_get_constraintdef(c.oid, true),
      'deferrable', c.condeferrable,
      'initially_deferred', c.condeferred,
      'validated', c.convalidated
    ) ORDER BY c.conrelid::regclass::text, c.conname)
    FROM pg_catalog.pg_constraint c
    WHERE c.conrelid IN (SELECT oid FROM rels)
       OR (c.contype = 'f' AND c.confrelid IN (SELECT oid FROM rels))
  ), '[]'::jsonb),
  'indexes', COALESCE((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'table', r.relname,
      'definition', pg_catalog.pg_get_indexdef(i.indexrelid),
      'valid', i.indisvalid
    ) ORDER BY r.relname, i.indexrelid::regclass::text)
    FROM pg_catalog.pg_index i JOIN rels r ON r.oid = i.indrelid
  ), '[]'::jsonb),
  'rls_policies', COALESCE((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'table', p.tablename, 'name', p.policyname,
      'permissive', p.permissive, 'roles', p.roles, 'command', p.cmd,
      'using', p.qual, 'with_check', p.with_check
    ) ORDER BY p.tablename, p.policyname)
    FROM pg_catalog.pg_policies p
    WHERE p.schemaname = 'public' AND p.tablename IN (SELECT name FROM wanted_tables)
  ), '[]'::jsonb),
  'triggers', COALESCE((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'table', t.tgrelid::regclass::text, 'name', t.tgname,
      'enabled', t.tgenabled,
      'definition', pg_catalog.pg_get_triggerdef(t.oid, true),
      'function', t.tgfoid::regprocedure::text
    ) ORDER BY t.tgrelid::regclass::text, t.tgname)
    FROM triggers t
  ), '[]'::jsonb),
  'functions', COALESCE((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'schema', f.nspname, 'name', f.proname,
      'arguments', pg_catalog.pg_get_function_identity_arguments(f.oid),
      'owner', pg_catalog.pg_get_userbyid(f.proowner),
      'security_definer', f.prosecdef,
      'settings', f.proconfig, 'acl', f.proacl::text,
      -- Existing function bodies may contain embedded credentials. Never return
      -- bearer values/JWT strings when this inventory is shared for review.
      'definition', pg_catalog.regexp_replace(
        pg_catalog.regexp_replace(pg_catalog.pg_get_functiondef(f.oid),
          '(Bearer[[:space:]]+)[^''[:space:]]+', '\1[REDACTED]', 'gi'),
        'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+', '[REDACTED_JWT]', 'g')
    ) ORDER BY f.nspname, f.proname, f.oid)
    FROM funcs f
  ), '[]'::jsonb),
  'missing_named_functions', COALESCE((
    SELECT pg_catalog.jsonb_agg(w.name ORDER BY w.name)
    FROM wanted_functions w
    WHERE NOT EXISTS (
      SELECT 1 FROM funcs f WHERE f.nspname = 'public' AND f.proname = w.name
    )
  ), '[]'::jsonb),
  'owner_role_capabilities', COALESCE((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'role', r.rolname, 'superuser', r.rolsuper,
      'bypass_rls', r.rolbypassrls, 'can_login', r.rolcanlogin
    ) ORDER BY r.rolname)
    FROM pg_catalog.pg_roles r
    WHERE r.rolname IN ('postgres', 'anon', 'authenticated', 'service_role')
  ), '[]'::jsonb),
  'scheduler_extensions', COALESCE((
    SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'name', e.extname, 'version', e.extversion
    ) ORDER BY e.extname)
    FROM pg_catalog.pg_extension e WHERE e.extname IN ('pg_cron', 'pg_net')
  ), '[]'::jsonb)
) AS statistics_integration_inventory;

-- READ ONLY. Run as postgres in SQL Editor. No message content is returned.
-- Player messages absent here indicate a send/write failure; present messages
-- invisible to spectators require checking SELECT policies and Realtime access.
SELECT jsonb_build_object(
  'recent_message_counts', (
    SELECT jsonb_agg(to_jsonb(x)) FROM (
      SELECT table_id,role,type,count(*) AS message_count,max(created_at) AS last_message_at
      FROM public.table_messages
      WHERE created_at > now()-interval '2 hours'
      GROUP BY table_id,role,type ORDER BY max(created_at) DESC LIMIT 30
    ) x
  ),
  'policies', (
    SELECT jsonb_agg(to_jsonb(p)) FROM pg_policies p
    WHERE schemaname='public' AND tablename='table_messages'
  ),
  'rls', (
    SELECT jsonb_build_object('enabled',relrowsecurity,'forced',relforcerowsecurity)
    FROM pg_class WHERE oid='public.table_messages'::regclass
  ),
  'authenticated_grants', (
    SELECT jsonb_agg(privilege_type) FROM information_schema.role_table_grants
    WHERE table_schema='public' AND table_name='table_messages'
      AND grantee='authenticated'
  ),
  'realtime_publications', (
    SELECT jsonb_agg(pubname) FROM pg_publication_tables
    WHERE schemaname='public' AND tablename='table_messages'
  )
) AS table_chat_diagnostics;

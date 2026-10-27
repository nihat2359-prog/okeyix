-- READ ONLY. No message content, balances or game state is returned/changed.
-- Required before installing membership triggers and history restrictions.
SELECT jsonb_build_object(
  'columns',(SELECT jsonb_agg(to_jsonb(c)) FROM (
    SELECT table_name,column_name,data_type,is_nullable,column_default
    FROM information_schema.columns WHERE table_schema='public'
      AND table_name IN ('table_messages','table_players','table_spectators')
    ORDER BY table_name,ordinal_position) c),
  'constraints',(SELECT jsonb_agg(jsonb_build_object('table',conrelid::regclass::text,
    'name',conname,'definition',pg_get_constraintdef(oid))) FROM pg_constraint
    WHERE conrelid IN ('public.table_messages'::regclass,
      'public.table_players'::regclass,'public.table_spectators'::regclass)),
  'policies',(SELECT jsonb_agg(to_jsonb(p)) FROM pg_policies p
    WHERE schemaname='public' AND tablename IN
      ('table_messages','table_players','table_spectators')),
  'rls',(SELECT jsonb_agg(jsonb_build_object('table',relname,
    'enabled',relrowsecurity,'forced',relforcerowsecurity)) FROM pg_class
    WHERE oid='public.table_messages'::regclass),
  'triggers',(SELECT jsonb_agg(jsonb_build_object('table',tgrelid::regclass::text,
    'definition',pg_get_triggerdef(oid))) FROM pg_trigger
    WHERE NOT tgisinternal AND tgrelid IN ('public.table_messages'::regclass,
      'public.table_players'::regclass,'public.table_spectators'::regclass)),
  'publications',(SELECT jsonb_agg(to_jsonb(p)) FROM pg_publication_tables p
    WHERE schemaname='public' AND tablename='table_messages')
) AS table_chat_membership_schema;

-- READ ONLY. Run the whole file in the Supabase SQL Editor, then share its
-- single JSON result. No function bodies, cron commands, player identities,
-- balances, credentials or game mutations are returned.
WITH candidate_functions AS (
  SELECT p.oid, p.oid::regprocedure::text AS signature,
    p.prosecdef AS security_definer,
    pg_get_userbyid(p.proowner) AS owner,
    has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute,
    has_function_privilege('service_role',p.oid,'EXECUTE') AS service_execute,
    md5(p.prosrc) AS body_fingerprint,
    p.prosrc ~* 'is_bot' AS refers_to_bot_flag,
    p.prosrc ~* '(profiles|coins)' AS refers_to_wallet,
    p.prosrc ~* '(join_table|table_players)' AS refers_to_seating
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.prokind='f'
    AND (p.proname ~* '(bot|join_table|start_game|create_table)'
      OR (p.prosrc ~* 'is_bot' AND p.prosrc ~* '(profiles|coins|table_players)'))
), columns AS (
  SELECT table_name,column_name,data_type,is_nullable,column_default
  FROM information_schema.columns
  WHERE table_schema='public' AND (
    (table_name='users' AND column_name IN ('id','is_bot')) OR
    (table_name='profiles' AND column_name IN ('id','coins')) OR
    (table_name='leagues' AND column_name IN ('id','name','min_coin','max_coin','display_order')) OR
    (table_name='wallet_transactions' AND column_name IN ('id','user_id','amount','reason','type','store','note')))
), triggers AS (
  SELECT c.relname AS relation,t.tgname AS name,t.tgenabled AS enabled,
    t.tgfoid::regprocedure::text AS handler
  FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
  WHERE t.tgrelid IN (to_regclass('public.users'),to_regclass('public.profiles'),
    to_regclass('public.table_players')) AND NOT t.tgisinternal
)
SELECT jsonb_build_object(
  'leagues',(SELECT jsonb_agg(jsonb_build_object('id',id,'name',name,
    'min_coin',min_coin,'max_coin',max_coin) ORDER BY display_order) FROM public.leagues),
  'largest_configured_entry',(SELECT max(max_coin) FROM public.leagues),
  'columns',COALESCE((SELECT jsonb_agg(to_jsonb(c) ORDER BY table_name,column_name) FROM columns c),'[]'::jsonb),
  'functions',COALESCE((SELECT jsonb_agg(to_jsonb(f)-'oid' ORDER BY signature) FROM candidate_functions f),'[]'::jsonb),
  'triggers',COALESCE((SELECT jsonb_agg(to_jsonb(t) ORDER BY relation,name) FROM triggers t),'[]'::jsonb),
  'authenticated_can_set_is_bot',has_column_privilege('authenticated','public.users','is_bot','UPDATE'),
  'anon_can_set_is_bot',has_column_privilege('anon','public.users','is_bot','UPDATE'),
  'authenticated_can_insert_users',has_table_privilege('authenticated','public.users','INSERT'),
  'users_rls',(SELECT relrowsecurity FROM pg_class WHERE oid=to_regclass('public.users')),
  'users_policies',COALESCE((SELECT jsonb_agg(jsonb_build_object('name',policyname,'command',cmd,'roles',roles))
    FROM pg_policies WHERE schemaname='public' AND tablename='users'),'[]'::jsonb)
) AS bot_wallet_inventory;

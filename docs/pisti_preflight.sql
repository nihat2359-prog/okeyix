-- Read-only inventory. Run on the intended STAGING database before migration.
SELECT current_database(),current_user,version();
SELECT extname,extversion FROM pg_extension WHERE extname IN ('pg_cron','pg_net');
SELECT table_schema,table_name,column_name,udt_name FROM information_schema.columns
WHERE (table_schema='public' AND
 ((table_name='users' AND column_name IN ('id','username','avatar_url','is_bot','is_banned','ban_until')) OR
  (table_name='profiles' AND column_name IN ('id','coins','rating','allow_game_invites')) OR
  (table_name='wallet_transactions' AND column_name IN ('id','user_id','amount','reason','type','store','note','created_at')) OR
  (table_name='friends' AND column_name IN ('user_id','friend_id','status')) OR
  (table_name='user_devices' AND column_name IN ('user_id','push_token')) OR
  table_name IN ('okeyix_gift_catalog','tables','table_players')))
ORDER BY table_name,ordinal_position;
SELECT conrelid::regclass,conname,pg_get_constraintdef(oid) FROM pg_constraint
WHERE conrelid IN ('public.wallet_transactions'::regclass,'public.profiles'::regclass);
SELECT tgrelid::regclass,tgname,pg_get_triggerdef(oid) FROM pg_trigger
WHERE NOT tgisinternal AND tgrelid IN ('public.table_players'::regclass,'public.wallet_transactions'::regclass,'public.profiles'::regclass);
SELECT schemaname,tablename FROM pg_publication_tables WHERE pubname='supabase_realtime';
SELECT to_regclass('vault.secrets'),to_regclass('storage.buckets'),to_regclass('storage.objects');
-- Do NOT select Vault decrypted values, push tokens, secrets or card state.

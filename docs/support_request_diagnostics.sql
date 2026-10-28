-- Read-only diagnostics. Run in the Supabase SQL editor.
-- Contains user messages: inspect privately; redact before sharing results.
select id, user_id, category, message, status, created_at
from public.support_requests
order by created_at desc
limit 20;

select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'support_requests'
order by ordinal_position;

select policyname, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public' and tablename = 'support_requests';

select c.relrowsecurity, c.relforcerowsecurity
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname = 'support_requests';

select tgname, pg_get_triggerdef(oid) as definition
from pg_trigger
where tgrelid = 'public.support_requests'::regclass and not tgisinternal;

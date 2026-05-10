create table if not exists public.debug_events (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  client_ts timestamptz null,
  tag text not null,
  table_id uuid null,
  user_id uuid null,
  payload jsonb not null default '{}'::jsonb
);

create index if not exists idx_debug_events_created_at
  on public.debug_events(created_at desc);

create index if not exists idx_debug_events_tag
  on public.debug_events(tag);

create index if not exists idx_debug_events_table_id
  on public.debug_events(table_id);

create index if not exists idx_debug_events_user_id
  on public.debug_events(user_id);

alter table public.debug_events enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'debug_events'
      and policyname = 'debug_events_insert_auth'
  ) then
    create policy debug_events_insert_auth
      on public.debug_events
      for insert
      to authenticated
      with check (auth.uid() = user_id);
  end if;
end
$$;


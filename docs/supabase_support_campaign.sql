-- Support / complaint messages from users
create table if not exists public.support_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  category text not null check (category in ('talep', 'sikayet', 'hata')),
  message text not null,
  status text not null default 'open',
  created_at timestamp without time zone not null default now()
);

create index if not exists idx_support_requests_user_id
  on public.support_requests(user_id);

create index if not exists idx_support_requests_created_at
  on public.support_requests(created_at desc);

-- Admin/system broadcast or targeted messages
create table if not exists public.system_messages (
  id uuid primary key default gen_random_uuid(),
  title text,
  body text not null,
  type text not null default 'info',
  target_user_id uuid null references public.users(id) on delete cascade,
  is_active boolean not null default true,
  created_at timestamp without time zone not null default now()
);

create index if not exists idx_system_messages_target
  on public.system_messages(target_user_id, is_active, created_at desc);

-- Optional read tracking for strict server-side unread management.
create table if not exists public.system_message_reads (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.system_messages(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  read_at timestamp without time zone not null default now(),
  unique(message_id, user_id)
);

create index if not exists idx_system_message_reads_user
  on public.system_message_reads(user_id, read_at desc);

-- Campaigns shown in app
create table if not exists public.campaigns (
  id uuid primary key default gen_random_uuid(),
  title text,
  image_url text not null,
  is_active boolean not null default true,
  start_at timestamp without time zone not null,
  end_at timestamp without time zone not null,
  priority integer not null default 0,
  created_at timestamp without time zone not null default now()
);

create index if not exists idx_campaigns_active_window
  on public.campaigns(is_active, start_at, end_at, priority desc);

-- Per-user campaign show tracking (shown once per user)
create table if not exists public.campaign_views (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  seen_at timestamp without time zone not null default now(),
  unique(campaign_id, user_id)
);

create index if not exists idx_campaign_views_user
  on public.campaign_views(user_id, seen_at desc);

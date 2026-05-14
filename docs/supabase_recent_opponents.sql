-- Son Oynadiklarim icin kalici tablo + okuma fonksiyonu.
-- Bu tablo game_finish icinde guncellenir.

create table if not exists public.recent_opponents (
  id bigserial primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  opponent_user_id uuid not null references public.profiles(id) on delete cascade,
  last_table_id uuid null references public.tables(id) on delete set null,
  last_played_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (user_id, opponent_user_id),
  check (user_id <> opponent_user_id)
);

create index if not exists idx_recent_opponents_user_last_played
  on public.recent_opponents(user_id, last_played_at desc);

create or replace function public.get_recent_opponents(
  p_user_id uuid,
  p_limit int default 20
)
returns table (
  user_id uuid,
  username text,
  avatar_url text,
  coins bigint,
  rating int,
  last_played_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  with ranked as (
    select
      ro.opponent_user_id,
      ro.last_played_at,
      row_number() over (
        partition by ro.user_id
        order by ro.last_played_at desc, ro.id desc
      ) as rn
    from public.recent_opponents ro
    where ro.user_id = p_user_id
  )
  select
    r.opponent_user_id as user_id,
    coalesce(u.username, pr.username, 'Oyuncu') as username,
    coalesce(u.avatar_url, '') as avatar_url,
    coalesce(pr.coins, 0) as coins,
    coalesce(pr.rating, 1200) as rating,
    r.last_played_at
  from ranked r
  left join public.profiles pr on pr.id = r.opponent_user_id
  left join public.users u on u.id::text = r.opponent_user_id::text
  where r.rn <= greatest(1, least(coalesce(p_limit, 20), 50))
  order by r.last_played_at desc
  limit greatest(1, least(coalesce(p_limit, 20), 50));
$$;

grant execute on function public.get_recent_opponents(uuid, int)
to authenticated, service_role;

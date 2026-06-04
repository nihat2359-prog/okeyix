-- Ensure daily bonus is granted at most once per user per day key.

-- Clean up existing duplicate daily_bonus rows before adding unique index.
-- Keeps the earliest row per (user_id, note), deletes later duplicates.
with ranked as (
  select
    id,
    row_number() over (
      partition by user_id, note
      order by created_at asc, id asc
    ) as rn
  from public.wallet_transactions
  where reason = 'daily_bonus'
    and note is not null
)
delete from public.wallet_transactions wt
using ranked r
where wt.id = r.id
  and r.rn > 1;

create unique index if not exists ux_wallet_daily_bonus_once_per_day
  on public.wallet_transactions(user_id, note)
  where reason = 'daily_bonus' and note is not null;

create or replace function public.claim_daily_bonus(
  p_user_id uuid,
  p_amount integer,
  p_day_key text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_user_id is null then
    raise exception 'INVALID_USER_ID';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'INVALID_AMOUNT';
  end if;

  if p_day_key is null or btrim(p_day_key) = '' then
    raise exception 'INVALID_DAY_KEY';
  end if;

  begin
    insert into public.wallet_transactions(
      user_id,
      amount,
      reason,
      type,
      store,
      note
    )
    values (
      p_user_id,
      p_amount,
      'daily_bonus',
      'credit',
      'system',
      p_day_key
    );
  exception
    when unique_violation then
      return false;
  end;

  update public.profiles
     set coins = coalesce(coins, 0) + p_amount
   where id = p_user_id;

  return true;
end;
$$;

comment on function public.claim_daily_bonus(uuid, integer, text)
  is 'Claims daily bonus once per user/day_key. Returns false if already claimed for that day.';

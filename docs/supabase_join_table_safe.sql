-- Safe join_table RPC (keeps existing flow: charge entry coin -> add table player)
-- Adds race-safe validation for table state, seat occupancy, max player limit,
-- duplicate joins, and null checks.

create or replace function public.join_table(
  p_table_id uuid,
  p_user_id uuid,
  p_seat int
)
returns void
language plpgsql
security definer
as $$
declare
  v_table record;
  v_coins int;
  v_player_count int;
begin
  --------------------------------
  -- table lock + table validation
  --------------------------------
  select id, status, max_players, entry_coin
    into v_table
  from public.tables
  where id = p_table_id
  for update;

  if not found then
    raise exception 'TABLE_NOT_FOUND';
  end if;

  if v_table.status <> 'waiting' then
    raise exception 'TABLE_NOT_JOINABLE';
  end if;

  if v_table.max_players is null or v_table.max_players <= 0 then
    raise exception 'INVALID_MAX_PLAYERS';
  end if;

  if p_seat < 0 or p_seat >= v_table.max_players then
    raise exception 'INVALID_SEAT';
  end if;

  if coalesce(v_table.entry_coin, 0) < 0 then
    raise exception 'INVALID_ENTRY_COIN';
  end if;

  --------------------------------
  -- duplicate membership check
  --------------------------------
  if exists (
    select 1
    from public.table_players
    where table_id = p_table_id
      and user_id = p_user_id
  ) then
    -- idempotent behavior: already joined, do nothing.
    return;
  end if;

  --------------------------------
  -- seat occupancy check
  --------------------------------
  if exists (
    select 1
    from public.table_players
    where table_id = p_table_id
      and seat_index = p_seat
  ) then
    raise exception 'SEAT_OCCUPIED';
  end if;

  --------------------------------
  -- max player count check
  --------------------------------
  select count(*)
    into v_player_count
  from public.table_players
  where table_id = p_table_id;

  if v_player_count >= v_table.max_players then
    raise exception 'TABLE_FULL';
  end if;

  --------------------------------
  -- profile lock + coin check
  --------------------------------
  select coins
    into v_coins
  from public.profiles
  where id = p_user_id
  for update;

  if not found then
    raise exception 'PROFILE_NOT_FOUND';
  end if;

  if v_coins is null then
    raise exception 'PROFILE_COINS_NULL';
  end if;

  if v_coins < coalesce(v_table.entry_coin, 0) then
    raise exception 'NOT_ENOUGH_COINS';
  end if;

  --------------------------------
  -- charge entry coin
  --------------------------------
  update public.profiles
    set coins = coins - coalesce(v_table.entry_coin, 0)
  where id = p_user_id;

  insert into public.wallet_transactions(
    user_id,
    amount,
    reason
  )
  values(
    p_user_id,
    -coalesce(v_table.entry_coin, 0),
    'table_entry'
  );

  --------------------------------
  -- add player to table
  --------------------------------
  insert into public.table_players(
    table_id,
    user_id,
    seat_index,
    hand
  )
  values(
    p_table_id,
    p_user_id,
    p_seat,
    '[]'::jsonb
  );
end;
$$;

grant execute on function public.join_table(uuid, uuid, int) to authenticated, service_role;


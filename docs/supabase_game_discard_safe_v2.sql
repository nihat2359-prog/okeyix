-- game_discard v2 (safe)
-- Keeps existing gameplay flow and adds missing robustness:
-- - explicit function signature with defaults for optional params
-- - consistent rating base (1200)
-- - explicit loser rating loss variable
-- - optional rating transaction logs (guarded)

-- IMPORTANT:
-- Remove all old overloads first, otherwise PostgREST named-arg resolution
-- can throw PGRST203 (ambiguous function candidate).
drop function if exists public.game_discard(uuid, uuid, jsonb, boolean, jsonb, boolean);
drop function if exists public.game_discard(uuid, uuid, jsonb, boolean, boolean, jsonb);
drop function if exists public.game_discard(uuid, uuid, jsonb, boolean);

create or replace function public.game_discard(
  p_table_id uuid,
  p_user_id uuid,
  p_tile jsonb,
  p_finish boolean default false,
  p_slots jsonb default null,
  p_is_player_action boolean default true
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_table record;
  v_player record;
  v_hand jsonb;
  v_next_turn int;
  v_before int;
  v_after int;

  v_entry_coin int;
  v_rating_reward int;
  v_rating_loss int;
  v_player_count int;
  v_pot int;
  v_system_cut integer;
  v_winner_reward integer;

  v_slots jsonb;
begin

-------------------------------------------------
-- TABLE LOCK
-------------------------------------------------

select id, status, current_turn, max_players, entry_coin
into v_table
from public.tables
where id = p_table_id
for update;

if not found then
  raise exception 'TABLE_NOT_FOUND';
end if;

v_rating_reward :=
case
  when v_table.entry_coin = 100 then 10
  when v_table.entry_coin = 250 then 15
  when v_table.entry_coin = 500 then 20
  when v_table.entry_coin = 1000 then 25
  when v_table.entry_coin = 2500 then 30
  else 10
end;

v_rating_loss := greatest(1, floor(v_rating_reward / 2.0));

if v_table.status <> 'playing' then
  raise exception 'TABLE_NOT_PLAYING';
end if;

-------------------------------------------------
-- PLAYER LOCK
-------------------------------------------------

select id, seat_index, hand
into v_player
from public.table_players
where table_id = p_table_id
  and user_id = p_user_id
for update;

if not found then
  raise exception 'PLAYER_NOT_IN_TABLE';
end if;

if v_player.seat_index <> v_table.current_turn then
  raise exception 'NOT_YOUR_TURN';
end if;

-------------------------------------------------
-- HAND CHECK
-------------------------------------------------

v_hand := coalesce(v_player.hand, '[]'::jsonb);
v_before := jsonb_array_length(v_hand);

if v_before <> 15 then
  raise exception 'DISCARD_REQUIRES_15';
end if;

-- TILE REMOVE
-------------------------------------------------

v_hand := public._hand_remove_first(v_hand, p_tile);
v_after := jsonb_array_length(v_hand);

if v_after <> v_before - 1 then
  raise exception 'TILE_NOT_IN_HAND';
end if;

-------------------------------------------------
-- FINISH CHECK (after tile removal)
-------------------------------------------------

if p_finish then
  if not public.okey_can_finish(v_hand) then
    raise exception 'INVALID_FINISH';
  end if;
end if;

-------------------------------------------------
-- DISCARD INSERT
-------------------------------------------------

insert into public.table_discards(
  table_id,
  seat_index,
  discarded_by_user_id,
  tile
)
values(
  p_table_id,
  v_player.seat_index,
  p_user_id,
  p_tile
);

-------------------------------------------------
-- REALTIME EVENT
-------------------------------------------------

insert into public.match_moves(
  table_id,
  player_id,
  move_type,
  tile_data
)
values(
  p_table_id,
  p_user_id,
  'discard',
  p_tile
);

-------------------------------------------------
-- UPDATE HAND
-------------------------------------------------

update public.table_players
set hand = v_hand,
    consecutive_timeouts =
      case
        when p_is_player_action then 0
        else consecutive_timeouts
      end
where id = v_player.id;

v_next_turn := (v_table.current_turn + 1) % v_table.max_players;

-------------------------------------------------
-- FINISH
-------------------------------------------------

if p_finish then
  v_entry_coin := coalesce(v_table.entry_coin, 100);

  select count(*)
  into v_player_count
  from public.table_players
  where table_id = p_table_id;

  v_pot := v_entry_coin * v_player_count;
  v_system_cut := floor(v_pot * 0.08);
  v_winner_reward := v_pot - v_system_cut;

  -------------------------------------------------
  -- SNAPSHOT
  -------------------------------------------------

  if p_slots is null then
    raise exception 'SLOTS_REQUIRED';
  end if;

  if jsonb_array_length(p_slots) <> 26 then
    raise exception 'INVALID_SLOT_COUNT';
  end if;

  v_slots := p_slots;

  insert into public.table_finish_snapshots(
    table_id,
    players
  )
  values(
    p_table_id,
    jsonb_build_object(
      'players', jsonb_build_array(
        jsonb_build_object(
          'user_id', p_user_id,
          'is_winner', true,
          'slots', v_slots
        )
      )
    )
  );

  -------------------------------------------------
  -- WINNER
  -------------------------------------------------

  update public.profiles
  set coins = coalesce(coins, 0) + v_winner_reward,
      rating = coalesce(rating, 1200) + v_rating_reward
  where id = p_user_id;

  insert into public.wallet_transactions(
    user_id,
    amount,
    reason
  )
  values(
    p_user_id,
    v_winner_reward,
    'game_win'
  );

  begin
    insert into public.rating_transactions(
      user_id,
      amount,
      type,
      note
    )
    values(
      p_user_id,
      v_rating_reward,
      'game_win',
      'winner rating reward'
    );
  exception when others then
    null;
  end;

  -------------------------------------------------
  -- SYSTEM RAKE
  -------------------------------------------------

  insert into public.wallet_transactions(
    user_id,
    amount,
    reason
  )
  values(
    '00000000-0000-0000-0000-000000000000',
    v_system_cut,
    'system_rake'
  );

  -------------------------------------------------
  -- LOSERS
  -------------------------------------------------

  update public.profiles
  set rating = greatest(coalesce(rating, 1200) - v_rating_loss, 500)
  where id in (
    select user_id
    from public.table_players
    where table_id = p_table_id
      and user_id <> p_user_id
  );

  begin
    insert into public.rating_transactions(
      user_id,
      amount,
      type,
      note
    )
    select
      tp.user_id,
      -v_rating_loss,
      'game_lose',
      'loser rating penalty'
    from public.table_players tp
    where tp.table_id = p_table_id
      and tp.user_id <> p_user_id;
  exception when others then
    null;
  end;

  -------------------------------------------------
  -- RESET TABLE
  -------------------------------------------------

  delete from public.table_discards
  where table_id = p_table_id;

  update public.table_players
  set hand = '[]'::jsonb,
      consecutive_timeouts = 0,
      is_double_mode = false
  where table_id = p_table_id;

  update public.tables
  set status = 'waiting',
      current_turn = v_next_turn,
      deck = '[]'::jsonb,
      turn_started_at = now(),
      last_winner_user_id = p_user_id,
      last_finish_at = now()
  where id = p_table_id;

  return jsonb_build_object(
    'ok', true,
    'action', 'finish',
    'table_id', p_table_id,
    'winner_user_id', p_user_id,
    'coin_reward', v_winner_reward,
    'rating_reward', v_rating_reward,
    'next_turn', v_next_turn
  );
end if;

-------------------------------------------------
-- NORMAL DISCARD
-------------------------------------------------

update public.tables
set current_turn = v_next_turn,
    turn_started_at = now(),
    last_winner_user_id = null
where id = p_table_id;

return jsonb_build_object(
  'ok', true,
  'action', 'discard',
  'table_id', p_table_id,
  'seat_index', v_player.seat_index,
  'next_turn', v_next_turn,
  'turn_started_at', now(),
  'hand', v_hand
);

end;
$$;

grant execute on function public.game_discard(uuid, uuid, jsonb, boolean, jsonb, boolean)
to authenticated, service_role;

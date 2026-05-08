-- Production hotfix for false INVALID_FINISH cases.
-- Goal:
-- 1) Keep validation server-authoritative.
-- 2) Accept valid finishes even if slot separators/glitches occur.
-- 3) Never accept foreign/missing tiles (hand <-> slots id multiset must match).

create or replace function public._okey_is_joker(p_tile jsonb)
returns boolean
language sql
immutable
as $$
  select coalesce(
    (p_tile->>'isJoker')::boolean,       -- camelCase (mobile payloads)
    (p_tile->>'joker')::boolean,
    (p_tile->>'is_joker')::boolean,
    (p_tile->>'isFakeJoker')::boolean,
    (p_tile->>'fake_joker')::boolean,
    (p_tile->>'is_fake_joker')::boolean,
    false
  );
$$;

create or replace function public._okey_tiles_from_slots(p_slots jsonb)
returns jsonb
language sql
immutable
as $$
  select coalesce(
    jsonb_agg(e.value->'tile' order by e.idx),
    '[]'::jsonb
  )
  from jsonb_array_elements(p_slots) with ordinality as e(value, idx)
  where e.value->'tile' is not null;
$$;

create or replace function public._okey_same_tile_id_multiset(
  p_a jsonb,
  p_b jsonb
)
returns boolean
language sql
immutable
as $$
  with a as (
    select v->>'id' as id, count(*) as c
    from jsonb_array_elements(coalesce(p_a, '[]'::jsonb)) x(v)
    group by v->>'id'
  ),
  b as (
    select v->>'id' as id, count(*) as c
    from jsonb_array_elements(coalesce(p_b, '[]'::jsonb)) x(v)
    group by v->>'id'
  ),
  d as (
    select coalesce(a.id, b.id) as id,
           coalesce(a.c, 0) as ca,
           coalesce(b.c, 0) as cb
    from a
    full outer join b on a.id = b.id
  )
  select not exists (
    select 1
    from d
    where id is null or ca <> cb
  );
$$;

-- Patch only finish validation part in game_discard.
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
  v_slots_tiles jsonb;
  v_finish_ok boolean := false;
begin

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

v_hand := coalesce(v_player.hand, '[]'::jsonb);
v_before := jsonb_array_length(v_hand);

if v_before <> 15 then
  raise exception 'DISCARD_REQUIRES_15';
end if;

v_hand := public._hand_remove_first(v_hand, p_tile);
v_after := jsonb_array_length(v_hand);

if v_after <> v_before - 1 then
  raise exception 'TILE_NOT_IN_HAND';
end if;

if p_finish then
  -- Primary source of truth: player's hand after discard.
  v_finish_ok := public.okey_can_finish(v_hand);

  -- Recovery path for client slot-glitch/timing:
  -- if slots are supplied, and exactly same tile-id multiset as hand,
  -- evaluate slots-extracted tiles too.
  if (not v_finish_ok) and p_slots is not null and jsonb_typeof(p_slots) = 'array' then
    v_slots_tiles := public._okey_tiles_from_slots(p_slots);
    if jsonb_array_length(v_slots_tiles) = 14
       and public._okey_same_tile_id_multiset(v_slots_tiles, v_hand)
    then
      v_finish_ok := public.okey_can_finish(v_slots_tiles);
    end if;
  end if;

  if not v_finish_ok then
    raise exception 'INVALID_FINISH';
  end if;
end if;

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

update public.table_players
set hand = v_hand,
    consecutive_timeouts =
      case
        when p_is_player_action then 0
        else consecutive_timeouts
      end
where id = v_player.id;

v_next_turn := (v_table.current_turn + 1) % v_table.max_players;

if p_finish then
  v_entry_coin := coalesce(v_table.entry_coin, 100);

  select count(*)
  into v_player_count
  from public.table_players
  where table_id = p_table_id;

  v_pot := v_entry_coin * v_player_count;
  v_system_cut := floor(v_pot * 0.08);
  v_winner_reward := v_pot - v_system_cut;

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

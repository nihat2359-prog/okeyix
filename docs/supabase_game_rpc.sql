-- Server-authoritative game RPC pack (performance-first)
-- Apply in Supabase SQL editor.

create extension if not exists pgcrypto;

alter table public.tables
  add column if not exists turn_started_at timestamptz default now();

alter table public.tables
  add column if not exists last_winner_user_id uuid;

alter table public.tables
  add column if not exists last_finish_at timestamptz;

alter table public.table_players
  add column if not exists consecutive_timeouts integer default 0;

alter table public.table_players
  add column if not exists is_double_mode boolean default false;

-- Utility: normalize tile joker flag
create or replace function public._tile_is_joker(t jsonb)
returns boolean
language sql
immutable
as $$
  select coalesce((t->>'joker')::boolean, false)
      or coalesce((t->>'is_joker')::boolean, false)
$$;

-- Utility: tile equality for hand/discard matching
create or replace function public._tile_eq(a jsonb, b jsonb)
returns boolean
language sql
immutable
as $$
  select
    coalesce(a->>'color','') = coalesce(b->>'color','')
    and coalesce(a->>'number','') = coalesce(b->>'number','')
    and public._tile_is_joker(a) = public._tile_is_joker(b)
    and coalesce((a->>'fake_joker')::boolean, coalesce((a->>'is_fake_joker')::boolean, false))
      = coalesce((b->>'fake_joker')::boolean, coalesce((b->>'is_fake_joker')::boolean, false))
$$;

-- Utility: remove first matching tile from jsonb hand array
create or replace function public._hand_remove_first(hand jsonb, tile jsonb)
returns jsonb
language plpgsql
immutable
as $$
declare
  out_hand jsonb := '[]'::jsonb;
  removed boolean := false;
  e jsonb;
begin
  if hand is null then
    return '[]'::jsonb;
  end if;

  for e in select value from jsonb_array_elements(hand)
  loop
    if (not removed) and public._tile_eq(e, tile) then
      removed := true;
    else
      out_hand := out_hand || jsonb_build_array(e);
    end if;
  end loop;

  return out_hand;
end;
$$;

create or replace function public.game_draw(
  p_table_id uuid,
  p_user_id uuid,
  p_source text,
  p_from_seat integer default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_table record;
  v_player record;
  v_hand jsonb;
  v_deck jsonb;
  v_tile jsonb;
  v_deck_count int;
  v_discard record;
begin
  select id, status, current_turn, max_players, deck, turn_started_at
    into v_table
  from public.tables
  where id = p_table_id
  for update;

  if not found then
    raise exception 'TABLE_NOT_FOUND';
  end if;
  if v_table.status <> 'playing' then
    raise exception 'TABLE_NOT_PLAYING';
  end if;

  select id, seat_index, hand
    into v_player
  from public.table_players
  where table_id = p_table_id and user_id = p_user_id
  for update;

  if not found then
    raise exception 'PLAYER_NOT_IN_TABLE';
  end if;
  if v_player.seat_index <> v_table.current_turn then
    raise exception 'NOT_YOUR_TURN';
  end if;

  v_hand := coalesce(v_player.hand, '[]'::jsonb);
  if jsonb_array_length(v_hand) >= 15 then
    raise exception 'HAND_ALREADY_15';
  end if;

  if p_source = 'closed' then
    v_deck := coalesce(v_table.deck, '[]'::jsonb);
    v_deck_count := jsonb_array_length(v_deck);
    -- deck[0] gosterge tasi; cekilemez.
    if v_deck_count <= 1 then
      raise exception 'DECK_EMPTY';
    end if;

    v_tile := v_deck -> (v_deck_count - 1);
    v_deck := v_deck #- array[(v_deck_count - 1)::text];

    update public.tables
      set deck = v_deck
    where id = p_table_id;

  elsif p_source = 'discard' then
    select id, seat_index, tile
      into v_discard
    from public.table_discards
    where table_id = p_table_id
      and drawn_at is null
      and (p_from_seat is null or seat_index = p_from_seat)
    order by created_at desc
    limit 1
    for update;

    if not found then
      raise exception 'DISCARD_EMPTY';
    end if;

    update public.table_discards
      set drawn_by_user_id = p_user_id,
          drawn_at = now()
    where id = v_discard.id;

    v_tile := v_discard.tile;
  else
    raise exception 'INVALID_DRAW_SOURCE';
  end if;

  v_hand := v_hand || jsonb_build_array(v_tile);

  update public.table_players
    set hand = v_hand
  where id = v_player.id;

  return jsonb_build_object(
    'ok', true,
    'action', 'draw',
    'table_id', p_table_id,
    'seat_index', v_player.seat_index,
    'current_turn', v_table.current_turn,
    'turn_started_at', coalesce(v_table.turn_started_at, now()),
    'hand', v_hand
  );
end;
$$;

drop function if exists public.game_discard(uuid, uuid, jsonb, boolean, boolean);

create or replace function public.game_discard(
  p_table_id uuid,
  p_user_id uuid,
  p_tile jsonb,
  p_finish boolean default false
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
  v_coin_reward int;
  v_rating_reward int;
  v_rating_loss int;
begin
  select id, status, current_turn, max_players, entry_coin
    into v_table
  from public.tables
  where id = p_table_id
  for update;

  if not found then
    raise exception 'TABLE_NOT_FOUND';
  end if;
  if v_table.status <> 'playing' then
    raise exception 'TABLE_NOT_PLAYING';
  end if;

  select id, seat_index, hand
    into v_player
  from public.table_players
  where table_id = p_table_id and user_id = p_user_id
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

  insert into public.table_discards(
    table_id, seat_index, discarded_by_user_id, tile
  ) values (
    p_table_id, v_player.seat_index, p_user_id, p_tile
  );

  update public.table_players
    set hand = v_hand
  where id = v_player.id;

  update public.table_players
    set consecutive_timeouts = 0
  where id = v_player.id;

  v_next_turn := (v_table.current_turn + 1) % v_table.max_players;

  if p_finish then
    v_coin_reward := greatest(coalesce(v_table.entry_coin, 100), 100);
    v_rating_reward := 10;
    v_rating_loss := greatest(1, floor(v_rating_reward / 2.0));

    update public.profiles
      set coins = coalesce(coins, 0) + v_coin_reward,
          rating = coalesce(rating, 1000) + v_rating_reward
    where id = p_user_id;

    update public.users
      set rating = coalesce(rating, 1000) + v_rating_reward
    where id = p_user_id;

    begin
      insert into public.wallet_transactions(user_id, amount, type, note)
      values (p_user_id, v_coin_reward, 'game_win', 'winner reward');
    exception when others then
      -- Optional table/columns or constraints; ignore if schema differs.
      null;
    end;

    begin
      insert into public.rating_transactions(user_id, amount, type, note)
      values (p_user_id, v_rating_reward, 'game_win', 'winner reward');
    exception when others then
      -- Optional table/columns or constraints; ignore if schema differs.
      null;
    end;

    -- Losers lose rating (with floor protection).
    update public.profiles p
      set rating = greatest(coalesce(p.rating, 1200) - v_rating_loss, 500)
    where p.id in (
      select tp.user_id
      from public.table_players tp
      where tp.table_id = p_table_id
        and tp.user_id <> p_user_id
    );

    update public.users u
      set rating = greatest(coalesce(u.rating, 1200) - v_rating_loss, 500)
    where u.id in (
      select tp.user_id
      from public.table_players tp
      where tp.table_id = p_table_id
        and tp.user_id <> p_user_id
    );

    begin
      insert into public.rating_transactions(user_id, amount, type, note)
      select
        tp.user_id,
        -v_rating_loss,
        'game_lose',
        'loser rating penalty'
      from public.table_players tp
      where tp.table_id = p_table_id
        and tp.user_id <> p_user_id;
    exception when others then
      -- Optional table/columns or constraints; ignore if schema differs.
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
      'winner_seat_index', v_player.seat_index,
      'winner_user_id', p_user_id,
      'coin_reward', v_coin_reward,
      'rating_reward', v_rating_reward,
      'next_turn', v_next_turn,
      'turn_started_at', now(),
      'hand', v_hand
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

create or replace function public.game_timeout_move(
  p_table_id uuid,
  p_user_id uuid
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_player record;
  v_table record;
  v_hand jsonb;
  v_pick jsonb;
  v_result jsonb;
  v_deck jsonb;
  v_deck_count int;
  v_timeout_count int;
  v_remaining_players int;
  v_penalty int;
  e jsonb;
begin
  select id, status, current_turn, max_players, deck, turn_seconds, turn_started_at, entry_coin
    into v_table
  from public.tables
  where id = p_table_id
  for update;

  if not found then
    raise exception 'TABLE_NOT_FOUND';
  end if;
  if v_table.status <> 'playing' then
    raise exception 'TABLE_NOT_PLAYING';
  end if;

  select id, seat_index, hand, consecutive_timeouts
    into v_player
  from public.table_players
  where table_id = p_table_id and user_id = p_user_id
  for update;

  if not found then
    raise exception 'PLAYER_NOT_IN_TABLE';
  end if;
  if v_player.seat_index <> v_table.current_turn then
    raise exception 'NOT_YOUR_TURN';
  end if;

  if now() < coalesce(v_table.turn_started_at, now()) + make_interval(secs => coalesce(v_table.turn_seconds,15)) then
    raise exception 'TURN_NOT_EXPIRED';
  end if;

  v_hand := coalesce(v_player.hand, '[]'::jsonb);

  -- If no draw yet (14), force draw from closed
  if jsonb_array_length(v_hand) = 14 then
    v_deck := coalesce(v_table.deck, '[]'::jsonb);
    v_deck_count := jsonb_array_length(v_deck);
    -- deck[0] is indicator; not drawable.
    if v_deck_count <= 1 then
      raise exception 'DECK_EMPTY';
    end if;
    v_pick := v_deck -> (v_deck_count - 1);
    v_deck := v_deck #- array[(v_deck_count - 1)::text];
    v_hand := v_hand || jsonb_build_array(v_pick);

    update public.tables
      set deck = v_deck
    where id = p_table_id;

    -- Persist forced draw before discard validation (expects 15 tiles).
    update public.table_players
      set hand = v_hand
    where id = v_player.id;
  end if;

  -- Pick discard candidate from right-most non-joker tile
  select value into v_pick
  from jsonb_array_elements(v_hand)
  where not public._tile_is_joker(value)
  order by 1 desc
  limit 1;

  if v_pick is null then
    -- fallback: first tile if all jokers (edge case)
    v_pick := v_hand->0;
  end if;

  v_result := public.game_discard(p_table_id, p_user_id, v_pick, false);

  v_timeout_count := coalesce(v_player.consecutive_timeouts, 0) + 1;

  update public.table_players
    set consecutive_timeouts = v_timeout_count
  where table_id = p_table_id
    and user_id = p_user_id
  returning consecutive_timeouts into v_timeout_count;

  if coalesce(v_timeout_count, 0) >= 3 then
    v_penalty := greatest(coalesce(v_table.entry_coin, 100), 100);

    begin
      update public.profiles
        set coins = greatest(0, coalesce(coins, 0) - v_penalty)
      where id = p_user_id;

      insert into public.wallet_transactions(user_id, amount, type, note)
      values (p_user_id, -v_penalty, 'timeout_penalty', '3x consecutive timeout');
    exception when others then
      null;
    end;

    delete from public.table_players
    where table_id = p_table_id
      and user_id = p_user_id;

    select count(*)
      into v_remaining_players
    from public.table_players
    where table_id = p_table_id;

    delete from public.table_discards
    where table_id = p_table_id;

    update public.table_players
      set hand = '[]'::jsonb,
          consecutive_timeouts = 0,
          is_double_mode = false
    where table_id = p_table_id;

    update public.tables
      set status = 'waiting',
          current_turn = 0,
          deck = '[]'::jsonb,
          turn_started_at = now()
    where id = p_table_id;

    return jsonb_build_object(
      'ok', true,
      'action', 'player_kicked_timeout',
      'table_id', p_table_id,
      'kicked_user_id', p_user_id,
      'penalty', v_penalty,
      'remaining_players', v_remaining_players
    );
  end if;

  return v_result || jsonb_build_object('timeout_count', coalesce(v_timeout_count, 1));
end;
$$;

grant execute on function public.game_draw(uuid, uuid, text, integer) to authenticated, service_role;
grant execute on function public.game_discard(uuid, uuid, jsonb, boolean) to authenticated, service_role;
grant execute on function public.game_timeout_move(uuid, uuid) to authenticated, service_role;

-- Start game with deterministic server-side dealing.
create or replace function public.start_game(p_table_id uuid)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_table record;
  v_player_count int;
  v_dealt_count int;
  v_deck_size int;
  v_indicator jsonb;
  v_okey_value int;
  v_okey_color text;
begin
  select id, status, max_players
    into v_table
  from public.tables
  where id = p_table_id
  for update;

  if not found then
    raise exception 'TABLE_NOT_FOUND';
  end if;

  if v_table.status = 'playing' then
    return jsonb_build_object('ok', true, 'already_playing', true, 'table_id', p_table_id);
  end if;

  if v_table.status <> 'waiting' then
    raise exception 'TABLE_NOT_WAITING';
  end if;

  select count(*)
    into v_player_count
  from public.table_players
  where table_id = p_table_id;

  if v_player_count <> v_table.max_players then
    raise exception 'TABLE_NOT_FULL';
  end if;

  -- Fresh start: clear old discards for this table.
  delete from public.table_discards
  where table_id = p_table_id;

  -- Shuffle deck and distribute hands (seat 0: 15, others: 14).
  -- Okey kurali:
  -- - Kapali destenin en ustunden 1 gosterge ayrilir (oyunda cekilmez).
  -- - Gosterge +1 ayni renkte olan taslar gercek okey olur (is_joker=true).
  -- - Baslangictaki 2 joker tasi sahte okeydir (is_fake_joker=true).
  create temp table _tmp_shuffled_tiles on commit drop as
  with base_tiles as (
    select jsonb_build_object(
      'color', c,
      'number', n,
      'joker', false,
      'is_joker', false,
      'fake_joker', false,
      'is_fake_joker', false
    ) as tile
    from unnest(array['red','blue','black','yellow']) as c
    cross join generate_series(1,13) as n
    cross join generate_series(1,2) as dup
  ),
  fake_jokers as (
    select jsonb_build_object(
      'color', 'red',
      'number', 0,
      'joker', false,
      'is_joker', false,
      'fake_joker', true,
      'is_fake_joker', true
    ) as tile
    union all
    select jsonb_build_object(
      'color', 'red',
      'number', 0,
      'joker', false,
      'is_joker', false,
      'fake_joker', true,
      'is_fake_joker', true
    ) as tile
  ),
  deck as (
    select tile from base_tiles
    union all
    select tile from fake_jokers
  )
  select
    row_number() over (order by random()) as rn,
    tile
  from deck;

  select max(rn) into v_deck_size
  from _tmp_shuffled_tiles;

  select tile into v_indicator
  from _tmp_shuffled_tiles
  where rn = v_deck_size;

  v_okey_color := coalesce(v_indicator->>'color', 'red');
  v_okey_value := case
    when coalesce((v_indicator->>'number')::int, 1) = 13 then 1
    else coalesce((v_indicator->>'number')::int, 1) + 1
  end;

  -- Gostergeye gore deckteki tas flaglerini normalize et.
  -- Not: gosterge tasi (rn = v_deck_size) oldugu gibi birakilir.
  update _tmp_shuffled_tiles s
  set tile = case
    when coalesce((s.tile->>'fake_joker')::boolean, coalesce((s.tile->>'is_fake_joker')::boolean, false)) then
      jsonb_build_object(
        'color', v_okey_color,
        'number', v_okey_value,
        'joker', false,
        'is_joker', false,
        'fake_joker', true,
        'is_fake_joker', true
      )
    when coalesce((s.tile->>'color'), '') = v_okey_color
      and coalesce((s.tile->>'number')::int, -1) = v_okey_value then
      jsonb_build_object(
        'color', v_okey_color,
        'number', v_okey_value,
        'joker', true,
        'is_joker', true,
        'fake_joker', false,
        'is_fake_joker', false
      )
    else
      jsonb_build_object(
        'color', coalesce(s.tile->>'color','red'),
        'number', coalesce((s.tile->>'number')::int, 1),
        'joker', false,
        'is_joker', false,
        'fake_joker', false,
        'is_fake_joker', false
      )
  end
  where s.rn < v_deck_size;

  with players as (
    select
      id,
      seat_index,
      row_number() over (order by seat_index) - 1 as p_idx
    from public.table_players
    where table_id = p_table_id
  ),
  hand_ranges as (
    select
      id,
      seat_index,
      case when p_idx = 0 then 1 else (14 * p_idx + 2) end as start_rn,
      case when p_idx = 0 then 15 else (15 + 14 * p_idx) end as end_rn
    from players
  ),
  hand_data as (
    select
      hr.id as player_id,
      coalesce(
        jsonb_agg(s.tile order by s.rn) filter (
          where s.rn between hr.start_rn and hr.end_rn
        ),
        '[]'::jsonb
      ) as hand
    from hand_ranges hr
    cross join _tmp_shuffled_tiles s
    group by hr.id
  )
  update public.table_players tp
     set hand = hd.hand,
         consecutive_timeouts = 0,
         is_double_mode = false
    from hand_data hd
   where tp.id = hd.player_id;

  v_dealt_count := 15 + 14 * (v_table.max_players - 1);

  update public.tables
     set deck = jsonb_build_array(v_indicator) || coalesce(
           (
             select jsonb_agg(tile order by rn)
             from _tmp_shuffled_tiles
             where rn > v_dealt_count
               and rn < v_deck_size
           ),
           '[]'::jsonb
         ),
         status = 'playing',
         current_turn = 0,
         turn_started_at = now(),
         shuffle_seed = gen_random_uuid()::text
   where id = p_table_id;

  return jsonb_build_object(
    'ok', true,
    'table_id', p_table_id,
    'players', v_player_count,
    'dealt_count', v_dealt_count
  );
end;
$$;

grant execute on function public.start_game(uuid) to authenticated, service_role;

create or replace function public.game_finish(
  p_table_id uuid,
  p_user_id uuid,
  p_slots jsonb,
  p_last_tile jsonb
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_table record;
  v_player record;

  v_hand jsonb;

  v_entry_coin int;
  v_player_count int;

  v_contribution int;
  v_current_pot int;
  v_winner_reward int;

  v_is_valid boolean;
  v_is_double boolean;
  v_is_okey boolean;

  v_slots jsonb;
  v_tiles_for_pairs jsonb := '[]'::jsonb;
  v_last_tile_id text;
  v_removed_user_ids jsonb := '[]'::jsonb;
  v_invalid_tile_ids jsonb := '[]'::jsonb;
begin

  if p_slots is null or jsonb_typeof(p_slots) <> 'array' then
    raise exception 'INVALID_SLOT_PAYLOAD';
  end if;

  if jsonb_array_length(p_slots) <> 26 then
    raise exception 'INVALID_SLOT_COUNT';
  end if;

  v_last_tile_id := p_last_tile->>'id';
  if v_last_tile_id is null or btrim(v_last_tile_id) = '' then
    raise exception 'INVALID_LAST_TILE';
  end if;

  v_slots := p_slots;

  -------------------------------------------------
  -- TABLE LOCK
  -------------------------------------------------
  select id, entry_coin, pot_amount, status
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

  -------------------------------------------------
  -- PLAYER + HAND
  -------------------------------------------------
  select id, hand
  into v_player
  from public.table_players
  where table_id = p_table_id
    and user_id = p_user_id
  for update;

  if not found then
    raise exception 'PLAYER_NOT_IN_TABLE';
  end if;

  v_hand := coalesce(v_player.hand, '[]'::jsonb);

  if jsonb_array_length(v_hand) <> 15 then
    raise exception 'INVALID_HAND_COUNT';
  end if;

  -------------------------------------------------
  -- DUPLICATE CHECK
  -------------------------------------------------
  if exists (
    select tile_id
    from (
      select (value->'tile'->>'id') as tile_id
      from jsonb_array_elements(v_slots)
      where value->'tile' is not null
    ) t
    group by tile_id
    having count(*) > 1
  ) then
    raise exception 'DUPLICATE_TILE';
  end if;

  -------------------------------------------------
  -- DOUBLE MODE (server state)
  -------------------------------------------------
  select coalesce(tp.is_double_mode, false)
  into v_is_double
  from public.table_players tp
  where tp.table_id = p_table_id
    and tp.user_id = p_user_id
  for update;

  select coalesce(jsonb_agg(e.value->'tile' order by e.ord), '[]'::jsonb)
  into v_tiles_for_pairs
  from jsonb_array_elements(v_slots) with ordinality as e(value, ord)
  where e.value->'tile' is not null;

  -------------------------------------------------
  -- SOLVER
  -------------------------------------------------
  if v_is_double then
    if not public._okey_is_pairs_finish(v_tiles_for_pairs) then
      v_invalid_tile_ids := public.okey_invalid_pairs_tiles(v_slots);
      return jsonb_build_object(
        'ok', false,
        'error_code', 'INVALID_DOUBLE_FINISH',
        'invalid_tile_ids', coalesce(v_invalid_tile_ids, '[]'::jsonb)
      );
    end if;
  else
    v_is_valid := public.okey_validate_finish(v_slots);
    if not v_is_valid then
      v_invalid_tile_ids := public.okey_invalid_finish_tiles(v_slots);
      return jsonb_build_object(
        'ok', false,
        'error_code', 'INVALID_FINISH',
        'invalid_tile_ids', coalesce(v_invalid_tile_ids, '[]'::jsonb)
      );
    end if;
  end if;

  -------------------------------------------------
  -- OKEY FINISH
  -------------------------------------------------
  v_is_okey :=
    exists (
      select 1
      from jsonb_array_elements(v_hand) h
      where h->>'id' = v_last_tile_id
        and coalesce((h->>'is_joker')::boolean, false) = true
        and coalesce((h->>'is_fake_joker')::boolean, false) = false
    );

  -------------------------------------------------
  -- REWARD
  -------------------------------------------------
  v_entry_coin := greatest(coalesce(v_table.entry_coin, 100), 50);

  select count(*) into v_player_count
  from public.table_players
  where table_id = p_table_id;

  v_contribution := (v_entry_coin * 10) / 100;
  v_current_pot := coalesce(v_table.pot_amount, 0);

  v_winner_reward :=
    (v_entry_coin * v_player_count)
    - (v_player_count * v_contribution);

  if v_is_double or v_is_okey then
    v_winner_reward := v_winner_reward + v_current_pot;
  end if;

  -------------------------------------------------
  -- WINNER COIN
  -------------------------------------------------
  update public.profiles
  set coins = coalesce(coins, 0) + v_winner_reward
  where id = p_user_id;

  -------------------------------------------------
  -- WIN / LOSS STATS (users) [safe / non-blocking]
  -------------------------------------------------
  begin
    if to_regclass('public.users') is not null then
      update public.users
      set wins = coalesce(wins, 0) + 1
      where id = p_user_id;

      update public.users u
      set losses = coalesce(losses, 0) + 1
      where u.id in (
        select tp.user_id
        from public.table_players tp
        where tp.table_id = p_table_id
          and tp.user_id <> p_user_id
      );
    end if;
  exception
    when others then
      null;
  end;

  insert into public.wallet_transactions(user_id, amount, reason)
  values (p_user_id, v_winner_reward, 'game_win');

  -------------------------------------------------
  -- RECENT OPPONENTS (kullanici basi son 20)
  -------------------------------------------------
  begin
    if to_regclass('public.recent_opponents') is not null then
      insert into public.recent_opponents(
        user_id,
        opponent_user_id,
        last_table_id,
        last_played_at
      )
      select
        a.user_id,
        b.user_id,
        p_table_id,
        now()
      from public.table_players a
      join public.table_players b
        on a.table_id = b.table_id
       and a.user_id <> b.user_id
      where a.table_id = p_table_id
      on conflict (user_id, opponent_user_id)
      do update set
        last_table_id = excluded.last_table_id,
        last_played_at = excluded.last_played_at;

      delete from public.recent_opponents ro
      where ro.id in (
        select id
        from (
          select
            id,
            row_number() over (
              partition by user_id
              order by last_played_at desc, id desc
            ) as rn
          from public.recent_opponents
        ) ranked
        where ranked.rn > 20
      );
    end if;
  exception
    when others then
      null;
  end;

  -------------------------------------------------
  -- NEW ROUND: remove players with low coins
  -------------------------------------------------
  with removed as (
    delete from public.table_players tp
    where tp.table_id = p_table_id
      and exists (
        select 1
        from public.profiles pr
        where pr.id = tp.user_id
          and coalesce(pr.coins, 0) < v_entry_coin
      )
    returning tp.user_id
  )
  select coalesce(jsonb_agg(user_id), '[]'::jsonb)
  into v_removed_user_ids
  from removed;

  -------------------------------------------------
  -- RESET
  -------------------------------------------------
  delete from public.table_discards
  where table_id = p_table_id;

  update public.table_players
  set hand = '[]'::jsonb,
      is_double_mode = false
  where table_id = p_table_id;

  update public.tables
  set
    ready_since = now(),
    status = 'waiting',
    deck = '[]'::jsonb,
    last_winner_user_id = p_user_id,
    last_win_amount = v_winner_reward,
    last_finish_tile = p_last_tile,
    last_final_slots = p_slots,
    last_finish_at = now(),
    pot_amount = case
      when v_is_double or v_is_okey then 0
      else pot_amount
    end
  where id = p_table_id;

  return jsonb_build_object(
    'ok', true,
    'winner_user_id', p_user_id,
    'win_amount', v_winner_reward,
    'finish_type',
      case
        when v_is_okey then 'okey'
        when v_is_double then 'double'
        else 'normal'
      end,
    'is_okey', v_is_okey,
    'is_double', v_is_double,
    'winner_name',
      (select username from public.profiles where id = p_user_id),
    'removed_user_ids', v_removed_user_ids
  );

end;
$$;

grant execute on function public.game_finish(uuid, uuid, jsonb, jsonb) to authenticated, service_role;

-- Server-authoritative invalid finish diagnostics
-- Goal: keep existing game_finish success flow intact, only enrich INVALID_FINISH path.

create or replace function public.okey_invalid_finish_tiles(p_slots jsonb)
returns jsonb
language plpgsql
as $$
declare
  v_groups jsonb := '[]'::jsonb;
  v_current jsonb := '[]'::jsonb;
  v_item jsonb;
  v_group jsonb;

  v_invalid_ids jsonb := '[]'::jsonb;
  v_valid_ids jsonb := '[]'::jsonb;
  v_group_ids jsonb := '[]'::jsonb;

  v_total int := 0;
  v_vals int[];
  v_colors text[];
  v_joker int;
  v_ids text[];
  v_sorted int[];
  v_gap int;
  i int;
begin
  if p_slots is null or jsonb_typeof(p_slots) <> 'array' then
    return '[]'::jsonb;
  end if;

  -- GROUP SPLIT (same logic style as can_finish)
  for v_item in select value from jsonb_array_elements(p_slots)
  loop
    if v_item->'tile' is null then
      if jsonb_array_length(v_current) > 0 then
        v_groups := v_groups || jsonb_build_array(v_current);
        v_current := '[]'::jsonb;
      end if;
    else
      v_current := v_current || jsonb_build_array(v_item->'tile');
    end if;
  end loop;

  if jsonb_array_length(v_current) > 0 then
    v_groups := v_groups || jsonb_build_array(v_current);
  end if;

  -- GROUP LOOP
  for v_group in select value from jsonb_array_elements(v_groups)
  loop
    -- Collect ids for this group once
    select coalesce(jsonb_agg(value->>'id'), '[]'::jsonb)
    into v_group_ids
    from jsonb_array_elements(v_group);

    if jsonb_array_length(v_group) < 3 then
      v_invalid_ids := v_invalid_ids || v_group_ids;
      continue;
    end if;

    v_total := v_total + jsonb_array_length(v_group);

    -- duplicate tile id
    select array_agg(value->>'id') into v_ids
    from jsonb_array_elements(v_group);

    if (select count(*) from unnest(v_ids)) <>
       (select count(distinct x) from unnest(v_ids) x)
    then
      -- Mark duplicate ids only
      v_invalid_ids := v_invalid_ids || coalesce((
        select jsonb_agg(tile_id)
        from (
          select tile_id
          from (
            select x as tile_id, count(*) as c
            from unnest(v_ids) x
            group by x
          ) d
          where d.c > 1
        ) dd
      ), '[]'::jsonb);
      continue;
    end if;

    -- joker count
    select count(*) into v_joker
    from jsonb_array_elements(v_group)
    where coalesce(
      (value->>'isJoker')::boolean,
      (value->>'is_joker')::boolean,
      (value->>'joker')::boolean,
      false
    ) = true;

    -- values/colors (joker hariç)
    select array_agg(coalesce((value->>'value')::int, (value->>'number')::int))
    into v_vals
    from jsonb_array_elements(v_group)
    where coalesce(
      (value->>'isJoker')::boolean,
      (value->>'is_joker')::boolean,
      (value->>'joker')::boolean,
      false
    ) = false;

    select array_agg(value->>'color')
    into v_colors
    from jsonb_array_elements(v_group)
    where coalesce(
      (value->>'isJoker')::boolean,
      (value->>'is_joker')::boolean,
      (value->>'joker')::boolean,
      false
    ) = false;

    -- SET
    if (coalesce(array_length(v_vals,1),0) + v_joker) between 3 and 4
       and (
         v_vals is null
         or (select count(distinct x) from unnest(v_vals) x) = 1
       )
       and (
         v_colors is null
         or (select count(distinct x) from unnest(v_colors) x) = array_length(v_colors,1)
       )
    then
      v_valid_ids := v_valid_ids || v_group_ids;
      continue;
    end if;

    -- RUN checks
    if v_colors is null or
       (select count(distinct x) from unnest(v_colors) x) <> 1
    then
      v_invalid_ids := v_invalid_ids || v_group_ids;
      continue;
    end if;

    select array_agg(x order by x)
    into v_sorted
    from unnest(v_vals) x;

    -- duplicate value olmaz
    if exists (
      select 1 from (
        select x, count(*) c from unnest(v_sorted) x group by x
      ) t where c > 1
    ) then
      v_invalid_ids := v_invalid_ids || v_group_ids;
      continue;
    end if;

    -- NORMAL GAP CHECK
    v_gap := 0;
    for i in 2..array_length(v_sorted,1)
    loop
      if v_sorted[i] = v_sorted[i-1] + 1 then
        continue;
      end if;
      v_gap := v_gap + (v_sorted[i] - v_sorted[i-1] - 1);
    end loop;

    if v_gap <= v_joker then
      v_valid_ids := v_valid_ids || v_group_ids;
      continue;
    end if;

    -- WRAP CHECK (13 -> 1)
    select array_agg(
      case when x = 1 then 14 else x end
      order by case when x = 1 then 14 else x end
    )
    into v_sorted
    from unnest(v_vals) x;

    v_gap := 0;
    for i in 2..array_length(v_sorted,1)
    loop
      if v_sorted[i] = v_sorted[i-1] + 1 then
        continue;
      end if;
      v_gap := v_gap + (v_sorted[i] - v_sorted[i-1] - 1);
    end loop;

    if v_gap <= v_joker then
      v_valid_ids := v_valid_ids || v_group_ids;
      continue;
    end if;

    -- Group fails both set and run
    v_invalid_ids := v_invalid_ids || v_group_ids;
  end loop;

  -- TOTAL check
  if v_total <> 14 then
    -- Only mark tiles that are still unmatched (not already validated in a good group).
    v_invalid_ids := v_invalid_ids || coalesce((
      with all_ids as (
        select value->'tile'->>'id' as id
        from jsonb_array_elements(p_slots)
        where value->'tile' is not null
      ),
      valid_ids as (
        select distinct value as id
        from jsonb_array_elements_text(coalesce(v_valid_ids, '[]'::jsonb))
      )
      select jsonb_agg(a.id)
      from all_ids a
      left join valid_ids v on v.id = a.id
      where a.id is not null
        and btrim(a.id) <> ''
        and v.id is null
    ), '[]'::jsonb);
  end if;

  -- Unique + deterministic output
  return coalesce((
    select jsonb_agg(id order by id)
    from (
      select distinct value::text as id
      from jsonb_array_elements_text(coalesce(v_invalid_ids, '[]'::jsonb))
      where value is not null and btrim(value) <> ''
    ) u
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.okey_invalid_finish_tiles(jsonb) to authenticated, service_role;

create or replace function public._okey_is_pairs_finish(p_tiles jsonb)
returns boolean
language plpgsql
immutable
as $$
declare
  v_pairs int := 0;
  v_joker_count int := 0;
  v_group_count int := 0;
  v_invalid_non_joker int := 0;
begin
  if p_tiles is null or jsonb_typeof(p_tiles) <> 'array' then
    return false;
  end if;

  if jsonb_array_length(p_tiles) <> 14 then
    return false;
  end if;

  -- Non-joker tiles must have usable color/number.
  select count(*)
  into v_invalid_non_joker
  from jsonb_array_elements(p_tiles) t
  where coalesce(
          (t->>'isJoker')::boolean,
          (t->>'is_joker')::boolean,
          (t->>'joker')::boolean,
          false
        ) = false
    and (
      coalesce(t->>'color', '') = ''
      or nullif(coalesce(t->>'number', t->>'value', ''), '') is null
    );

  if v_invalid_non_joker > 0 then
    return false;
  end if;

  -- Count jokers (accept all common flag keys).
  select count(*)
  into v_joker_count
  from jsonb_array_elements(p_tiles) t
  where coalesce(
          (t->>'isJoker')::boolean,
          (t->>'is_joker')::boolean,
          (t->>'joker')::boolean,
          false
        ) = true;

  -- Group identical non-joker stones by color + number/value.
  for v_group_count in
    select count(*) as c
    from jsonb_array_elements(p_tiles) t
    where coalesce(
            (t->>'isJoker')::boolean,
            (t->>'is_joker')::boolean,
            (t->>'joker')::boolean,
            false
          ) = false
    group by
      (t->>'color'),
      coalesce(t->>'number', t->>'value')
  loop
    -- Natural pairs in the group.
    v_pairs := v_pairs + (v_group_count / 2);

    -- Odd singleton may be completed by one joker.
    if (v_group_count % 2) = 1 and v_joker_count > 0 then
      v_pairs := v_pairs + 1;
      v_joker_count := v_joker_count - 1;
    end if;
  end loop;

  -- Remaining jokers may pair with each other.
  v_pairs := v_pairs + (v_joker_count / 2);

  return v_pairs >= 7;
end;
$$;

grant execute on function public._okey_is_pairs_finish(jsonb) to authenticated, service_role;

create or replace function public.okey_invalid_pairs_tiles(p_slots jsonb)
returns jsonb
language plpgsql
as $$
declare
  v_tiles jsonb := '[]'::jsonb;
begin
  if p_slots is null or jsonb_typeof(p_slots) <> 'array' then
    return '[]'::jsonb;
  end if;

  if jsonb_array_length(p_slots) <> 26 then
    return '[]'::jsonb;
  end if;

  -- 26 slot payload -> only occupied tiles in slot order
  select coalesce(jsonb_agg(e.value->'tile' order by e.ord), '[]'::jsonb)
  into v_tiles
  from jsonb_array_elements(p_slots) with ordinality as e(value, ord)
  where e.value->'tile' is not null;

  -- double finish must evaluate exactly 14 tiles
  if jsonb_array_length(v_tiles) <> 14 then
    return coalesce((
      select jsonb_agg(id order by id)
      from (
        select distinct (e.value->'tile'->>'id') as id
        from jsonb_array_elements(p_slots) as e(value)
        where e.value->'tile' is not null
          and coalesce(e.value->'tile'->>'id', '') <> ''
      ) x
    ), '[]'::jsonb);
  end if;

  return coalesce((
    with tiles as (
      select
        t.value as tile,
        coalesce(t.value->>'id', '') as id,
        coalesce(t.value->>'color', '') as color,
        coalesce(t.value->>'number', t.value->>'value', '') as num_txt,
        coalesce(
          (t.value->>'isJoker')::boolean,
          (t.value->>'is_joker')::boolean,
          (t.value->>'joker')::boolean,
          false
        ) as is_joker
      from jsonb_array_elements(v_tiles) as t(value)
    ),
    non_j as (
      select *
      from tiles
      where is_joker = false
    ),
    grp as (
      select
        color,
        num_txt,
        count(*) as c
      from non_j
      where color <> '' and num_txt <> ''
      group by color, num_txt
    ),
    capacity as (
      select
        coalesce(sum(c / 2), 0) as base_pairs,
        coalesce(sum(c % 2), 0) as singles
      from grp
    ),
    joker_ct as (
      select count(*) as j
      from tiles
      where is_joker = true
    ),
    can_finish as (
      select
        (base_pairs + least(singles, j) + ((j - least(singles, j)) / 2)) >= 7 as ok
      from capacity, joker_ct
    ),
    bad as (
      -- if mathematically cannot make 7 pairs, mark all tiles as invalid
      select id
      from tiles
      where id <> ''
        and (select ok from can_finish) = false

      union all

      -- if can finish, but there are malformed non-joker tiles (missing color/number), mark them
      select id
      from non_j
      where id <> ''
        and (color = '' or num_txt = '')
    )
    select jsonb_agg(id order by id)
    from (
      select distinct id
      from bad
      where id <> ''
    ) u
  ), '[]'::jsonb);
end;
$$;

grant execute on function public.okey_invalid_pairs_tiles(jsonb) to authenticated, service_role;

-- -------------------------------------------------------------------
-- game_finish patch (minimal, no success-flow change)
-- Replace only SOLVER + DOUBLE block in function body:
--
-- OLD:
-- v_is_valid := public.okey_validate_finish(v_slots);
--
-- if not v_is_valid then
--   v_invalid_tile_ids := public.okey_invalid_finish_tiles(v_slots);
--   return jsonb_build_object(
--     'ok', false,
--     'error_code', 'INVALID_FINISH',
--     'invalid_tile_ids', coalesce(v_invalid_tile_ids, '[]'::jsonb)
--   );
-- end if;
--
-- v_is_double := public._okey_is_pairs_finish(v_slots);
--
-- NEW (double mode cannot finish from serial):
-- select coalesce(tp.is_double_mode, false)
-- into v_is_double
-- from public.table_players tp
-- where tp.table_id = p_table_id
--   and tp.user_id = p_user_id
-- for update;
--
-- if v_is_double then
--   if not public._okey_is_pairs_finish(v_slots) then
--     v_invalid_tile_ids := public.okey_invalid_pairs_tiles(v_slots);
--     return jsonb_build_object(
--       'ok', false,
--       'error_code', 'INVALID_DOUBLE_FINISH',
--       'invalid_tile_ids', coalesce(v_invalid_tile_ids, '[]'::jsonb)
--     );
--   end if;
-- else
--   v_is_valid := public.okey_validate_finish(v_slots);
--
--   if not v_is_valid then
--     v_invalid_tile_ids := public.okey_invalid_finish_tiles(v_slots);
--
--     return jsonb_build_object(
--       'ok', false,
--       'error_code', 'INVALID_FINISH',
--       'invalid_tile_ids', coalesce(v_invalid_tile_ids, '[]'::jsonb)
--     );
--   end if;
-- end if;
-- -------------------------------------------------------------------

-- -------------------------------------------------------------------
-- TEMP DEBUG (paste into real public.game_finish while diagnosing)
-- -------------------------------------------------------------------
-- declare section additions:
-- v_tiles_from_slots jsonb := '[]'::jsonb;
-- v_last_tile_match_count int := 0;
--
-- right after v_slots is rebuilt:
-- select coalesce(jsonb_agg(e.value->'tile' order by e.ord), '[]'::jsonb)
-- into v_tiles_from_slots
-- from jsonb_array_elements(v_slots) with ordinality as e(value, ord)
-- where e.value->'tile' is not null;
--
-- select count(*)
-- into v_last_tile_match_count
-- from jsonb_array_elements(p_slots) s
-- where s->'tile' is not null
--   and s->'tile'->>'id' = p_last_tile->>'id';
--
-- In DOUBLE error branch, temporarily return extra debug payload:
-- return jsonb_build_object(
--   'ok', false,
--   'error_code', 'INVALID_DOUBLE_FINISH',
--   'invalid_tile_ids', coalesce(v_invalid_tile_ids, '[]'::jsonb),
--   'debug', jsonb_build_object(
--     'input_slot_count', jsonb_array_length(coalesce(p_slots, '[]'::jsonb)),
--     'rebuilt_slot_count', jsonb_array_length(coalesce(v_slots, '[]'::jsonb)),
--     'tiles_from_slots_count', jsonb_array_length(coalesce(v_tiles_from_slots, '[]'::jsonb)),
--     'last_tile_id', coalesce(p_last_tile->>'id', ''),
--     'last_tile_match_count_in_input', v_last_tile_match_count,
--     'tiles_from_slots_ids', (
--       select coalesce(jsonb_agg(x->>'id'), '[]'::jsonb)
--       from jsonb_array_elements(v_tiles_from_slots) x
--     ),
--     'pairs_finish_ok', public._okey_is_pairs_finish(v_tiles_from_slots)
--   )
-- );
--
-- Optional server log:
-- raise notice 'GF_DEBUG table=% user=% last_tile_id=% input_slots=% rebuilt_slots=% tiles=% matches=%',
--   p_table_id, p_user_id, p_last_tile->>'id',
--   jsonb_array_length(coalesce(p_slots, '[]'::jsonb)),
--   jsonb_array_length(coalesce(v_slots, '[]'::jsonb)),
--   jsonb_array_length(coalesce(v_tiles_from_slots, '[]'::jsonb)),
--   v_last_tile_match_count;
-- -------------------------------------------------------------------

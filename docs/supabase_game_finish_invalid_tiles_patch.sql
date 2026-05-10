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

-- -------------------------------------------------------------------
-- game_finish patch (minimal, no success-flow change)
-- Replace only INVALID_FINISH block:
--
-- v_is_valid := public.okey_validate_finish(v_slots);
--
-- if not v_is_valid then
--   return jsonb_build_object(
--     'ok', false,
--     'error_code', 'INVALID_FINISH',
--     'invalid_tile_ids', public.okey_invalid_finish_tiles(v_slots)
--   );
-- end if;
-- -------------------------------------------------------------------

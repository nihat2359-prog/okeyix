-- Robust finish validator (joker-aware, full-hand partition)
-- Install this after your game_discard function.

create or replace function public._okey_is_joker(p_tile jsonb)
returns boolean
language sql
immutable
as $$
  select coalesce(
    (p_tile->>'joker')::boolean,
    (p_tile->>'is_joker')::boolean,
    (p_tile->>'fake_joker')::boolean,
    (p_tile->>'is_fake_joker')::boolean,
    false
  );
$$;

create or replace function public._okey_remove_indices(
  p_tiles jsonb,
  p_indices int[]
)
returns jsonb
language sql
immutable
as $$
  select coalesce(
    jsonb_agg(e.value order by e.idx),
    '[]'::jsonb
  )
  from jsonb_array_elements(p_tiles) with ordinality as e(value, idx)
  where not (e.idx = any(p_indices));
$$;

create or replace function public._okey_candidate_groups(p_tiles jsonb)
returns setof int[]
language plpgsql
as $$
declare
  v_len int;
  v_first_idx int;
  v_first_num int;
  v_first_color text;
  v_joker_idxs int[] := '{}';
  v_joker_count int := 0;

  v_set_idxs int[] := '{}';
  v_set_n int := 0;
  v_mask int;
  v_bits int;
  v_target int;
  v_joker_need int;
  v_group int[];
  v_first_pos int := 0;

  r record;
  v_run_idxs int[];
  v_needed int;
  v_last_num int;
  v_curr_num int;
  v_diff int;
  v_extra int;
  v_rem_j int;
begin
  v_len := jsonb_array_length(p_tiles);
  if v_len < 3 then
    return;
  end if;

  -- Joker indices
  select coalesce(array_agg(t.idx order by t.idx), '{}')
    into v_joker_idxs
  from (
    select e.idx::int as idx
    from jsonb_array_elements(p_tiles) with ordinality e(value, idx)
    where public._okey_is_joker(e.value)
  ) t;
  v_joker_count := coalesce(array_length(v_joker_idxs, 1), 0);

  -- First non-joker anchor
  select t.idx, t.num, t.color
    into v_first_idx, v_first_num, v_first_color
  from (
    select
      e.idx::int as idx,
      coalesce((e.value->>'number')::int, (e.value->>'value')::int) as num,
      lower(coalesce(e.value->>'color', '')) as color
    from jsonb_array_elements(p_tiles) with ordinality e(value, idx)
    where not public._okey_is_joker(e.value)
    order by num, color, idx
  ) t
  limit 1;

  if v_first_idx is null then
    -- all jokers: only 3/4 groups are valid
    if (v_len % 3 = 0) or (v_len % 4 = 0) then
      return next (select array_agg(i) from generate_series(1, least(4, v_len)) i);
    end if;
    return;
  end if;

  -------------------------------------------------
  -- SET candidates (same number, distinct colors)
  -------------------------------------------------
  select coalesce(array_agg(x.idx order by x.idx), '{}')
    into v_set_idxs
  from (
    select distinct on (t.color) t.color, t.idx
    from (
      select
        e.idx::int as idx,
        coalesce((e.value->>'number')::int, (e.value->>'value')::int) as num,
        lower(coalesce(e.value->>'color', '')) as color
      from jsonb_array_elements(p_tiles) with ordinality e(value, idx)
      where not public._okey_is_joker(e.value)
    ) t
    where t.num = v_first_num
    order by t.color, t.idx
  ) x;

  v_set_n := coalesce(array_length(v_set_idxs, 1), 0);
  if v_set_n > 0 then
    for i in 1..v_set_n loop
      if v_set_idxs[i] = v_first_idx then
        v_first_pos := i;
        exit;
      end if;
    end loop;

    for v_target in 3..4 loop
      for v_mask in 1..((1 << v_set_n) - 1) loop
        v_bits := 0;
        v_group := '{}';
        for i in 1..v_set_n loop
          if ((v_mask >> (i - 1)) & 1) = 1 then
            v_bits := v_bits + 1;
            v_group := array_append(v_group, v_set_idxs[i]);
          end if;
        end loop;

        if v_bits < 1 or v_bits > v_target then
          continue;
        end if;
        if ((v_mask >> (v_first_pos - 1)) & 1) = 0 then
          continue;
        end if;

        v_joker_need := v_target - v_bits;
        if v_joker_need < 0 or v_joker_need > v_joker_count then
          continue;
        end if;

        if v_joker_need > 0 then
          for i in 1..v_joker_need loop
            v_group := array_append(v_group, v_joker_idxs[i]);
          end loop;
        end if;

        return next v_group;
      end loop;
    end loop;
  end if;

  -------------------------------------------------
  -- RUN candidates (same color, consecutive, jokers fill gaps)
  -------------------------------------------------
  v_run_idxs := array[v_first_idx];
  v_needed := 0;
  v_last_num := case when v_first_num = 1 then 14 else v_first_num end;

  -- Try run with only jokers appended to anchor.
  v_rem_j := v_joker_count - v_needed;
  for v_extra in 0..least(3, greatest(v_rem_j, 0)) loop
    if array_length(v_run_idxs, 1) + v_needed + v_extra >= 3 then
      v_group := v_run_idxs;
      for i in 1..(v_needed + v_extra) loop
        v_group := array_append(v_group, v_joker_idxs[i]);
      end loop;
      return next v_group;
    end if;
  end loop;

  for r in
    select
      e.idx::int as idx,
      coalesce((e.value->>'number')::int, (e.value->>'value')::int) as num
    from jsonb_array_elements(p_tiles) with ordinality e(value, idx)
    where not public._okey_is_joker(e.value)
      and lower(coalesce(e.value->>'color', '')) = v_first_color
      and e.idx::int <> v_first_idx
    order by case
      when coalesce((e.value->>'number')::int, (e.value->>'value')::int) = 1 then 14
      else coalesce((e.value->>'number')::int, (e.value->>'value')::int)
    end, e.idx
  loop
    v_curr_num := case when r.num = 1 then 14 else r.num end;

    if v_curr_num = v_last_num then
      continue;
    elsif v_curr_num = v_last_num + 1 then
      v_diff := 1;
    elsif v_curr_num > v_last_num then
      v_diff := v_curr_num - v_last_num;
    else
      exit;
    end if;

    if v_diff > 1 then
      if (v_diff - 1) <= (v_joker_count - v_needed) then
        v_needed := v_needed + (v_diff - 1);
      else
        exit;
      end if;
    end if;

    v_run_idxs := array_append(v_run_idxs, r.idx);
    v_last_num := v_curr_num;

    v_rem_j := v_joker_count - v_needed;
    for v_extra in 0..least(3, greatest(v_rem_j, 0)) loop
      if array_length(v_run_idxs, 1) + v_needed + v_extra >= 3 then
        v_group := v_run_idxs;
        for i in 1..(v_needed + v_extra) loop
          v_group := array_append(v_group, v_joker_idxs[i]);
        end loop;
        return next v_group;
      end if;
    end loop;
  end loop;
end;
$$;

create or replace function public._okey_can_finish_recursive(p_tiles jsonb)
returns boolean
language plpgsql
as $$
declare
  v_len int;
  g int[];
  v_rest jsonb;
begin
  v_len := jsonb_array_length(p_tiles);
  if v_len = 0 then
    return true;
  end if;
  if v_len < 3 then
    return false;
  end if;

  for g in select * from public._okey_candidate_groups(p_tiles)
  loop
    v_rest := public._okey_remove_indices(p_tiles, g);
    if public._okey_can_finish_recursive(v_rest) then
      return true;
    end if;
  end loop;

  return false;
end;
$$;

create or replace function public.okey_can_finish(p_tiles jsonb)
returns boolean
language plpgsql
as $$
declare
  v_len int;
begin
  if p_tiles is null or jsonb_typeof(p_tiles) <> 'array' then
    return false;
  end if;

  v_len := jsonb_array_length(p_tiles);
  if v_len = 0 then
    return false;
  end if;
  if v_len % 3 <> 2 then
    return false;
  end if;

  return public._okey_can_finish_recursive(p_tiles);
end;
$$;

grant execute on function public.okey_can_finish(jsonb) to authenticated, service_role;


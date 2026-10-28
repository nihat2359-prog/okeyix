-- Read-only: starting tables across all leagues; no names, messages or hands.
select t.id, t.league_id, t.status, t.max_players,
  t.created_at, t.ready_since,
  count(tp.user_id) as seated,
  count(tp.user_id) filter (where u.is_bot = true) as bots,
  count(tp.user_id) filter (where u.is_bot = false) as humans,
  count(tp.user_id) filter (where u.id is null) as unknown_users,
  coalesce(bool_or(jsonb_array_length(
    case when jsonb_typeof(tp.hand) = 'array'
      then tp.hand else '[]'::jsonb end
  ) > 0), false) as has_dealt_hand
from public.tables t
left join public.table_players tp on tp.table_id = t.id
left join public.users u on u.id = tp.user_id
where t.status in ('start', 'starting')
group by t.id
order by t.ready_since nulls last, t.created_at;

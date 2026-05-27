-- Cleanup waiting tables whose creator went offline/stale before game starts.
-- This handles abrupt app closes where client-side cleanup cannot run.

create or replace function public.cleanup_stale_waiting_tables(
  p_stale_after interval default interval '2 minutes'
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted integer := 0;
begin
  with candidate_tables as (
    select t.id
      from public.tables t
      left join public.profiles owner_profile on owner_profile.id = t.created_by
     where t.status = 'waiting'
       and t.created_by is not null
       and (
         owner_profile.is_online is false
         or (
           owner_profile.last_seen_at is not null
           and owner_profile.last_seen_at < (now() - p_stale_after)
         )
       )
       and not exists (
         select 1
           from public.table_players tp
           join public.users u on u.id = tp.user_id
          where tp.table_id = t.id
            and tp.user_id <> t.created_by
            and coalesce(u.is_bot, false) = false
       )
  ),
  deleted_moves as (
    delete from public.match_moves mm
     where mm.table_id in (select id from candidate_tables)
    returning mm.table_id
  ),
  deleted_discards as (
    delete from public.table_discards td
     where td.table_id in (select id from candidate_tables)
    returning td.table_id
  ),
  deleted_players as (
    delete from public.table_players tp
     where tp.table_id in (select id from candidate_tables)
    returning tp.table_id
  )
  delete from public.tables t
   where t.id in (select id from candidate_tables);

  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

comment on function public.cleanup_stale_waiting_tables(interval)
  is 'Deletes waiting tables whose creator is stale/offline and no other human player joined.';

-- Run once immediately after migration.
select public.cleanup_stale_waiting_tables(interval '2 minutes');

-- Schedule periodic cleanup if pg_cron is available.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid)
      from cron.job
     where jobname = 'cleanup-stale-waiting-tables';

    perform cron.schedule(
      'cleanup-stale-waiting-tables',
      '* * * * *',
      $job$select public.cleanup_stale_waiting_tables(interval '2 minutes');$job$
    );
  end if;
end
$$;

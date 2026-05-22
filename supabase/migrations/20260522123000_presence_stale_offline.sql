-- Keep profiles.is_online in sync with heartbeat freshness.
-- If a user has not sent heartbeat recently, force is_online=false.

create or replace function public.mark_stale_profiles_offline(
  p_stale_after interval default interval '2 minutes'
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rows integer := 0;
begin
  update public.profiles
     set is_online = false
   where is_online = true
     and (
       last_seen_at is null
       or last_seen_at < (now() - p_stale_after)
     );

  get diagnostics v_rows = row_count;
  return v_rows;
end;
$$;

comment on function public.mark_stale_profiles_offline(interval)
  is 'Marks stale users as offline based on last_seen_at age.';

-- Run once immediately after migration.
select public.mark_stale_profiles_offline(interval '2 minutes');

-- If pg_cron is available, schedule periodic cleanup.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    -- Replace existing job if present.
    perform cron.unschedule(jobid)
      from cron.job
     where jobname = 'mark-stale-profiles-offline';

    perform cron.schedule(
      'mark-stale-profiles-offline',
      '* * * * *',
      $job$select public.mark_stale_profiles_offline(interval '2 minutes');$job$
    );
  end if;
end
$$;

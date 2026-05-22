-- Relax presence stale cutoff to reduce false-offline flips.
-- Heartbeat is 45s on client; use 5 minutes for server cleanup safety margin.

create or replace function public.mark_stale_profiles_offline(
  p_stale_after interval default interval '5 minutes'
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
     and last_seen_at is not null
     and last_seen_at < (now() - p_stale_after);

  get diagnostics v_rows = row_count;
  return v_rows;
end;
$$;

-- Re-schedule cron job if available.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid)
      from cron.job
     where jobname = 'mark-stale-profiles-offline';

    perform cron.schedule(
      'mark-stale-profiles-offline',
      '* * * * *',
      $job$select public.mark_stale_profiles_offline(interval '5 minutes');$job$
    );
  end if;
end
$$;

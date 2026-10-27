-- NOT APPLIED. Fixes the supplied live legacy function without changing its API.
-- Existing rewards/progress remain untouched; seven-day RPCs are unchanged.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
DO $guard$
DECLARE body text;
BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'POSTGRES_REQUIRED'; END IF;
  IF to_regclass('public.ux_wallet_daily_bonus_once_per_day') IS NULL THEN
    RAISE EXCEPTION 'DAILY_BONUS_UNIQUE_INDEX_REQUIRED'; END IF;
  SELECT replace(prosrc,chr(13)||chr(10),chr(10)) INTO body FROM pg_proc
    WHERE oid=to_regprocedure('public.claim_daily_bonus(uuid,integer,text)')
      AND proowner='postgres'::regrole AND prosecdef;
  IF NOT FOUND THEN RAISE EXCEPTION 'LEGACY_DAILY_SOURCE_REQUIRED'; END IF;
  IF md5(body) NOT IN ('3651123acf20ffacd8b2feb49bea8e1b','d2529d70292551d448a007d31c1dd7cc') THEN
    RAISE EXCEPTION 'LEGACY_DAILY_SOURCE_CHANGED_REVIEW_REQUIRED'; END IF;
END $guard$;

-- Keep the legacy RPC signature and boolean result for released clients.
-- p_amount and p_day_key are compatibility inputs, never trusted values.
create or replace function public.claim_daily_bonus(
  p_user_id uuid,
  p_amount integer,
  p_day_key text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_amount constant integer := 2500;
  v_day_key text := 'daily_bonus:' ||
    pg_catalog.to_char(pg_catalog.statement_timestamp() at time zone 'Europe/Istanbul', 'YYYY-MM-DD');
  v_inserted integer;
  v_updated integer;
begin
  if v_user_id is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
  end if;
  if p_user_id is distinct from v_user_id then
    raise exception 'USER_ID_MISMATCH' using errcode = '42501';
  end if;

  -- Uses ux_wallet_daily_bonus_once_per_day from the earlier migration.
  -- Concurrent requests for this user/day cannot both insert a credit.
  insert into public.wallet_transactions(user_id, amount, reason, type, store, note)
  values (v_user_id, v_amount, 'daily_bonus', 'credit', 'system', v_day_key)
  on conflict (user_id, note)
    where reason = 'daily_bonus' and note is not null
  do nothing;
  get diagnostics v_inserted = row_count;
  if v_inserted = 0 then
    return false;
  end if;

  update public.profiles
     set coins = coalesce(coins, 0) + v_amount
   where id = v_user_id;
  get diagnostics v_updated = row_count;
  if v_updated <> 1 then
    -- Uncaught exception rolls back the credit insert as well.
    raise exception 'BONUS_PROFILE_NOT_FOUND';
  end if;
  return true;
end;
$$;

-- CREATE OR REPLACE preserves existing grants. Remove public/anon access
-- explicitly, including PUBLIC's inherited EXECUTE, then allow signed-in users.
-- Any privileged owner/service_role access still requires a valid auth.uid().
revoke all on function public.claim_daily_bonus(uuid, integer, text) from public, anon;
grant execute on function public.claim_daily_bonus(uuid, integer, text) to authenticated;

comment on function public.claim_daily_bonus(uuid, integer, text)
  is 'Authenticated daily bonus: 2500 coins once per Europe/Istanbul day. Legacy amount/day inputs ignored.';

commit;

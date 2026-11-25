-- Additive only. No changes to existing reward, profile or table policies.
-- Configure each real store ID and enable it only after public release.
begin;
create table if not exists public.cross_promo_catalog (
  game_id text primary key check (game_id in ('okix', 'sirenix', 'kartix')),
  android_package text,
  ios_bundle text,
  android_enabled boolean not null default false,
  ios_enabled boolean not null default false
);
insert into public.cross_promo_catalog(game_id) values ('okix'), ('sirenix'), ('kartix')
  on conflict do nothing;
update public.cross_promo_catalog set ios_bundle = 'com.okeyix.' || game_id
  where ios_bundle is null;
update public.cross_promo_catalog set android_package = 'com.okeyix.' || game_id
  where android_package is null;
alter table public.cross_promo_catalog enable row level security;
revoke all on public.cross_promo_catalog from public, anon, authenticated;

create table if not exists public.cross_promo_claims (
  user_id uuid not null references public.profiles(id) on delete cascade,
  game_id text not null references public.cross_promo_catalog(game_id),
  store text not null check (store in ('ios', 'android')),
  claimed_at timestamptz not null default now(),
  primary key(user_id, game_id)
);
alter table public.cross_promo_claims enable row level security;
revoke all on public.cross_promo_claims from public, anon, authenticated;

create or replace function public.okeyix_claim_cross_promo(p_game_id text, p_store text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_rows integer;
begin
  if v_user is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if p_store not in ('ios', 'android') or p_store is null then raise exception 'INVALID_STORE'; end if;
  if not exists(select 1 from public.cross_promo_catalog c where c.game_id = p_game_id and
      ((p_store = 'ios' and c.ios_enabled and nullif(c.ios_bundle, '') is not null) or
       (p_store = 'android' and c.android_enabled and nullif(c.android_package, '') is not null))) then
    raise exception 'PROMO_NOT_PUBLIC';
  end if;
  insert into public.cross_promo_claims(user_id, game_id, store) values(v_user, p_game_id, p_store)
    on conflict(user_id, game_id) do nothing;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then return jsonb_build_object('credited', false, 'already_claimed', true, 'amount', 0); end if;
  update public.profiles set coins = coalesce(coins, 0) + 5000 where id = v_user;
  get diagnostics v_rows = row_count;
  if v_rows <> 1 then raise exception 'PROFILE_NOT_FOUND'; end if;
  insert into public.wallet_transactions(user_id, amount, reason, type, store, note)
    values(v_user, 5000, 'cross_promo', 'credit', 'system', 'cross_promo:' || p_game_id);
  return jsonb_build_object('credited', true, 'already_claimed', false, 'amount', 5000);
end;
$$;
revoke all on function public.okeyix_claim_cross_promo(text, text) from public, anon;
grant execute on function public.okeyix_claim_cross_promo(text, text) to authenticated;
commit;

SELECT public.fixture_assert((SELECT count(*)=160 FROM public.users),'150 new identities');
SELECT public.fixture_assert((SELECT count(*)=160 FROM public.profiles),'150 new profiles');
SELECT public.fixture_assert((SELECT count(*)=160 FROM okeyix_bot_wallet_private.registry),'automatic registry');
SELECT public.fixture_assert((SELECT count(*)=150 AND count(DISTINCT user_id)=150
  AND bool_and(balance_before=10000 AND amount=balance_after-balance_before AND origin='migration')
  FROM okeyix_bot_wallet_private.topups),'initial funding receipts');
SELECT public.fixture_assert(NOT EXISTS(SELECT 1 FROM auth.users),'no Auth accounts');
SELECT public.fixture_assert((SELECT min(rating)=0 AND max(rating)=1800
  AND count(DISTINCT rating)=150 AND count(DISTINCT coins)=150
  AND min(coins)>200000000 AND bool_and(NOT is_online AND allow_game_invites)
  FROM public.profiles WHERE id::text LIKE 'b0251125-%'),'ratings, reserves, presence');
SELECT public.fixture_assert((SELECT bool_and(untouched_default='default-kept')
  FROM public.users),'defaults preserved');
SELECT public.fixture_assert(NOT EXISTS(
  SELECT 1 FROM public.fixture_existing old
  LEFT JOIN public.users u ON u.id=old.id LEFT JOIN public.profiles p ON p.id=old.id
  LEFT JOIN okeyix_bot_wallet_private.registry r ON r.user_id=old.id
  WHERE to_jsonb(u) IS DISTINCT FROM old.user_row OR to_jsonb(p) IS DISTINCT FROM old.profile_row
    OR to_jsonb(r) IS DISTINCT FROM old.registry_row
),'all 10 old bots unchanged');


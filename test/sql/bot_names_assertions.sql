SELECT public.fixture_assert((
  SELECT count(*)=160
    AND count(*) FILTER(WHERE username ~ '^[a-zçğıöşü0-9_]+$')=48
    AND count(*) FILTER(WHERE username LIKE '% %')=16
    AND count(*) FILTER(WHERE username ~ '[★ツ•♡✿彡☆ღ✦『』]')=32
    AND count(*) FILTER(WHERE username !~ '^[a-zçğıöşü0-9_]+$'
      AND username NOT LIKE '% %' AND username !~ '[★ツ•♡✿彡☆ღ✦『』]')=64
  FROM public.users u WHERE u.is_bot
    AND NOT EXISTS(SELECT 1 FROM auth.users a WHERE a.id=u.id)
),'160 bots have exact 40/30/20/10 distribution');
SELECT public.fixture_assert(NOT EXISTS(
  SELECT 1 FROM public.users u JOIN public.profiles p USING(id)
  JOIN public.fixture_before_names b USING(id)
  WHERE (to_jsonb(u)-'username') IS DISTINCT FROM (b.user_row-'username')
    OR (to_jsonb(p)-'username') IS DISTINCT FROM (b.profile_row-'username')
    OR u.username IS DISTINCT FROM p.username
),'only usernames changed, profiles synchronized');
SELECT public.fixture_assert(NOT EXISTS(
  SELECT 1 FROM public.users u JOIN public.fixture_before_names b USING(id)
  WHERE (NOT u.is_bot OR EXISTS(SELECT 1 FROM auth.users a WHERE a.id=u.id))
    AND to_jsonb(u) IS DISTINCT FROM b.user_row
),'humans and Auth identities untouched');
SELECT public.fixture_assert((SELECT count(*)=count(DISTINCT lower(btrim(username)))
  FROM public.users),'case insensitive uniqueness');

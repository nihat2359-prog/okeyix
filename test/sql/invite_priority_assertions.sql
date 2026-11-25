-- Regression: offline high-rated humans must not crowd out new bots.
SELECT public.fixture_assert((SELECT count(*)=160 FROM public.get_invitable_players(
  md5('target')::uuid,md5('self')::uuid,'standard',1000)),'two independent 80-row budgets');
SELECT public.fixture_assert(EXISTS(SELECT 1 FROM public.get_invitable_players(
  md5('target')::uuid,md5('self')::uuid,'standard',1000) WHERE username LIKE 'New bot %'),'new bots visible');
SELECT public.fixture_assert((SELECT bool_and(NOT r.is_bot) FROM public.get_invitable_players(
  md5('target')::uuid,md5('self')::uuid,'standard',1000) WITH ORDINALITY r WHERE r.ordinality<=10),'online humans first');
SELECT public.fixture_assert((SELECT count(*)=80 FROM public.get_invitable_players(
  md5('target')::uuid,md5('self')::uuid,'standard',1000) r JOIN public.profiles p ON p.id=r.id
  WHERE NOT r.is_bot AND NOT p.is_online),'offline humans keep their own budget');
SELECT public.fixture_assert((SELECT count(*)=80 FROM public.get_invitable_players(
  md5('target')::uuid,md5('self')::uuid,'standard',1000) r JOIN public.profiles p ON p.id=r.id
  WHERE r.is_bot OR p.is_online),'online players keep their own budget');
-- Both human-only leagues must remain bot-free even with a permissive rating fixture.
SELECT public.fixture_assert(NOT EXISTS(SELECT 1 FROM public.get_invitable_players(
  md5('target')::uuid,md5('self')::uuid,'gold',1000) WHERE is_bot),'gold bot ban');
SELECT public.fixture_assert(NOT EXISTS(SELECT 1 FROM public.get_invitable_players(
  md5('target')::uuid,md5('self')::uuid,'elite',1000) WHERE is_bot),'elite bot ban');
-- Match existing Flutter busy rules before applying the limit.
INSERT INTO public.tables VALUES(md5('waiting')::uuid,'waiting'),(md5('start')::uuid,'start'),
  (md5('starting')::uuid,'starting'),(md5('playing')::uuid,'playing');
INSERT INTO public.table_players
SELECT md5(s)::uuid,md5('old-bot-'||n)::uuid
FROM (VALUES('waiting',1),('start',2),('starting',3),('playing',4)) v(s,n);
INSERT INTO public.table_players
SELECT md5(s)::uuid,md5('human-'||n)::uuid
FROM (VALUES('waiting',1),('start',2),('starting',3),('playing',4)) v(s,n);
INSERT INTO public.table_invites VALUES(md5('target')::uuid,md5('old-bot-5')::uuid,'pending');
INSERT INTO public.table_players VALUES(md5('target')::uuid,md5('old-bot-6')::uuid);
UPDATE public.profiles SET allow_game_invites=false WHERE id=md5('human-5')::uuid;
UPDATE public.profiles SET rating=-1 WHERE id=md5('old-bot-7')::uuid;
UPDATE public.profiles SET coins=0 WHERE id=md5('old-bot-8')::uuid;
SELECT public.fixture_assert(NOT EXISTS(
  SELECT 1 FROM public.get_invitable_players(md5('target')::uuid,md5('human-6')::uuid,'standard',1000) r
  WHERE r.id IN (SELECT md5('old-bot-'||n)::uuid FROM generate_series(1,8) n)
    OR r.id IN (SELECT md5('human-'||n)::uuid FROM generate_series(2,6) n)
),'busy, pending, seated, disabled, self, rating and coins excluded');
SELECT public.fixture_assert(EXISTS(SELECT 1 FROM public.get_invitable_players(
  md5('target')::uuid,md5('self')::uuid,'standard',1000) WHERE id=md5('human-1')::uuid),'waiting human remains eligible');
SELECT public.fixture_assert(NOT EXISTS(SELECT 1 FROM public.get_invitable_players(
  md5('target')::uuid,md5('self')::uuid,'silver',1000) WHERE username LIKE 'New bot %'),'minimum rating preserved');


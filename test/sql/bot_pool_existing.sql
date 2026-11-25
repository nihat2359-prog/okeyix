INSERT INTO public.users(id,username,is_bot,avatar_url,rating)
SELECT ('00000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  'Existing '||n,true,'existing-avatar',900 FROM generate_series(1,10) n;
CREATE TABLE public.fixture_existing AS
SELECT u.id,to_jsonb(u) AS user_row,to_jsonb(p) AS profile_row,to_jsonb(r) AS registry_row
FROM public.users u JOIN public.profiles p USING(id)
JOIN okeyix_bot_wallet_private.registry r ON r.user_id=u.id;
CREATE FUNCTION public.fixture_assert(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'ASSERT: %',label; END IF; END $$;


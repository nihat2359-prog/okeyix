-- Occupy the first candidate in all four categories with human accounts.
INSERT INTO public.users(id,username)
SELECT ('eeeeeeee-eeee-4000-8000-'||lpad(n::text,12,'0'))::uuid,name
FROM unnest(ARRAY['MaviBoncuk','ahmet34','★MaviBoncuk★','Ahmet Yılmaz'])
  WITH ORDINALITY AS names(name,n);
-- An Auth identity must be excluded even with an incorrect is_bot flag.
INSERT INTO auth.users VALUES('eeeeeeee-eeee-4000-8000-000000000005');
INSERT INTO public.users(id,username,is_bot)
VALUES('eeeeeeee-eeee-4000-8000-000000000005','Auth Oyuncusu',true);
CREATE TABLE public.fixture_before_names AS
SELECT u.id,to_jsonb(u) AS user_row,to_jsonb(p) AS profile_row
FROM public.users u JOIN public.profiles p USING(id);

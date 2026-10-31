ALTER TABLE public.profiles ADD COLUMN is_online boolean DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN last_seen_at timestamptz;

-- LOCAL ONLY; extends the separate chat fixture database.
\set ON_ERROR_STOP on
DO $$ BEGIN
  IF current_database()<>'okeyix_chat_test' THEN RAISE EXCEPTION 'LOCAL_CHAT_TEST_REQUIRED'; END IF;
END $$;
ALTER TABLE public.tables ADD COLUMN IF NOT EXISTS status text DEFAULT 'playing';
ALTER TABLE public.tables ADD COLUMN IF NOT EXISTS round_count integer DEFAULT 1;
CREATE TABLE IF NOT EXISTS public.wallet_transactions(
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid,amount bigint,reason text,note text);
CREATE PUBLICATION supabase_realtime;

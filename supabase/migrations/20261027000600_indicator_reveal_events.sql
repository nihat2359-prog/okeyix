-- NOT APPLIED. Publishes successful indicator receipts for opponent animation.
-- Does not alter reward amounts, balances, hands or game start/finish functions.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $$ BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'POSTGRES_REQUIRED'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_publication WHERE pubname='supabase_realtime') THEN
    RAISE EXCEPTION 'SUPABASE_REALTIME_PUBLICATION_REQUIRED'; END IF;
END $$;
CREATE SCHEMA IF NOT EXISTS okeyix_indicator_private AUTHORIZATION postgres;
REVOKE ALL ON SCHEMA okeyix_indicator_private FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE IF NOT EXISTS public.table_indicator_events(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  table_id uuid NOT NULL REFERENCES public.tables(id) ON DELETE CASCADE,
  player_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  round_no integer NOT NULL,
  amount bigint NOT NULL CHECK(amount>0),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(table_id,player_id,round_no)
);
ALTER TABLE public.table_indicator_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.table_indicator_events FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON public.table_indicator_events TO authenticated;
DROP POLICY IF EXISTS indicator_participant_read ON public.table_indicator_events;
CREATE POLICY indicator_participant_read ON public.table_indicator_events
  FOR SELECT TO authenticated USING(EXISTS(
    SELECT 1 FROM public.table_players p
    WHERE p.table_id=table_indicator_events.table_id AND p.user_id=auth.uid()));

CREATE OR REPLACE FUNCTION okeyix_indicator_private.publish_receipt()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_table uuid; v_round integer;
BEGIN
  IF NEW.amount<=0 OR NEW.note IS NULL OR NEW.note !~
    '^indicator_bonus:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    THEN RETURN NEW; END IF;
  v_table:=substr(NEW.note,17)::uuid;
  SELECT t.round_count INTO v_round FROM public.tables t
    WHERE t.id=v_table AND t.status='playing' AND EXISTS(
      SELECT 1 FROM public.table_players p WHERE p.table_id=t.id AND p.user_id=NEW.user_id);
  IF NOT FOUND OR v_round IS NULL THEN RETURN NEW; END IF;
  INSERT INTO public.table_indicator_events(table_id,player_id,round_no,amount)
    VALUES(v_table,NEW.user_id,v_round,NEW.amount) ON CONFLICT DO NOTHING;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION okeyix_indicator_private.publish_receipt()
  FROM PUBLIC,anon,authenticated,service_role;
DROP TRIGGER IF EXISTS okeyix_indicator_receipt ON public.wallet_transactions;
CREATE TRIGGER okeyix_indicator_receipt AFTER INSERT ON public.wallet_transactions
  FOR EACH ROW WHEN(NEW.reason='indicator_bonus')
  EXECUTE FUNCTION okeyix_indicator_private.publish_receipt();
DO $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime'
    AND schemaname='public' AND tablename='table_indicator_events') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.table_indicator_events;
  END IF;
END $$;
NOTIFY pgrst,'reload schema';
COMMIT;

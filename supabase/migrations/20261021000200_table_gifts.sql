-- NOT APPLIED. Additive table-session gifts. No game/statistics RPC changes.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $$ BEGIN IF current_user<>'postgres' OR NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname=current_user AND (rolbypassrls OR rolsuper))
  THEN RAISE EXCEPTION 'GIFT_REQUIRES_POSTGRES'; END IF; END $$;
CREATE TABLE public.okeyix_gift_catalog (
  id text PRIMARY KEY,
  name_tr text NOT NULL, name_en text NOT NULL,
  filename text NOT NULL UNIQUE CHECK(filename ~ '^[a-z_]+\.png$'),
  price integer NOT NULL CHECK(price>0),
  sort_order integer NOT NULL,
  enabled boolean NOT NULL DEFAULT true
);
INSERT INTO public.okeyix_gift_catalog(id,name_tr,name_en,filename,price,sort_order) VALUES
 ('cay','Çay','Tea','cay.png',1000,1),
 ('kahve','Kahve','Coffee','kahve.png',2500,2),
 ('pasta','Pasta','Cake','pasta.png',5000,3),
 ('kirmizi_gul','Kırmızı Gül','Red Rose','kirmizi_gul.png',10000,4),
 ('limon','Limon','Lemon','limon.png',2000,5),
 ('aci_biber','Acı Biber','Chili Pepper','aci_biber.png',3000,6),
 ('sans_yildizi','Şans Yıldızı','Lucky Star','sans_yildizi.png',25000,7),
 ('nazar_boncugu','Nazar Boncuğu','Evil Eye','nazar_boncugu.png',10000,8),
 ('sans_nali','Şans Nalı','Lucky Horseshoe','sans_nali.png',10000,9),
 ('tac','Taç','Crown','tac.png',50000,10),
 ('yuzuk','Yüzük','Ring','yuzuk.png',75000,11),
 ('dort_yaprakli_yonca','Dört Yapraklı Yonca','Four-leaf Clover','dort_yaprakli_yonca.png',10000,12),
 ('saat','Saat','Watch','saat.png',5000,13),
 ('hediye_paketi','Hediye Paketi','Gift Box','hediye_paketi.png',10000,14);

-- Purchase history survives table cleanup; the live table UUID is historical.
CREATE TABLE public.okeyix_table_gift_purchases (
  seq bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  request_id uuid NOT NULL,
  table_id uuid NOT NULL,
  sender_id uuid NOT NULL, recipient_id uuid NOT NULL,
  gift_id text NOT NULL REFERENCES public.okeyix_gift_catalog(id) ON DELETE RESTRICT,
  price integer NOT NULL CHECK(price>0),
  wallet_transaction_id uuid NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(sender_id,request_id)
);
CREATE INDEX table_gift_events ON public.okeyix_table_gift_purchases(table_id,seq);
CREATE TABLE public.okeyix_table_last_gifts (
  table_id uuid NOT NULL REFERENCES public.tables(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  membership_id uuid NOT NULL UNIQUE REFERENCES public.table_players(id) ON DELETE CASCADE,
  purchase_seq bigint NOT NULL UNIQUE REFERENCES public.okeyix_table_gift_purchases(seq) ON DELETE RESTRICT,
  gift_id text NOT NULL REFERENCES public.okeyix_gift_catalog(id) ON DELETE RESTRICT,
  PRIMARY KEY(table_id,user_id)
);
ALTER TABLE public.okeyix_gift_catalog ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.okeyix_table_gift_purchases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.okeyix_table_last_gifts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.okeyix_gift_catalog,public.okeyix_table_gift_purchases,public.okeyix_table_last_gifts FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON SEQUENCE public.okeyix_table_gift_purchases_seq_seq FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON public.okeyix_gift_catalog,public.okeyix_table_gift_purchases,public.okeyix_table_last_gifts TO authenticated;

CREATE FUNCTION public.okeyix_can_view_table_gifts(p_table_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
  SELECT auth.uid() IS NOT NULL AND EXISTS(SELECT 1 FROM public.tables t WHERE t.id=p_table_id
    AND (t.spectators_enabled OR EXISTS(SELECT 1 FROM public.table_players p WHERE p.table_id=t.id AND p.user_id=auth.uid())));
$$;
CREATE POLICY gift_catalog_read ON public.okeyix_gift_catalog FOR SELECT TO authenticated USING(enabled);
CREATE POLICY gift_events_read ON public.okeyix_table_gift_purchases FOR SELECT TO authenticated USING(public.okeyix_can_view_table_gifts(table_id));
CREATE POLICY gift_state_read ON public.okeyix_table_last_gifts FOR SELECT TO authenticated USING(public.okeyix_can_view_table_gifts(table_id));

CREATE FUNCTION public.okeyix_buy_table_gift(p_table_id uuid,p_recipient_id uuid,p_gift_id text,p_request_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE u uuid:=auth.uid(); t public.tables%ROWTYPE; g public.okeyix_gift_catalog%ROWTYPE;
  e public.okeyix_table_gift_purchases%ROWTYPE; balance integer; wallet_id uuid; membership uuid;
BEGIN
  IF u IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED' USING ERRCODE='42501'; END IF;
  IF p_request_id IS NULL OR p_table_id IS NULL OR p_recipient_id IS NULL OR p_gift_id IS NULL THEN
    RAISE EXCEPTION 'GIFT_ARGUMENT_REQUIRED' USING ERRCODE='22004'; END IF;
  -- Same request, even with conflicting table arguments, is serialized first.
  PERFORM pg_advisory_xact_lock(hashtextextended(u::text||':'||p_request_id::text,0));
  SELECT * INTO e FROM public.okeyix_table_gift_purchases WHERE sender_id=u AND request_id=p_request_id;
  IF FOUND THEN
    IF e.table_id<>p_table_id OR e.recipient_id<>p_recipient_id OR e.gift_id<>p_gift_id THEN
      RAISE EXCEPTION 'GIFT_REQUEST_CONFLICT' USING ERRCODE='22023'; END IF;
    SELECT coins INTO balance FROM public.profiles WHERE id=u;
    RETURN jsonb_build_object('event',to_jsonb(e),'balance',balance,'replayed',true);
  END IF;
  SELECT * INTO t FROM public.tables WHERE id=p_table_id FOR UPDATE;
  IF NOT FOUND OR t.status<>'playing' OR t.max_players<>2 THEN RAISE EXCEPTION 'GIFT_TABLE_NOT_ACTIVE'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.table_players WHERE table_id=t.id AND user_id=u)
    OR NOT EXISTS(SELECT 1 FROM public.users WHERE id=u AND NOT is_bot)
    OR NOT EXISTS(SELECT 1 FROM public.table_players WHERE table_id=t.id AND user_id=p_recipient_id)
    OR (SELECT count(*) FROM public.table_players WHERE table_id=t.id)<>2
    OR (SELECT count(DISTINCT user_id) FROM public.table_players WHERE table_id=t.id)<>2 THEN
    RAISE EXCEPTION 'GIFT_PLAYER_NOT_AT_TABLE' USING ERRCODE='42501'; END IF;
  SELECT id INTO STRICT membership FROM public.table_players WHERE table_id=t.id AND user_id=p_recipient_id;
  SELECT * INTO g FROM public.okeyix_gift_catalog WHERE id=p_gift_id AND enabled FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'GIFT_NOT_AVAILABLE'; END IF;
  SELECT coins INTO balance FROM public.profiles WHERE id=u FOR UPDATE;
  IF balance IS NULL OR balance<g.price THEN RAISE EXCEPTION 'GIFT_INSUFFICIENT_COINS'; END IF;
  UPDATE public.profiles SET coins=coins-g.price WHERE id=u RETURNING coins INTO balance;
  INSERT INTO public.wallet_transactions(user_id,amount,reason,type,store,note)
    VALUES(u,-g.price,'table_gift','debit','system',g.id) RETURNING id INTO wallet_id;
  INSERT INTO public.okeyix_table_gift_purchases(request_id,table_id,sender_id,recipient_id,gift_id,price,wallet_transaction_id)
    VALUES(p_request_id,t.id,u,p_recipient_id,g.id,g.price,wallet_id) RETURNING * INTO e;
  INSERT INTO public.okeyix_table_last_gifts(table_id,user_id,membership_id,purchase_seq,gift_id)
    VALUES(t.id,p_recipient_id,membership,e.seq,g.id)
    ON CONFLICT(table_id,user_id) DO UPDATE SET membership_id=excluded.membership_id,purchase_seq=excluded.purchase_seq,gift_id=excluded.gift_id
      WHERE public.okeyix_table_last_gifts.purchase_seq<excluded.purchase_seq;
  RETURN jsonb_build_object('event',to_jsonb(e),'balance',balance,'replayed',false);
END $$;

-- One snapshot for state and cursor; reconnect restores state without replaying
-- historical flights. Catalog prices/balance come from the server as well.
CREATE FUNCTION public.okeyix_table_gift_snapshot(p_table_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
BEGIN
  IF NOT public.okeyix_can_view_table_gifts(p_table_id) THEN RAISE EXCEPTION 'GIFT_VIEW_DENIED' USING ERRCODE='42501'; END IF;
  RETURN (SELECT jsonb_build_object(
    'table_id',p_table_id,
    'cursor',coalesce((SELECT max(seq) FROM public.okeyix_table_gift_purchases WHERE table_id=p_table_id),0),
    'balance',(SELECT coins FROM public.profiles WHERE id=auth.uid()),
    'catalog',coalesce((SELECT jsonb_agg(to_jsonb(g) ORDER BY sort_order) FROM public.okeyix_gift_catalog g WHERE enabled),'[]'::jsonb),
    'last_gifts',coalesce((SELECT jsonb_agg(to_jsonb(s)) FROM public.okeyix_table_last_gifts s WHERE table_id=p_table_id),'[]'::jsonb)
  ));
END $$;
REVOKE ALL ON FUNCTION public.okeyix_can_view_table_gifts(uuid),public.okeyix_table_gift_snapshot(uuid),
  public.okeyix_buy_table_gift(uuid,uuid,text,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.okeyix_can_view_table_gifts(uuid),public.okeyix_table_gift_snapshot(uuid),
  public.okeyix_buy_table_gift(uuid,uuid,text,uuid) TO authenticated;
DO $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='okeyix_table_gift_purchases') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.okeyix_table_gift_purchases;
  END IF;
END $$;
NOTIFY pgrst,'reload schema';
COMMIT;

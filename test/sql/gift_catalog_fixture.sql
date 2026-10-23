-- LOCAL TEST CLUSTER ONLY.
DO $$ BEGIN
 IF current_database()<>'okeyix_gift_catalog_test' OR inet_server_addr()<>'127.0.0.1'::inet
 THEN RAISE EXCEPTION 'LOCAL_ONLY'; END IF;
END $$;
CREATE TABLE public.okeyix_gift_catalog (
 id text PRIMARY KEY, name_tr text NOT NULL,name_en text NOT NULL,
 filename text NOT NULL UNIQUE,price integer NOT NULL CHECK(price>0),
 sort_order integer NOT NULL,enabled boolean NOT NULL DEFAULT true
);
INSERT INTO public.okeyix_gift_catalog(id,name_tr,name_en,filename,price,sort_order)
SELECT id,id,id,id||'.png',price,position FROM (VALUES
 ('cay',100,1),('kahve',250,2),('pasta',500,3),('kirmizi_gul',1000,4),
 ('limon',200,5),('aci_biber',300,6),('sans_yildizi',2500,7),
 ('nazar_boncugu',1000,8),('sans_nali',1000,9),('tac',5000,10),
 ('yuzuk',7500,11),('dort_yaprakli_yonca',1000,12),('saat',500,13),
 ('hediye_paketi',1000,14)) AS g(id,price,position);
CREATE TABLE public.before_prices AS SELECT id,price FROM public.okeyix_gift_catalog;
CREATE TABLE public.historical_gift(gift_id text REFERENCES public.okeyix_gift_catalog(id) ON DELETE RESTRICT);
INSERT INTO public.historical_gift VALUES('hediye_paketi');

DO $$ BEGIN
 IF current_database()<>'okeyix_gift_catalog_test' OR inet_server_addr()<>'127.0.0.1'::inet
 THEN RAISE EXCEPTION 'LOCAL_ONLY'; END IF;
 IF (SELECT array_agg(id ORDER BY sort_order) FROM public.okeyix_gift_catalog WHERE enabled)
   IS DISTINCT FROM ARRAY['cay','kahve','emzik','soguk_su','sigara','pasta','kirmizi_gul',
     'limon','aci_biber','sans_yildizi','nazar_boncugu','sans_nali','tac','yuzuk','dort_yaprakli_yonca','saat']
 THEN RAISE EXCEPTION 'WRONG_CATALOG_ORDER'; END IF;
 IF (SELECT count(*) FROM public.okeyix_gift_catalog WHERE id IN('emzik','soguk_su','sigara') AND price=250 AND enabled)<>3
 THEN RAISE EXCEPTION 'WRONG_NEW_PRICES'; END IF;
 IF EXISTS(SELECT 1 FROM public.before_prices b JOIN public.okeyix_gift_catalog g USING(id) WHERE b.price<>g.price)
 THEN RAISE EXCEPTION 'EXISTING_PRICE_CHANGED'; END IF;
 IF (SELECT count(*) FROM public.okeyix_gift_catalog)<>17
   OR NOT EXISTS(SELECT 1 FROM public.historical_gift h JOIN public.okeyix_gift_catalog g ON g.id=h.gift_id
     WHERE g.id='hediye_paketi' AND NOT g.enabled)
 THEN RAISE EXCEPTION 'HISTORY_NOT_RETAINED'; END IF;
END $$;
SELECT 'Gift catalog prices, ordering, retirement and history checks passed' AS result;

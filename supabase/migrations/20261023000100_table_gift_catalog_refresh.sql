-- NOT APPLIED. Stage first. Ship compatible clients/assets before enabling
-- these new catalog IDs in production; older clients do not recognise them.
-- Catalog only: no RPC, game, wallet or historical receipt changes.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $$ BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'GIFT_CATALOG_REQUIRES_POSTGRES'; END IF;
  IF to_regclass('public.okeyix_gift_catalog') IS NULL THEN
    RAISE EXCEPTION 'GIFT_CATALOG_BASE_REQUIRED'; END IF;
END $$;
 
-- Do not DELETE: past purchase receipts and live gifts reference this ID.
UPDATE public.okeyix_gift_catalog SET enabled=false WHERE id='hediye_paketi';

INSERT INTO public.okeyix_gift_catalog(id,name_tr,name_en,filename,price,sort_order,enabled)
VALUES ('emzik','Emzik','Pacifier','emzik.png',250,3,true),
       ('soguk_su','Soğuk Su','Cold Water','soguk_su.png',250,4,true),
       ('sigara','Sigara','Cigarette','sigara.png',250,5,true)
ON CONFLICT(id) DO UPDATE SET name_tr=excluded.name_tr,name_en=excluded.name_en,
  filename=excluded.filename,price=excluded.price,sort_order=excluded.sort_order,enabled=true;

-- Preserve all existing prices and enabled flags. Absolute orders make this
-- script safe to repeat without adding another offset on every execution.
UPDATE public.okeyix_gift_catalog AS g SET sort_order=o.position
FROM (VALUES ('cay',1),('kahve',2),('emzik',3),('soguk_su',4),('sigara',5),
  ('pasta',6),('kirmizi_gul',7),('limon',8),('aci_biber',9),('sans_yildizi',10),
  ('nazar_boncugu',11),('sans_nali',12),('tac',13),('yuzuk',14),
  ('dort_yaprakli_yonca',15),('saat',16),('hediye_paketi',17)) AS o(id,position)
WHERE g.id=o.id;
COMMIT;

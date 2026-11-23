DO $$
DECLARE r record; n bigint; c bigint;
BEGIN
 SELECT count(*),count(*) FILTER(WHERE credited) INTO n,c FROM okeyix_ads_private.attempts WHERE created_at>now()-interval '24 hours';
 RAISE NOTICE 'ADS_ATTEMPTS_24H=%, CREDITED=%',n,c;
 FOR r IN SELECT conname,pg_get_constraintdef(oid) AS definition FROM pg_constraint WHERE conrelid='public.wallet_transactions'::regclass LOOP
 RAISE NOTICE 'WALLET_CONSTRAINT %: %',r.conname,r.definition;
 END LOOP;
 FOR r IN SELECT a.attname,t.typname FROM pg_attribute a JOIN pg_type t ON t.oid=a.atttypid WHERE a.attrelid='public.wallet_transactions'::regclass AND a.attname IN ('reason','type','store') LOOP
 RAISE NOTICE 'WALLET_COLUMN % TYPE %',r.attname,r.typname;
 END LOOP;
END $$;
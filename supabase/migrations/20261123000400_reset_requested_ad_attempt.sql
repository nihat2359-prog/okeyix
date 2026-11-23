BEGIN;
DO $$
DECLARE target constant uuid:='c1788536-38fa-407a-8fdc-02bf4d94d3c1'; n integer; paid integer;
BEGIN
 PERFORM 1 FROM public.profiles WHERE id=target AND username='•Aslan•' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Account identity changed; no reset performed'; END IF;
 SELECT count(*) INTO paid FROM okeyix_ads_private.attempts WHERE user_id=target AND credited
 AND day=(statement_timestamp() AT TIME ZONE 'Europe/Istanbul')::date;
 DELETE FROM okeyix_ads_private.attempts WHERE user_id=target AND NOT credited
 AND day=(statement_timestamp() AT TIME ZONE 'Europe/Istanbul')::date;
 GET DIAGNOSTICS n=ROW_COUNT;
 RAISE NOTICE 'Uncredited ad attempts removed=%, credited attempts preserved=%. Wallet and seven-day rewards unchanged.',n,paid;
END $$;
COMMIT;
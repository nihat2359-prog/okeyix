-- Disposable fixture database only; test the actual existing bot-ban migration.
DO $$ BEGIN IF current_database()<>'okeyix_quick_play_test' THEN RAISE EXCEPTION 'LOCAL_ONLY'; END IF; END $$;
INSERT INTO public.leagues VALUES('gold',100000,500000,80,2);

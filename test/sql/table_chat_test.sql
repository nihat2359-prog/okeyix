-- LOCAL ONLY. Executes under actual authenticated role to exercise RLS.
\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
  IF current_database()<>'okeyix_chat_test' THEN RAISE EXCEPTION 'LOCAL_CHAT_TEST_REQUIRED'; END IF;
  IF (SELECT count(*) FROM public.table_messages)<>1 THEN RAISE EXCEPTION 'INSTALL_CREATED_FAKE_EVENTS'; END IF;
  IF EXISTS(SELECT 1 FROM pg_publication_rel WHERE prrelid='public.table_messages'::regclass
    AND prattrs IS NOT NULL) THEN RAISE EXCEPTION 'PUBLICATION_METADATA_MISSING'; END IF;
END $$;
INSERT INTO public.table_players(table_id,user_id,seat_index)
VALUES('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002',1);
INSERT INTO public.table_spectators(table_id,user_id)
VALUES('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003');
-- Idempotent rejoin creates no event and retains the original floor.
CREATE TEMP TABLE original_window AS SELECT * FROM okeyix_chat_private.memberships;
INSERT INTO public.table_spectators(table_id,user_id)
VALUES('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003')
ON CONFLICT(table_id,user_id) DO NOTHING;
UPDATE public.table_players SET hand='[]',is_ready=true,joined_at='2000-01-01';
DO $$ BEGIN
  IF (SELECT count(*) FROM public.table_messages WHERE membership_event IS NOT NULL)<>2
    THEN RAISE EXCEPTION 'DUPLICATE_JOIN_EVENTS'; END IF;
  IF EXISTS(SELECT * FROM original_window EXCEPT SELECT * FROM okeyix_chat_private.memberships)
    THEN RAISE EXCEPTION 'WINDOW_RESET_ON_UPDATE'; END IF;
END $$;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',true);
DO $$ BEGIN
  IF EXISTS(SELECT 1 FROM public.table_messages WHERE content='old conversation')
    THEN RAISE EXCEPTION 'HISTORY_LEAK'; END IF;
  IF (SELECT count(*) FROM public.table_messages)<>1 THEN RAISE EXCEPTION 'OWN_JOIN_NOT_VISIBLE'; END IF;
END $$;
INSERT INTO public.table_messages(table_id,sender_id,role,content,created_at)
VALUES('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003',
  'spectator','live spectator message','2000-01-01');
DO $$ BEGIN
  IF EXISTS(SELECT 1 FROM public.table_messages WHERE content='live spectator message'
    AND created_at<'2026-01-01') THEN RAISE EXCEPTION 'CLIENT_CONTROLLED_TIME'; END IF;
  BEGIN
    INSERT INTO public.table_messages(table_id,sender_id,role,content,membership_event)
    VALUES('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003',
      'spectator','spoof','{"action":"join"}');
    RAISE EXCEPTION 'SYSTEM_SPOOF_ACCEPTED';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'CHAT_SYSTEM_EVENT_SERVER_ONLY' THEN RAISE; END IF;
  END;
  BEGIN
    INSERT INTO public.table_messages(table_id,sender_id,role,content)
    VALUES('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','player','spoof');
    RAISE EXCEPTION 'SENDER_SPOOF_ACCEPTED';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000004',true);
DO $$ BEGIN
  IF EXISTS(SELECT 1 FROM public.table_messages) THEN RAISE EXCEPTION 'OUTSIDER_READ'; END IF;
  BEGIN
    INSERT INTO public.table_messages(table_id,sender_id,role,content)
    VALUES('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000004','player','outside');
    RAISE EXCEPTION 'OUTSIDER_WRITE';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
INSERT INTO public.table_messages(table_id,sender_id,role,content,type,voice_url,duration)
VALUES('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001',
  'player','voice','voice','test.m4a',3);
DO $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.table_messages WHERE content='old conversation')
    THEN RAISE EXCEPTION 'EXISTING_MEMBER_HISTORY_LOST'; END IF;
END $$;
RESET ROLE;
DELETE FROM public.table_players WHERE user_id='00000000-0000-4000-8000-000000000002';
DELETE FROM public.table_spectators WHERE user_id='00000000-0000-4000-8000-000000000003';
DO $$ BEGIN
  IF (SELECT count(*) FROM public.table_messages WHERE membership_event->>'action'='leave')<>2
    THEN RAISE EXCEPTION 'LEAVE_EVENTS_MISSING'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.table_messages WHERE membership_event->>'username'='Berkay'
    AND membership_event->>'action'='leave') THEN RAISE EXCEPTION 'LEAVE_IDENTITY_LOST'; END IF;
END $$;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',true);
DO $$ BEGIN
  IF EXISTS(SELECT 1 FROM public.table_messages) THEN RAISE EXCEPTION 'LEFT_VIEWER_READ'; END IF;
END $$;
RESET ROLE;
INSERT INTO public.table_spectators(table_id,user_id)
VALUES('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003');
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  IF (SELECT count(*) FROM public.table_messages)<>1 THEN RAISE EXCEPTION 'REENTRY_HISTORY_LEAK'; END IF;
END $$;
RESET ROLE;
-- Moving a membership updates both streams and revokes old table access.
UPDATE public.table_spectators SET table_id='10000000-0000-4000-8000-000000000002'
WHERE user_id='00000000-0000-4000-8000-000000000003';
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  IF EXISTS(SELECT 1 FROM public.table_messages
    WHERE table_id='10000000-0000-4000-8000-000000000001') THEN
    RAISE EXCEPTION 'MOVED_VIEWER_OLD_TABLE_ACCESS'; END IF;
  IF (SELECT count(*) FROM public.table_messages)<>1 THEN RAISE EXCEPTION 'MOVE_JOIN_MISSING'; END IF;
  BEGIN
    PERFORM 1 FROM okeyix_chat_private.memberships;
    RAISE EXCEPTION 'PRIVATE_WINDOWS_EXPOSED';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
UPDATE public.tables SET spectators_enabled=false
WHERE id='10000000-0000-4000-8000-000000000002';
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  IF EXISTS(SELECT 1 FROM public.table_messages) THEN RAISE EXCEPTION 'DISABLED_SPECTATORS_READ'; END IF;
END $$;
RESET ROLE;
UPDATE public.tables SET chat_enabled=false,spectators_enabled=true;
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  BEGIN
    INSERT INTO public.table_messages(table_id,sender_id,role,content)
    VALUES('10000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000003','spectator','disabled');
    RAISE EXCEPTION 'DISABLED_CHAT_WRITE';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
DELETE FROM public.tables;
DO $$ BEGIN
  IF EXISTS(SELECT 1 FROM public.table_messages) OR EXISTS(SELECT 1 FROM okeyix_chat_private.memberships)
    THEN RAISE EXCEPTION 'TABLE_CASCADE_BROKEN'; END IF;
END $$;
ROLLBACK;
\echo 'Chat membership/RLS tests passed.'

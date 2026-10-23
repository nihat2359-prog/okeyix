-- Run AFTER 003. Does not modify Auth, user, profile, coin or rating records.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
DO $$ BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'READY_TABLES_REQUIRES_POSTGRES'; END IF;
  IF to_regclass('okeyix_ready_private.policy') IS NULL THEN
    RAISE EXCEPTION 'READY_TABLES_INSTALL_003_FIRST'; END IF;
  IF NOT EXISTS(SELECT 1 FROM auth.users
    WHERE id='c1788536-38fa-407a-8fdc-02bf4d94d3c1'::uuid) THEN
    RAISE EXCEPTION 'READY_TABLES_OWNER_NOT_IN_AUTH_USERS'; END IF;
END $$;

CREATE OR REPLACE FUNCTION okeyix_ready_private.valid_owner(p_owner uuid) RETURNS boolean
LANGUAGE sql STABLE SET search_path=pg_catalog,pg_temp AS $$
  SELECT p_owner='c1788536-38fa-407a-8fdc-02bf4d94d3c1'::uuid
    AND EXISTS(SELECT 1 FROM auth.users WHERE id=p_owner);
$$;

CREATE OR REPLACE FUNCTION okeyix_ready_private.guard_policy() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
BEGIN
  IF NOT okeyix_bot_wallet_private.trusted() THEN
    RAISE EXCEPTION 'READY_TABLES_SERVER_ONLY' USING ERRCODE='42501'; END IF;
  IF NEW.owner_id IS NOT NULL AND (NEW.enabled OR NEW.owner_id IS DISTINCT FROM OLD.owner_id) THEN
    IF NOT okeyix_ready_private.valid_owner(NEW.owner_id) THEN
      RAISE EXCEPTION 'READY_TABLES_FIXED_OWNER_REQUIRED'; END IF;
    IF EXISTS(SELECT 1 FROM okeyix_ready_private.managed m
      JOIN public.tables t ON t.id=m.table_id WHERE t.created_by<>NEW.owner_id) THEN
      RAISE EXCEPTION 'READY_TABLES_OWNER_IN_USE'; END IF;
  END IF;
  RETURN NEW;
END $$;

DO $$ BEGIN
  UPDATE okeyix_ready_private.policy
    SET owner_id='c1788536-38fa-407a-8fdc-02bf4d94d3c1'::uuid,enabled=true,target=3
    WHERE singleton;
  IF NOT FOUND THEN RAISE EXCEPTION 'READY_TABLES_POLICY_MISSING'; END IF;
END $$;
COMMIT;

-- Existing minute watchdog fills the tables; no extra cron needed.
SELECT enabled AS aktif,target AS lig_basina_hedef,owner_id AS masa_sahibi
FROM okeyix_ready_private.policy;

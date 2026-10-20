-- MANUAL ROLLBACK, not a migration. NOT APPLIED.
-- Use during a maintenance window. Stop new RPC traffic first.
-- Retains ALL event receipts and permanent history; does not undo any payments.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $restore$
DECLARE x record; d text; g record; target text;
BEGIN
  IF current_user<>'postgres' THEN RAISE EXCEPTION 'STAT_RESTORE_REQUIRES_POSTGRES'; END IF;
  IF pg_catalog.to_regclass('cron.job') IS NOT NULL THEN
    FOR x IN EXECUTE 'SELECT jobid FROM cron.job WHERE jobname=''okeyix-stat-projector''' LOOP
      EXECUTE 'SELECT cron.unschedule($1)' USING x.jobid;
    END LOOP;
  END IF;
  DROP TRIGGER IF EXISTS okeyix_stat_table_reset ON public.tables;
  DROP TRIGGER IF EXISTS okeyix_stat_table_delete ON public.tables;
  FOR x IN SELECT * FROM okeyix_stat_private.original_acl ORDER BY name LOOP
    d:=pg_catalog.pg_get_functiondef(pg_catalog.to_regprocedure(
      'okeyix_stat_private.source_'||x.name||'('||x.arguments||')'));
    IF d IS NULL THEN RAISE EXCEPTION 'STAT_RESTORE_SOURCE_MISSING'; END IF;
    EXECUTE replace(d,'CREATE OR REPLACE FUNCTION okeyix_stat_private.source_'||x.name||'(',
      'CREATE OR REPLACE FUNCTION public.'||x.name||'(');
    target:='public.'||quote_ident(x.name)||'('||x.arguments||')';
    EXECUTE 'REVOKE ALL ON FUNCTION '||target||' FROM PUBLIC,anon,authenticated,service_role';
    FOR g IN SELECT * FROM pg_catalog.aclexplode(COALESCE(x.acl,
      pg_catalog.acldefault('f',(SELECT oid FROM pg_catalog.pg_roles WHERE rolname='postgres')))) LOOP
      EXECUTE 'GRANT '||g.privilege_type||' ON FUNCTION '||target||' TO '||
        CASE WHEN g.grantee=0 THEN 'PUBLIC' ELSE quote_ident(pg_catalog.pg_get_userbyid(g.grantee)) END||
        CASE WHEN g.is_grantable THEN ' WITH GRANT OPTION' ELSE '' END;
    END LOOP;
  END LOOP;
END $restore$;
COMMIT;

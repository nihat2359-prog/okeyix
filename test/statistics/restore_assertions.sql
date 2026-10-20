-- LOCAL ONLY. Run after concurrency.ps1 and 04_pause_and_restore.sql.
DO $$
DECLARE x record; a text; b text;
BEGIN
  IF current_database() NOT LIKE 'okeyix_stat_test_%'
    OR inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet
  THEN RAISE EXCEPTION 'LOCAL_TEST_DATABASE_REQUIRED'; END IF;
  FOR x IN SELECT * FROM okeyix_stat_private.original_acl LOOP
    a:=pg_get_functiondef(to_regprocedure('public.'||x.name||'('||x.arguments||')'));
    b:=replace(pg_get_functiondef(to_regprocedure('okeyix_stat_private.source_'||x.name||'('||x.arguments||')')),
      'CREATE OR REPLACE FUNCTION okeyix_stat_private.source_'||x.name||'(',
      'CREATE OR REPLACE FUNCTION public.'||x.name||'(');
    IF a IS DISTINCT FROM b THEN RAISE EXCEPTION 'RESTORE_BODY_MISMATCH: %',x.name; END IF;
  END LOOP;
  IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgname IN ('okeyix_stat_table_reset','okeyix_stat_table_delete'))
    OR (SELECT count(*) FROM public.okeyix_stat_rounds WHERE status='completed')<>1
    OR (SELECT count(*) FROM okeyix_stat_private.events)<>2
    OR NOT has_function_privilege('anon','public.start_game(uuid)','EXECUTE')
  THEN RAISE EXCEPTION 'RESTORE_STATE_MISMATCH'; END IF;
END $$;
SELECT 'restore body, permissions and retained history assertions passed' AS result;

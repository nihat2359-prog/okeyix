param(
  [string]$Database='okeyix_stat_test_004',
  [string]$Psql='C:\Program Files\PostgreSQL\16\bin\psql.exe'
)
$ErrorActionPreference='Stop'
if ($Database -notmatch '^okeyix_stat_test_[a-zA-Z0-9_]+$') { throw 'Local test database name required' }
$work=Join-Path (Get-Location) '.dart_tool/stat_concurrency'
[IO.Directory]::CreateDirectory($work) | Out-Null
$connection=@('-X','-h','127.0.0.1','-p','55439','-U','postgres','-d',$Database,'-v','ON_ERROR_STOP=1')
function Write-Sql([string]$Name,[string]$Sql) {
  $path=Join-Path $work ($Name+'.sql')
  [IO.File]::WriteAllText($path,$Sql,[Text.UTF8Encoding]::new($false))
  return $path
}
function Run-Sql([string]$Name,[string]$Sql) {
  $path=Write-Sql $Name $Sql
  & $Psql @connection -f $path
  if ($LASTEXITCODE -ne 0) { throw "SQL test failed: $Name" }
}
function Start-Sql([string]$Name,[string]$Sql) {
  $path=Write-Sql $Name $Sql
  $out=Join-Path $work ($Name+'.out')
  $err=Join-Path $work ($Name+'.err')
  $args=$connection + @('-f',('"'+$path+'"'))
  $process=Start-Process -FilePath $Psql -ArgumentList $args -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
  # Keep the process handle before a fast child exits (Windows PowerShell 5).
  $null=$process.Handle
  return @{Process=$process;Out=$out;Err=$err}
}
function End-Sql($Job,[bool]$ExpectedFailure=$false) {
  if (-not $Job.Process.WaitForExit(15000)) { throw 'Local concurrent SQL exceeded 15 seconds' }
  $Job.Process.WaitForExit()
  $errorText=[IO.File]::ReadAllText($Job.Err)
  if ($ExpectedFailure) {
    if ($Job.Process.ExitCode -eq 0 -or $errorText -notmatch 'TABLE_NOT_PLAYING') { throw 'Second finish did not reject safely' }
  } elseif ($Job.Process.ExitCode -ne 0) { throw $errorText }
}
$guard=@'
DO $$ BEGIN
  IF current_database() NOT LIKE 'okeyix_stat_test_%' OR inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet
    THEN RAISE EXCEPTION 'LOCAL_TEST_DATABASE_REQUIRED'; END IF;
END $$;
SET lock_timeout='8s'; SET statement_timeout='12s';
'@
$actor=@'
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
SELECT set_config('request.jwt.claim.role','authenticated',false);
SET ROLE authenticated;
'@
Run-Sql 'setup' ($guard+@'
INSERT INTO public.users(id,is_bot) VALUES
('00000000-0000-4000-8000-000000000001',false),('00000000-0000-4000-8000-000000000002',true);
INSERT INTO public.profiles(id,username,coins,rating) VALUES
('00000000-0000-4000-8000-000000000001','Local A',10000,1200),('00000000-0000-4000-8000-000000000002','Local Bot',10000,1200);
INSERT INTO public.tables(id,league_id,created_by,max_players,entry_coin,min_rounds) VALUES
('00000000-0000-4000-8000-000000000100','standard','00000000-0000-4000-8000-000000000001',2,100,1);
INSERT INTO public.table_players(table_id,user_id,seat_index) VALUES
('00000000-0000-4000-8000-000000000100','00000000-0000-4000-8000-000000000001',0),
('00000000-0000-4000-8000-000000000100','00000000-0000-4000-8000-000000000002',1);
'@)
$start="SELECT public.start_game('00000000-0000-4000-8000-000000000100');"
$a=Start-Sql 'start_a' ($guard+$actor+"BEGIN; $start SELECT pg_sleep(1.5); COMMIT;")
Start-Sleep -Milliseconds 300
$b=Start-Sql 'start_b' ($guard+$actor+$start)
End-Sql $a
End-Sql $b
if ([IO.File]::ReadAllText($b.Out) -notmatch 'already_playing') { throw 'Concurrent start was not idempotent' }
$integration=Get-Content test/statistics/integration.sql -Raw
$finishHelper=[regex]::Match($integration,'CREATE FUNCTION pg_temp\.finish_hand[\s\S]+?END \$\$;').Value
if (-not $finishHelper) { throw 'Finish helper not found' }
$finish="SELECT pg_temp.finish_hand('00000000-0000-4000-8000-000000000100','00000000-0000-4000-8000-000000000001');"
$a=Start-Sql 'finish_a' ($guard+$finishHelper+$actor+"BEGIN; $finish SELECT pg_sleep(1.5); COMMIT;")
Start-Sleep -Milliseconds 300
$b=Start-Sql 'finish_b' ($guard+$finishHelper+$actor+"BEGIN; $finish COMMIT;")
End-Sql $a
End-Sql $b $true
$a=Start-Sql 'worker_a' ($guard+'BEGIN; SELECT okeyix_stat_private.process_events(100); SELECT pg_sleep(1.5); COMMIT;')
Start-Sleep -Milliseconds 300
$b=Start-Sql 'worker_b' ($guard+'SELECT okeyix_stat_private.process_events(100);')
End-Sql $a
End-Sql $b
if ([IO.File]::ReadAllText($b.Out) -notmatch "`r?`n\s*0`r?`n") { throw 'Concurrent worker did not yield the worker lock' }
Run-Sql 'assertions' ($guard+@'
DO $$ BEGIN
 IF (SELECT count(*) FROM okeyix_stat_private.events WHERE table_id='00000000-0000-4000-8000-000000000100')<>2
 OR (SELECT count(*) FROM public.wallet_transactions WHERE user_id IN
   ('00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002') AND reason='table_entry')<>2
 OR (SELECT count(*) FROM public.wallet_transactions WHERE user_id='00000000-0000-4000-8000-000000000001' AND reason='game_win')<>1
 OR (SELECT wins FROM public.users WHERE id='00000000-0000-4000-8000-000000000001')<>1
 OR (SELECT count(*) FROM public.okeyix_stat_rounds WHERE status='completed')<>1
 OR EXISTS(SELECT 1 FROM okeyix_stat_private.events WHERE processed_at IS NULL)
 THEN RAISE EXCEPTION 'CONCURRENT_RESULT_MISMATCH'; END IF;
END $$;
'@)
Write-Output 'Concurrent start, finish and worker assertions passed.'

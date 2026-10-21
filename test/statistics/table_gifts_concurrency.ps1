param([string]$Database='okeyix_stat_test_gifts_002',
  [string]$Psql='C:\Program Files\PostgreSQL\16\bin\psql.exe')
$ErrorActionPreference='Stop'
if ($Database -notmatch '^okeyix_stat_test_[a-zA-Z0-9_]+$') { throw 'Local database required' }
$work=Join-Path (Get-Location) '.dart_tool/gift_concurrency'
[IO.Directory]::CreateDirectory($work) | Out-Null
$connection=@('-X','-h','127.0.0.1','-p','55439','-U','postgres','-d',$Database,'-v','ON_ERROR_STOP=1')
function File-Sql([string]$Name,[string]$Sql) {
  $path=Join-Path $work ($Name+'.sql')
  [IO.File]::WriteAllText($path,$Sql,[Text.UTF8Encoding]::new($false)); return $path
}
function Run-Sql([string]$Name,[string]$Sql) {
  & $Psql @connection -f (File-Sql $Name $Sql)
  if ($LASTEXITCODE -ne 0) { throw "SQL failure: $Name" }
}
function Start-Sql([string]$Name,[string]$Sql) {
  $path=File-Sql $Name $Sql
  $out=Join-Path $work ($Name+'.out'); $err=Join-Path $work ($Name+'.err')
  $process=Start-Process -FilePath $Psql -ArgumentList ($connection+@('-f',('"'+$path+'"'))) -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
  $null=$process.Handle; return @{Process=$process;Err=$err}
}
function End-Sql($Job,[bool]$Insufficient=$false) {
  if (-not $Job.Process.WaitForExit(15000)) { throw 'Concurrent test timed out' }
  $Job.Process.WaitForExit(); $errorText=[IO.File]::ReadAllText($Job.Err)
  if ($Insufficient) {
    if ($Job.Process.ExitCode -eq 0 -or $errorText -notmatch 'GIFT_INSUFFICIENT_COINS') { throw 'Expected insufficient coins' }
  } elseif ($Job.Process.ExitCode -ne 0) { throw $errorText }
}
Run-Sql 'setup' @'
DO $$ BEGIN IF current_database() NOT LIKE 'okeyix_stat_test_%' OR inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet THEN RAISE EXCEPTION 'LOCAL_ONLY'; END IF; END $$;
INSERT INTO public.users(id,username) VALUES('00000000-0000-4000-8001-000000000001','Gift A'),('00000000-0000-4000-8001-000000000002','Gift B');
INSERT INTO public.profiles(id,username,coins) VALUES('00000000-0000-4000-8001-000000000001','A',2500),('00000000-0000-4000-8001-000000000002','B',10000);
INSERT INTO public.tables(id,created_by,league_id,entry_coin,min_rounds,max_players,status) VALUES('00000000-0000-4000-8001-000000000100','00000000-0000-4000-8001-000000000001','test',100,1,2,'playing');
INSERT INTO public.table_players(table_id,user_id,seat_index) VALUES('00000000-0000-4000-8001-000000000100','00000000-0000-4000-8001-000000000001',0),('00000000-0000-4000-8001-000000000100','00000000-0000-4000-8001-000000000002',1);
'@
$actor=@'
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8001-000000000001',false);
SET ROLE authenticated;
SET lock_timeout='8s'; SET statement_timeout='12s';
'@
$buy="SELECT public.okeyix_buy_table_gift('00000000-0000-4000-8001-000000000100','00000000-0000-4000-8001-000000000002','cay',"
$a=Start-Sql 'same_a' ($actor+"BEGIN; "+$buy+"'00000000-0000-4000-8001-000000000200'); SELECT pg_sleep(2); COMMIT;")
Start-Sleep -Milliseconds 600
$b=Start-Sql 'same_b' ($actor+$buy+"'00000000-0000-4000-8001-000000000200');")
End-Sql $a; End-Sql $b
$a=Start-Sql 'balance_a' ($actor+"BEGIN; "+$buy+"'00000000-0000-4000-8001-000000000201'); SELECT pg_sleep(2); COMMIT;")
Start-Sleep -Milliseconds 600
$b=Start-Sql 'balance_b' ($actor+$buy+"'00000000-0000-4000-8001-000000000202');")
End-Sql $a; End-Sql $b $true
Run-Sql 'assertions' @'
DO $$ BEGIN
 IF (SELECT coins FROM public.profiles WHERE id='00000000-0000-4000-8001-000000000001')<>500
 OR (SELECT count(*) FROM public.okeyix_table_gift_purchases WHERE table_id='00000000-0000-4000-8001-000000000100')<>2
 OR (SELECT count(*) FROM public.wallet_transactions WHERE user_id='00000000-0000-4000-8001-000000000001')<>2
 THEN RAISE EXCEPTION 'CONCURRENT_GIFT_INVARIANT_FAILED'; END IF;
END $$;
SELECT 'same request charged once; competing requests cannot overspend' AS result;
'@

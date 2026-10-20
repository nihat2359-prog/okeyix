param([string]$Database='okeyix_stat_test_referrals_001',
  [string]$Psql='C:\Program Files\PostgreSQL\16\bin\psql.exe')
$ErrorActionPreference='Stop'
if ($Database -notmatch '^okeyix_stat_test_[a-zA-Z0-9_]+$') { throw 'Local database required' }
$work=Join-Path (Get-Location) '.dart_tool/referral_concurrency'
[IO.Directory]::CreateDirectory($work) | Out-Null
$connection=@('-X','-h','127.0.0.1','-p','55439','-U','postgres','-d',$Database,'-v','ON_ERROR_STOP=1')
function File-Sql([string]$Name,[string]$Sql) {
  $path=Join-Path $work ($Name+'.sql')
  [IO.File]::WriteAllText($path,$Sql,[Text.UTF8Encoding]::new($false))
  return $path
}
function Run-Sql([string]$Name,[string]$Sql) {
  & $Psql @connection -f (File-Sql $Name $Sql)
  if ($LASTEXITCODE -ne 0) { throw "SQL failure: $Name" }
}
function Start-Sql([string]$Name,[string]$Sql) {
  $path=File-Sql $Name $Sql
  $out=Join-Path $work ($Name+'.out'); $err=Join-Path $work ($Name+'.err')
  $process=Start-Process -FilePath $Psql -ArgumentList ($connection+@('-f',('"'+$path+'"'))) -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
  $null=$process.Handle
  return @{Process=$process;Err=$err}
}
function End-Sql($Job) {
  if (-not $Job.Process.WaitForExit(15000)) { throw 'Concurrent test timed out' }
  $Job.Process.WaitForExit()
  if ($Job.Process.ExitCode -ne 0) { throw ([IO.File]::ReadAllText($Job.Err)) }
}
Run-Sql 'setup' @'
DO $$ BEGIN
  IF current_database() NOT LIKE 'okeyix_stat_test_%' OR inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet
    THEN RAISE EXCEPTION 'LOCAL_ONLY'; END IF;
END $$;
INSERT INTO public.users(id,username) VALUES
('00000000-0000-4000-9000-000000000001','Concurrency A'),
('00000000-0000-4000-9000-000000000002','Concurrency B'),
('00000000-0000-4000-9000-000000000003','Concurrency C');
INSERT INTO public.profiles(id,username,coins) SELECT id,username,10000 FROM public.users WHERE id::text LIKE '00000000-0000-4000-9000-%';
INSERT INTO okeyix_referral_private.codes(user_id,code) VALUES
('00000000-0000-4000-9000-000000000001','ABCDEF123456');
'@
$actor=@'
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-9000-000000000002',false);
SET ROLE authenticated;
'@
$a=Start-Sql 'redeem_a' ($actor+@'
BEGIN;
SELECT public.okeyix_redeem_invite('ABCDEF123456');
SELECT pg_sleep(2);
COMMIT;
'@)
Start-Sleep -Milliseconds 600
$b=Start-Sql 'redeem_b' ($actor+"SELECT public.okeyix_redeem_invite('ABCDEF123456');")
End-Sql $a; End-Sql $b
Run-Sql 'ten_hands' @'
DO $$ DECLARE s uuid; r uuid; n integer;
BEGIN
  IF (SELECT count(*) FROM okeyix_referral_private.invitations)<>1 THEN RAISE EXCEPTION 'duplicate invitation'; END IF;
  FOR n IN 1..10 LOOP
    INSERT INTO public.okeyix_stat_sessions(table_id,league_id,entry_coin,started_at)
      VALUES(gen_random_uuid(),'test',100,now()) RETURNING id INTO s;
    INSERT INTO public.okeyix_stat_rounds(session_id,source_start_key,round_no,status,winner_user_id,started_at,finished_at)
      VALUES(s,gen_random_uuid()::text,1,'completed','00000000-0000-4000-9000-000000000002',now(),clock_timestamp()) RETURNING id INTO r;
    INSERT INTO public.okeyix_stat_players(round_id,user_id,round_started_at,seat_index,is_bot,outcome) VALUES
      (r,'00000000-0000-4000-9000-000000000002',now(),0,false,'win'),
      (r,'00000000-0000-4000-9000-000000000003',now(),1,false,'loss');
  END LOOP;
END $$;
'@
$a=Start-Sql 'worker_a' "BEGIN; SELECT okeyix_referral_private.process(100); SELECT pg_sleep(2); COMMIT;"
Start-Sleep -Milliseconds 600
$b=Start-Sql 'worker_b' 'SELECT okeyix_referral_private.process(100);'
End-Sql $a; End-Sql $b
Run-Sql 'assertions' @'
DO $$ BEGIN
  IF (SELECT count(*) FROM okeyix_referral_private.payments)<>2
    OR (SELECT count(*) FROM public.wallet_transactions WHERE reason='friend_referral')<>2
    OR (SELECT count(*) FROM public.profiles WHERE id IN('00000000-0000-4000-9000-000000000001','00000000-0000-4000-9000-000000000002') AND coins=1010000)<>2
    THEN RAISE EXCEPTION 'CONCURRENT_PAYMENT_INVARIANT_FAILED'; END IF;
END $$;
SELECT 'concurrent redemption and workers: exactly one invitation and two credits' AS result;
'@

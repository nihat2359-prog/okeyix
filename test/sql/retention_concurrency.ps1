param([string]$Psql='C:\Program Files\PostgreSQL\16\bin\psql.exe')
$ErrorActionPreference='Stop'
$testRoot=Join-Path (Get-Location) ('.dart_tool/retention-concurrency-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$encoding=[Text.UTF8Encoding]::new($false)
$newSql=Join-Path $testRoot 'new.sql'
$oldSql=Join-Path $testRoot 'old.sql'
$guard="DO `$`$ BEGIN IF current_database()<>'okeyix_retention_test' THEN RAISE EXCEPTION 'LOCAL_TEST_DATABASE_REQUIRED'; END IF; END `$`$;"
$prefix=@('-X','-h','127.0.0.1','-p','55447','-U','postgres','-d','okeyix_retention_test','-v','ON_ERROR_STOP=1')
$resetPath=Join-Path $testRoot 'reset.sql'
[IO.File]::WriteAllText($resetPath,"$guard`nDELETE FROM public.wallet_transactions; DELETE FROM okeyix_retention_private.reward_progress; UPDATE public.profiles SET coins=1000;",$encoding)
& $Psql @prefix -f $resetPath
if($LASTEXITCODE -ne 0){throw 'Local test reset failed'}
function Run-Race([string]$uid,[bool]$mixed) {
  $auth="SELECT set_config('request.jwt.claim.sub','$uid',false); SELECT pg_sleep(0.15);"
  [IO.File]::WriteAllText($newSql,"$guard`n$auth`nSELECT public.okeyix_claim_daily_reward();",$encoding)
  [IO.File]::WriteAllText($oldSql,"$guard`n$auth`nSELECT public.claim_daily_bonus('$uid',999999,'spoofed');",$encoding)
  $jobs=@()
  for($i=0;$i -lt 8;$i++) {
    $sqlPath=if($mixed -and $i%2 -eq 0){$oldSql}else{$newSql}
    $job=Start-Process -FilePath $Psql -WindowStyle Hidden -PassThru `
      -ArgumentList ($prefix+@('-f',('"'+$sqlPath+'"'))) `
      -RedirectStandardOutput (Join-Path $testRoot "$uid-$i.out") `
      -RedirectStandardError (Join-Path $testRoot "$uid-$i.err")
    $null=$job.Handle
    $jobs+=$job
  }
  foreach($job in $jobs) {
    if(-not $job.WaitForExit(20000)){throw 'Local concurrency test timed out'}
    if($job.ExitCode -ne 0){throw "Local claim process failed: $($job.ExitCode)"}
    $job.Dispose()
  }
}
Run-Race '00000000-0000-4000-8000-000000000001' $false
Run-Race '00000000-0000-4000-8000-000000000002' $true
$assertPath=Join-Path $testRoot 'assert.sql'
$assert=@'
DO $$ BEGIN
  IF current_database()<>'okeyix_retention_test' THEN RAISE EXCEPTION 'LOCAL_TEST_DATABASE_REQUIRED'; END IF;
  IF EXISTS(SELECT 1 FROM public.profiles WHERE coins<>3500) THEN RAISE EXCEPTION 'CONCURRENT_BALANCE_FAILED'; END IF;
  IF (SELECT count(*) FROM public.wallet_transactions)<>2 THEN RAISE EXCEPTION 'CONCURRENT_RECEIPTS_FAILED'; END IF;
  IF (SELECT claims FROM okeyix_retention_private.reward_progress WHERE user_id='00000000-0000-4000-8000-000000000001')<>1 THEN
    RAISE EXCEPTION 'CONCURRENT_PROGRESS_FAILED'; END IF;
END $$;
'@
[IO.File]::WriteAllText($assertPath,$assert,$encoding)
& $Psql @prefix -f $assertPath
if($LASTEXITCODE -ne 0){throw 'Local concurrency assertions failed'}
Write-Output 'PASS: 8 new/new and 8 mixed legacy/new claims produced one credit per user.'

param([string]$PgBin = 'C:\Program Files\PostgreSQL\16\bin')
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $workspace ('.dart_tool\bot-wallet-test-' + [guid]::NewGuid().ToString('N'))
$dataPath = Join-Path $testRoot 'data'
$pgCtl = Join-Path $PgBin 'pg_ctl.exe'
$psql = Join-Path $PgBin 'psql.exe'
$port = 56484
$utf8 = [Text.UTF8Encoding]::new($false)
New-Item -ItemType Directory -Path $testRoot | Out-Null
function Invoke-LocalSql([string]$File) {
  & $psql -X -h 127.0.0.1 -p $port -U postgres -d okeyix_bot_wallet_test -v ON_ERROR_STOP=1 -f $File
  if ($LASTEXITCODE -ne 0) { throw "SQL failed: $File" }
}
$started = $false
try {
  & (Join-Path $PgBin 'initdb.exe') -D $dataPath -U postgres -A trust --no-locale -E UTF8 *> (Join-Path $testRoot 'init.log')
  if ($LASTEXITCODE -ne 0) { throw 'initdb failed' }
  $serverLog = Join-Path $testRoot 'server.log'
  $launcher = Start-Process -FilePath $pgCtl -ArgumentList @('-D',"`"$dataPath`"",'-l',"`"$serverLog`"",'-o',"`"-p $port -h 127.0.0.1`"",'start') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $testRoot 'start.log') -RedirectStandardError (Join-Path $testRoot 'start-error.log')
  $ready = $false
  for ($attempt=0; $attempt -lt 40; $attempt++) {
    & (Join-Path $PgBin 'pg_isready.exe') -h 127.0.0.1 -p $port -U postgres *> $null
    if ($LASTEXITCODE -eq 0) { $ready=$true; break }
    Start-Sleep -Milliseconds 250
  }
  if (!$ready) { throw 'Local PostgreSQL start failed (port may be occupied)' }
  $actualDataPath = & $psql -X -w -At -h 127.0.0.1 -p $port -U postgres -d postgres -c 'SHOW data_directory'
  if ([IO.Path]::GetFullPath($actualDataPath) -ne [IO.Path]::GetFullPath($dataPath)) {
    throw 'Port belongs to another PostgreSQL instance; refusing to run tests'
  }
  $started = $true
  & (Join-Path $PgBin 'createdb.exe') -h 127.0.0.1 -p $port -U postgres okeyix_bot_wallet_test
  if ($LASTEXITCODE -ne 0) { throw 'createdb failed' }
  Invoke-LocalSql (Join-Path $workspace 'test\sql\bot_wallet_fixture.sql')
  Invoke-LocalSql (Join-Path $workspace 'docs\bot_wallet_preflight.sql')
  $migration = Join-Path $workspace 'supabase\migrations\20261021000400_bot_wallet_reserve.sql'
  # Unmodified production precondition must REJECT contract doubles.
  $guardLog = Join-Path $testRoot 'source-guard.log'
  $savedPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  & $psql -X -h 127.0.0.1 -p $port -U postgres -d okeyix_bot_wallet_test -v ON_ERROR_STOP=1 -f $migration *> $guardLog
  $guardExit = $LASTEXITCODE
  $ErrorActionPreference = $savedPreference
  $guardText = [regex]::Replace([IO.File]::ReadAllText($guardLog),'\s','')
  if ($guardExit -eq 0 -or !$guardText.Contains('BOT_RESERVE_SOURCE_CHANGED')) {
    throw 'Production source fingerprint guard did not reject the fixture'
  }
  # The local financial tests use API doubles, so adapt ONLY the two expected
  # fingerprints in a disposable COPY. Production SQL is never edited.
  $hashes = & $psql -X -At -h 127.0.0.1 -p $port -U postgres -d okeyix_bot_wallet_test -c "SELECT md5(prosrc) FROM pg_proc WHERE oid IN ('public.run_okey_watchdog()'::regprocedure,'public.run_standard_bot_table_maintainer(integer,boolean)'::regprocedure) ORDER BY proname"
  if ($LASTEXITCODE -ne 0 -or $hashes.Count -ne 2) { throw 'Fixture hash lookup failed' }
  $localMigration = [IO.File]::ReadAllText($migration).Replace('b60311af82a4e64d13541944d251149f',$hashes[0]).Replace('b2d85bfb32b8057267a3fedce7421ecb',$hashes[1])
  $localMigrationPath = Join-Path $testRoot 'migration-with-fixture-fingerprints.sql'
  [IO.File]::WriteAllText($localMigrationPath,$localMigration,$utf8)
  Invoke-LocalSql $localMigrationPath
  Invoke-LocalSql (Join-Path $workspace 'test\sql\bot_wallet_reserve_test.sql')
  # Two real connections overlap while the first holds its wallet row lock.
  $concurrentSql = Join-Path $testRoot 'concurrent.sql'
  [IO.File]::WriteAllText($concurrentSql,"BEGIN; SELECT okeyix_bot_wallet_private.replenish('watchdog'); SELECT pg_sleep(2); COMMIT;",$utf8)
  $before = & $psql -X -At -h 127.0.0.1 -p $port -U postgres -d okeyix_bot_wallet_test -c 'SELECT count(*) FROM okeyix_bot_wallet_private.topups'
  $first = Start-Process -FilePath $psql -ArgumentList @('-X','-h','127.0.0.1','-p',"$port",'-U','postgres','-d','okeyix_bot_wallet_test','-v','ON_ERROR_STOP=1','-f',"`"$concurrentSql`"") -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $testRoot 'concurrent-first.log') -RedirectStandardError (Join-Path $testRoot 'concurrent-first-error.log')
  $firstHandle = $first.Handle
  $overlap = $false
  for ($attempt=0; $attempt -lt 25; $attempt++) {
    $sleeping = & $psql -X -At -h 127.0.0.1 -p $port -U postgres -d okeyix_bot_wallet_test -c "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND state='active' AND query='SELECT pg_sleep(2);'"
    if ([int]$sleeping -gt 0) { $overlap=$true; break }
    Start-Sleep -Milliseconds 50
  }
  if (!$overlap) { throw 'Could not establish concurrent lock overlap' }
  & $psql -X -h 127.0.0.1 -p $port -U postgres -d okeyix_bot_wallet_test -v ON_ERROR_STOP=1 -c "SELECT okeyix_bot_wallet_private.replenish('watchdog');"
  if ($LASTEXITCODE -ne 0) { throw 'Second concurrent request failed' }
  $first.WaitForExit()
  $first.Refresh()
  if (($null -ne $first.ExitCode -and $first.ExitCode -ne 0) -or
      (Get-Item (Join-Path $testRoot 'concurrent-first-error.log')).Length -gt 0 -or
      !([IO.File]::ReadAllText((Join-Path $testRoot 'concurrent-first.log')).Contains('COMMIT'))) {
    throw 'First concurrent request failed'
  }
  $after = & $psql -X -At -h 127.0.0.1 -p $port -U postgres -d okeyix_bot_wallet_test -c 'SELECT count(*) FROM okeyix_bot_wallet_private.topups'
  if ([int]$after -ne [int]$before+1) { throw 'Concurrent refill produced duplicate/missing receipts' }
  & $psql -X -h 127.0.0.1 -p $port -U postgres -d okeyix_bot_wallet_test -v ON_ERROR_STOP=1 -c "SELECT public.test_assert((SELECT coins=200000000 FROM public.profiles WHERE id='00000000-0000-0000-0000-000000000001'),'concurrent target exact');"
  if ($LASTEXITCODE -ne 0) { throw 'Concurrent balance assertion failed' }
  Invoke-LocalSql (Join-Path $workspace 'docs\bot_wallet_installation_check.sql')
  Write-Output 'ALL BOT WALLET LOCAL TESTS PASSED (including two-session concurrency)'
  Write-Output "Artifacts: $testRoot"
} finally {
  if ($started) { & $pgCtl -D $dataPath stop -m fast }
}

param([string]$PgBin = 'C:\Program Files\PostgreSQL\16\bin')
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $workspace ('.dart_tool\bot-pool-' + [guid]::NewGuid().ToString('N'))
$dataPath = Join-Path $testRoot 'data'
$port = 56493
$psql = Join-Path $PgBin 'psql.exe'
$pgCtl = Join-Path $PgBin 'pg_ctl.exe'
$utf8 = [Text.UTF8Encoding]::new($false)
New-Item -ItemType Directory -Path $testRoot | Out-Null
function Invoke-SqlFile([string]$path) {
  & $psql -X -w -h 127.0.0.1 -p $port -U postgres -d okeyix_bot_pool_test -v ON_ERROR_STOP=1 -f $path
  if ($LASTEXITCODE -ne 0) { throw "SQL failed: $path" }
}
function Invoke-Sql([string]$sql) {
  $path = Join-Path $testRoot 'step.sql'
  [IO.File]::WriteAllText($path,$sql,$utf8)
  Invoke-SqlFile $path
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
  if (!$ready) { throw 'Local PostgreSQL did not start' }
  $actual = & $psql -X -w -At -h 127.0.0.1 -p $port -U postgres -d postgres -c 'SHOW data_directory'
  if ([IO.Path]::GetFullPath($actual) -ne [IO.Path]::GetFullPath($dataPath)) { throw 'Wrong cluster; refusing tests' }
  $started = $true
  & (Join-Path $PgBin 'createdb.exe') -h 127.0.0.1 -p $port -U postgres okeyix_bot_pool_test
  if ($LASTEXITCODE -ne 0) { throw 'createdb failed' }
  Invoke-SqlFile (Join-Path $workspace 'test\sql\bot_pool_fixture.sql')
  # Use the actual wallet tables, guards and registration trigger, unchanged.
  # Exclude the unrelated maintainer/watchdog source-hash prerequisites.
  $wallet = [IO.File]::ReadAllText((Join-Path $workspace 'supabase\migrations\20261021000400_bot_wallet_reserve.sql'))
  $start = $wallet.IndexOf('CREATE SCHEMA okeyix_bot_wallet_private')
  $end = $wallet.IndexOf('CREATE FUNCTION okeyix_bot_wallet_private.replenish')
  Invoke-Sql ("BEGIN;`n" + $wallet.Substring($start,$end-$start) + "`nCOMMIT;")
  Invoke-SqlFile (Join-Path $workspace 'test\sql\bot_pool_existing.sql')
  $migration = Join-Path $workspace 'supabase\migrations\20261125000100_expand_bot_pool.sql'

  # A human name collision must roll back the entire batch.
  Invoke-Sql "INSERT INTO public.users(id,username) VALUES('ffffffff-ffff-4000-8000-ffffffffffff','Emre K.');"
  $collisionLog = Join-Path $testRoot 'collision.log'
  $saved = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  & $psql -X -w -h 127.0.0.1 -p $port -U postgres -d okeyix_bot_pool_test -v ON_ERROR_STOP=1 -f $migration *> $collisionLog
  $collisionExit = $LASTEXITCODE
  $ErrorActionPreference = $saved
  $collisionText = [regex]::Replace([IO.File]::ReadAllText($collisionLog),'\s','')
  if ($collisionExit -eq 0 -or !$collisionText.Contains('BOT_POOL_PLAYER_NAME_COLLISION')) { throw 'Collision guard failed' }
  Invoke-Sql "SELECT public.fixture_assert((SELECT count(*)=11 FROM public.users),'collision rollback'); DELETE FROM public.profiles WHERE id='ffffffff-ffff-4000-8000-ffffffffffff'; DELETE FROM public.users WHERE id='ffffffff-ffff-4000-8000-ffffffffffff';"

  Invoke-SqlFile $migration
  Invoke-SqlFile (Join-Path $workspace 'test\sql\bot_pool_assertions.sql')
  # Reruns must preserve game-driven changes and never duplicate funding.
  Invoke-Sql "UPDATE public.profiles SET coins=12345,rating=555 WHERE id='b0251125-0150-4000-8000-000000000001';"
  Invoke-SqlFile $migration
  Invoke-Sql "SELECT public.fixture_assert((SELECT coins=12345 AND rating=555 FROM public.profiles WHERE id='b0251125-0150-4000-8000-000000000001'),'rerun preserves played balances'); SELECT public.fixture_assert((SELECT count(*)=150 FROM okeyix_bot_wallet_private.topups),'rerun no duplicate funding');"
  Write-Output 'ALL BOT POOL TESTS PASSED (150 inserts, original 10 unchanged, trigger-created profiles, name collision rollback, rerun preservation)'
} finally {
  if ($started) { & $pgCtl -D $dataPath stop -m fast }
}


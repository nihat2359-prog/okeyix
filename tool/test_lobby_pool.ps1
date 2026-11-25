param([string]$PgBin = 'C:\Program Files\PostgreSQL\16\bin')
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $workspace ('.dart_tool\lobby-pool-' + [guid]::NewGuid().ToString('N'))
$dataPath = Join-Path $testRoot 'data'
$port = 56495
$psql = Join-Path $PgBin 'psql.exe'
$pgCtl = Join-Path $PgBin 'pg_ctl.exe'
$utf8 = [Text.UTF8Encoding]::new($false)
New-Item -ItemType Directory -Path $testRoot | Out-Null
function Invoke-SqlFile([string]$path) {
  & $psql -X -w -h 127.0.0.1 -p $port -U postgres -d okeyix_lobby_pool_test -v ON_ERROR_STOP=1 -f $path
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
  & (Join-Path $PgBin 'createdb.exe') -h 127.0.0.1 -p $port -U postgres okeyix_lobby_pool_test
  if ($LASTEXITCODE -ne 0) { throw 'createdb failed' }
  foreach($relative in @('test\sql\ready_tables_fixture.sql',
    'supabase\migrations\20261022000100_quick_play.sql',
    'supabase\migrations\20261022000200_quick_play_instant.sql',
    'supabase\migrations\20261118000100_quick_play_queue.sql',
    'test\sql\lobby_pool_fixture.sql','test\fixtures\lobby_pool_sources.sql')) {
    Invoke-SqlFile (Join-Path $workspace $relative)
    if($relative -eq 'test\sql\ready_tables_fixture.sql') {
      Invoke-Sql 'CREATE FUNCTION public.leave_table(p_table_id uuid,p_user_id uuid) RETURNS void LANGUAGE sql AS $$ DELETE FROM public.table_players WHERE table_id=p_table_id AND user_id=p_user_id $$;'
    }
  }
  Invoke-Sql 'SELECT okeyix_bot_wallet_private.source_maintainer(3,true);'
  Invoke-SqlFile (Join-Path $workspace 'supabase\migrations\20261125000400_unified_lobby_pool.sql')
  Invoke-SqlFile (Join-Path $workspace 'test\sql\lobby_pool_assertions.sql')
  Write-Output 'ALL UNIFIED LOBBY POOL TESTS PASSED'
} finally {
  if ($started) { & $pgCtl -D $dataPath stop -m fast }
}

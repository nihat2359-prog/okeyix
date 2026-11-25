param([string]$PgBin = 'C:\Program Files\PostgreSQL\16\bin')
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $workspace ('.dart_tool\invite-priority-' + [guid]::NewGuid().ToString('N'))
$dataPath = Join-Path $testRoot 'data'
$port = 56494
$psql = Join-Path $PgBin 'psql.exe'
$pgCtl = Join-Path $PgBin 'pg_ctl.exe'
$utf8 = [Text.UTF8Encoding]::new($false)
New-Item -ItemType Directory -Path $testRoot | Out-Null
function Invoke-SqlFile([string]$path) {
  & $psql -X -w -h 127.0.0.1 -p $port -U postgres -d okeyix_invite_priority_test -v ON_ERROR_STOP=1 -f $path
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
  & (Join-Path $PgBin 'createdb.exe') -h 127.0.0.1 -p $port -U postgres okeyix_invite_priority_test
  if ($LASTEXITCODE -ne 0) { throw 'createdb failed' }
  Invoke-SqlFile (Join-Path $workspace 'test\sql\invite_priority_fixture.sql')
  Invoke-Sql "SELECT public.fixture_assert(NOT EXISTS(SELECT 1 FROM public.get_invitable_players(md5('target')::uuid,md5('self')::uuid,'standard',1000) WHERE username LIKE 'New bot %'),'old RPC reproduces starvation');"
  Invoke-SqlFile (Join-Path $workspace 'supabase\migrations\20261125000200_invite_player_priority.sql')
  Invoke-Sql "SELECT public.fixture_assert(NOT EXISTS(SELECT 1 FROM public.get_invitable_players(md5('target')::uuid,md5('self')::uuid,'standard',1000) r JOIN public.profiles p ON p.id=r.id WHERE NOT r.is_bot AND NOT p.is_online),'single budget reproduces empty offline tab');"
  Invoke-SqlFile (Join-Path $workspace 'supabase\migrations\20261125000300_invite_tab_budgets.sql')
  Invoke-SqlFile (Join-Path $workspace 'test\sql\invite_priority_assertions.sql')
  Write-Output 'ALL INVITE PRIORITY TESTS PASSED'
} finally {
  if ($started) { & $pgCtl -D $dataPath stop -m fast }
}

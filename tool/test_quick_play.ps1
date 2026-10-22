param([string]$PgBin = 'C:\Program Files\PostgreSQL\16\bin')
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $workspace ('.dart_tool\quick-play-test-' + [guid]::NewGuid().ToString('N'))
$dataPath = Join-Path $testRoot 'data'
$port = 56485
$psql = Join-Path $PgBin 'psql.exe'
$pgCtl = Join-Path $PgBin 'pg_ctl.exe'
$started = $false
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
  & (Join-Path $PgBin 'initdb.exe') -D $dataPath -U postgres -A trust --no-locale -E UTF8 *> (Join-Path $testRoot 'init.log')
  if ($LASTEXITCODE -ne 0) { throw 'initdb failed' }
  $launcher = Start-Process -FilePath $pgCtl -ArgumentList @('-D',"`"$dataPath`"",'-l',"`"$(Join-Path $testRoot 'server.log')`"",'-o',"`"-p $port -h 127.0.0.1`"",'start') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $testRoot 'start.log') -RedirectStandardError (Join-Path $testRoot 'start-error.log')
  $ready = $false
  for ($i=0; $i -lt 40; $i++) {
    & (Join-Path $PgBin 'pg_isready.exe') -h 127.0.0.1 -p $port -U postgres *> $null
    if ($LASTEXITCODE -eq 0) { $ready=$true; break }
    Start-Sleep -Milliseconds 250
  }
  if (!$ready) { throw 'Local PostgreSQL failed to start' }
  $actual = & $psql -X -w -At -h 127.0.0.1 -p $port -U postgres -d postgres -c 'SHOW data_directory'
  if ([IO.Path]::GetFullPath($actual) -ne [IO.Path]::GetFullPath($dataPath)) { throw 'Wrong database cluster; refusing tests' }
  $started = $true
  & (Join-Path $PgBin 'createdb.exe') -h 127.0.0.1 -p $port -U postgres okeyix_quick_play_test
  if ($LASTEXITCODE -ne 0) { throw 'createdb failed' }
  foreach ($relative in @('test\sql\quick_play_fixture.sql','supabase\migrations\20261022000100_quick_play.sql','supabase\migrations\20261022000200_quick_play_instant.sql','test\sql\quick_play_test.sql')) {
    & $psql -X -h 127.0.0.1 -p $port -U postgres -d okeyix_quick_play_test -v ON_ERROR_STOP=1 -f (Join-Path $workspace $relative)
    if ($LASTEXITCODE -ne 0) { throw "SQL failed: $relative" }
  }
  & $psql -X -h 127.0.0.1 -p $port -U postgres -d okeyix_quick_play_test -v ON_ERROR_STOP=1 -f (Join-Path $workspace 'test\sql\quick_play_concurrency_setup.sql')
  if ($LASTEXITCODE -ne 0) { throw 'Concurrency setup failed' }
  $jobs = @()
  foreach ($suffix in @('a','b')) {
    $file = Join-Path $workspace "test\sql\quick_play_concurrent_$suffix.sql"
    $jobs += Start-Process -FilePath $psql -ArgumentList @('-X','-h','127.0.0.1','-p',"$port",'-U','postgres','-d','okeyix_quick_play_test','-v','ON_ERROR_STOP=1','-f',"`"$file`"") -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $testRoot "$suffix.log") -RedirectStandardError (Join-Path $testRoot "$suffix-error.log")
  }
  foreach ($job in $jobs) {
    $job.WaitForExit()
    if ($null -ne $job.ExitCode -and $job.ExitCode -ne 0) { throw 'Concurrent SQL failed' }
  }
  & $psql -X -h 127.0.0.1 -p $port -U postgres -d okeyix_quick_play_test -v ON_ERROR_STOP=1 -f (Join-Path $workspace 'test\sql\quick_play_concurrency_check.sql')
  if ($LASTEXITCODE -ne 0) { throw 'Concurrency assertions failed' }
  Write-Output 'Local quick-play SQL checks passed; no remote database used.'
} finally {
  if ($started) { & $pgCtl -D $dataPath -m fast stop *> (Join-Path $testRoot 'stop.log') }
}

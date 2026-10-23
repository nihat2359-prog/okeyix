param([string]$PgBin = 'C:\Program Files\PostgreSQL\16\bin')
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $workspace ('.dart_tool\gift-catalog-' + [guid]::NewGuid().ToString('N'))
$dataPath = Join-Path $testRoot 'data'
$port = 56487
$psql = Join-Path $PgBin 'psql.exe'
$pgCtl = Join-Path $PgBin 'pg_ctl.exe'
$started = $false
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
  & (Join-Path $PgBin 'initdb.exe') -D $dataPath -U postgres -A trust --no-locale -E UTF8 *> (Join-Path $testRoot 'init.log')
  if ($LASTEXITCODE -ne 0) { throw 'initdb failed' }
  $launcher = Start-Process -FilePath $pgCtl -ArgumentList @('-D',"`"$dataPath`"",'-l',"`"$(Join-Path $testRoot 'server.log')`"",'-o',"`"-p $port -h 127.0.0.1`"",'start') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $testRoot 'start.log') -RedirectStandardError (Join-Path $testRoot 'start-error.log')
  $ready = $false
  for ($attempt=0; $attempt -lt 40; $attempt++) {
    & (Join-Path $PgBin 'pg_isready.exe') -h 127.0.0.1 -p $port -U postgres *> $null
    if ($LASTEXITCODE -eq 0) { $ready=$true; break }
    Start-Sleep -Milliseconds 250
  }
  if (!$ready) { throw 'Local PostgreSQL failed to start' }
  $actual = & $psql -X -w -At -h 127.0.0.1 -p $port -U postgres -d postgres -c 'SHOW data_directory'
  if ([IO.Path]::GetFullPath($actual) -ne [IO.Path]::GetFullPath($dataPath)) { throw 'Wrong cluster; refusing tests' }
  $started = $true
  & (Join-Path $PgBin 'createdb.exe') -h 127.0.0.1 -p $port -U postgres okeyix_gift_catalog_test
  if ($LASTEXITCODE -ne 0) { throw 'createdb failed' }
  foreach ($relative in @('test\sql\gift_catalog_fixture.sql',
    'supabase\migrations\20261023000100_table_gift_catalog_refresh.sql','test\sql\gift_catalog_assertions.sql',
    'supabase\migrations\20261023000100_table_gift_catalog_refresh.sql','test\sql\gift_catalog_assertions.sql')) {
    & $psql -X -h 127.0.0.1 -p $port -U postgres -d okeyix_gift_catalog_test -v ON_ERROR_STOP=1 -f (Join-Path $workspace $relative)
    if ($LASTEXITCODE -ne 0) { throw "SQL failed: $relative" }
  }
  Write-Output 'Local gift catalog SQL checks passed twice; no remote database used.'
} finally {
  if ($started) { & $pgCtl -D $dataPath -m fast stop *> (Join-Path $testRoot 'stop.log') }
}

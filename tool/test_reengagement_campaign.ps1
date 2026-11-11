param([string]$PgBin='C:\Program Files\PostgreSQL\16\bin')
$ErrorActionPreference='Stop'
$workspace=Split-Path -Parent $PSScriptRoot
$testRoot=Join-Path $workspace ('.dart_tool\campaign-test-'+[guid]::NewGuid().ToString('N'))
$dataPath=Join-Path $testRoot 'data'
$port=56507
$psql=Join-Path $PgBin 'psql.exe'
$pgCtl=Join-Path $PgBin 'pg_ctl.exe'
$started=$false
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
  & (Join-Path $PgBin 'initdb.exe') -D $dataPath -U postgres -A trust --no-locale -E UTF8 *> (Join-Path $testRoot 'init.log')
  if ($LASTEXITCODE -ne 0) { throw 'initdb failed' }
  $launcher=Start-Process -FilePath $pgCtl -ArgumentList @('-D',"`"$dataPath`"",'-l',"`"$(Join-Path $testRoot 'server.log')`"",'-o',"`"-p $port -h 127.0.0.1`"",'start') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $testRoot 'start.log') -RedirectStandardError (Join-Path $testRoot 'start-error.log')
  $ready=$false
  for ($attempt=0;$attempt -lt 40;$attempt++) {
    & (Join-Path $PgBin 'pg_isready.exe') -h 127.0.0.1 -p $port -U postgres *> $null
    if ($LASTEXITCODE -eq 0) { $ready=$true; break }
    Start-Sleep -Milliseconds 250
  }
  if (!$ready) { throw 'Local PostgreSQL failed to start' }
  $actual=& $psql -X -w -At -h 127.0.0.1 -p $port -U postgres -d postgres -c 'SHOW data_directory'
  if ([IO.Path]::GetFullPath($actual) -ne [IO.Path]::GetFullPath($dataPath)) { throw 'Wrong cluster; refusing tests' }
  $started=$true
  & $psql -X -h 127.0.0.1 -p $port -U postgres -d postgres -v ON_ERROR_STOP=1 -c 'CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;'
  & (Join-Path $PgBin 'createdb.exe') -h 127.0.0.1 -p $port -U postgres okeyix_reengagement_test
  foreach ($relative in @('test/sql/reengagement_fixture.sql','test/sql/reengagement_campaign_cron_fixture.sql',
    'supabase/migrations/20261028000100_reengagement_notifications.sql',
    'supabase/migrations/20261028000400_reengagement_token_delivery.sql',
    'supabase/migrations/20261030000100_reengagement_unlimited_campaign.sql',
    'test/sql/reengagement_campaign_regression.sql')) {
    & $psql -X -h 127.0.0.1 -p $port -U postgres -d okeyix_reengagement_test -v ON_ERROR_STOP=1 -f (Join-Path $workspace $relative)
    if ($LASTEXITCODE -ne 0) { throw "SQL failed: $relative" }
  }
  $env:REENGAGEMENT_CAMPAIGN_LOCAL='1'
  & node --test (Join-Path $workspace 'test/reengagement_campaign_concurrency_test.mjs')
  if ($LASTEXITCODE -ne 0) { throw 'Campaign concurrency test failed' }
  Write-Output 'Local campaign migration and regression checks passed; no remote sends.'
} finally {
  Remove-Item Env:REENGAGEMENT_CAMPAIGN_LOCAL -ErrorAction SilentlyContinue
  if ($started) { & $pgCtl -D $dataPath -m fast stop *> (Join-Path $testRoot 'stop.log') }
}

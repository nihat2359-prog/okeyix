param([Parameter(Mandatory=$true)][string]$SourceDefinitionsPath, [string]$PgBin = 'C:\Program Files\PostgreSQL\16\bin')
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $workspace ('.dart_tool\ready-tables-' + [guid]::NewGuid().ToString('N'))
$dataPath = Join-Path $testRoot 'data'
$port = 56489
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
  & (Join-Path $PgBin 'createdb.exe') -h 127.0.0.1 -p $port -U postgres okeyix_ready_tables_test
  if ($LASTEXITCODE -ne 0) { throw 'createdb failed' }
  $definitions = Get-Content -LiteralPath $SourceDefinitionsPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $sourcePath = Join-Path $testRoot 'sources.sql'
  $source = ($definitions | ForEach-Object { $_.definition + ';' }) -join "`n"
  [IO.File]::WriteAllText($sourcePath,$source,[Text.UTF8Encoding]::new($false))
  foreach ($sqlPath in @((Join-Path $workspace 'test\sql\ready_tables_fixture.sql'),
    $sourcePath,(Join-Path $workspace 'supabase\migrations\20261023000300_ready_bot_tables.sql'),
    (Join-Path $workspace 'test\sql\ready_tables_assertions.sql'))) {
    & $psql -X -h 127.0.0.1 -p $port -U postgres -d okeyix_ready_tables_test -v ON_ERROR_STOP=1 -f $sqlPath
    if ($LASTEXITCODE -ne 0) { throw "SQL failed: $sqlPath" }
  }
  $resetPath = Join-Path $testRoot 'concurrency-reset.sql'
  [IO.File]::WriteAllText($resetPath,@'
INSERT INTO okeyix_bot_wallet_private.registry SELECT u.id FROM public.users u
WHERE u.is_bot AND NOT EXISTS(SELECT 1 FROM auth.users a WHERE a.id=u.id) ON CONFLICT DO NOTHING;
DELETE FROM public.tables WHERE id IN (SELECT table_id FROM okeyix_ready_private.managed);
'@,[Text.UTF8Encoding]::new($false))
  & $psql -X -h 127.0.0.1 -p $port -U postgres -d okeyix_ready_tables_test -v ON_ERROR_STOP=1 -f $resetPath
  if ($LASTEXITCODE -ne 0) { throw 'Concurrency reset failed' }
  $parallelPath = Join-Path $testRoot 'parallel.sql'
  [IO.File]::WriteAllText($parallelPath,'BEGIN; SELECT public.run_standard_bot_table_maintainer(3,true); SELECT pg_sleep(1); COMMIT;',[Text.UTF8Encoding]::new($false))
  $workers = @()
  foreach ($index in 1..2) {
    $worker = Start-Process -FilePath $psql -ArgumentList @('-X','-h','127.0.0.1','-p',"$port",'-U','postgres','-d','okeyix_ready_tables_test','-v','ON_ERROR_STOP=1','-f',"`"$parallelPath`"") -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $testRoot "parallel-$index.log") -RedirectStandardError (Join-Path $testRoot "parallel-$index-error.log")
    $null = $worker.Handle
    $workers += $worker
  }
  foreach ($worker in $workers) { $worker.WaitForExit(); if ($worker.ExitCode -ne 0) { throw 'Parallel maintainer failed' } }
  $count = & $psql -X -At -h 127.0.0.1 -p $port -U postgres -d okeyix_ready_tables_test -c 'SELECT count(*) FROM okeyix_ready_private.managed'
  if ($count -ne '8') { throw "Concurrent maintenance over-created tables: $count" }
  Write-Output 'Local ready table and concurrent maintenance tests passed; no remote database used.'
} finally {
  if ($started) { & $pgCtl -D $dataPath -m fast stop *> (Join-Path $testRoot 'stop.log') }
}

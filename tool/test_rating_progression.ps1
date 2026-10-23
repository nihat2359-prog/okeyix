param([Parameter(Mandatory=$true)][string]$SourceDefinitionPath, [string]$PgBin = 'C:\Program Files\PostgreSQL\16\bin')
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $workspace ('.dart_tool\rating-progression-' + [guid]::NewGuid().ToString('N'))
$dataPath = Join-Path $testRoot 'data'
$port = 56488
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
  & (Join-Path $PgBin 'createdb.exe') -h 127.0.0.1 -p $port -U postgres okeyix_rating_test
  if ($LASTEXITCODE -ne 0) { throw 'createdb failed' }
  $definition = (Get-Content -LiteralPath $SourceDefinitionPath -Raw -Encoding UTF8 | ConvertFrom-Json)[0].pg_get_functiondef
  if (!$definition.Contains('okeyix_stat_private.source_game_finish(')) { throw 'Expected source_game_finish definition JSON' }
  $fixture = "CREATE SCHEMA okeyix_stat_private;`n" + $definition + ";`n" + @"

CREATE TABLE public.original_function AS SELECT oid,proowner,proacl,prosecdef,prosrc
FROM pg_proc WHERE oid='okeyix_stat_private.source_game_finish(uuid,uuid,jsonb,jsonb)'::regprocedure;
CREATE TABLE public.profiles(id uuid PRIMARY KEY,rating integer);
INSERT INTO public.profiles VALUES('00000000-0000-0000-0000-000000000001',1200);
"@
  $fixturePath = Join-Path $testRoot 'source.sql'
  [IO.File]::WriteAllText($fixturePath,$fixture,[Text.UTF8Encoding]::new($false))
  $migrationPath = Join-Path $workspace 'supabase\migrations\20261023000200_rating_progression.sql'
  $assertionsPath = Join-Path $workspace 'test\sql\rating_progression_assertions.sql'
  $migrationText = [IO.File]::ReadAllText($migrationPath).Replace("`r`n","`n")
  $crlfPath = Join-Path $testRoot 'migration-crlf.sql'
  $lfPath = Join-Path $testRoot 'migration-lf.sql'
  $resetLfPath = Join-Path $testRoot 'reset-source-lf.sql'
  [IO.File]::WriteAllText($crlfPath,$migrationText.Replace("`n","`r`n"),[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($lfPath,$migrationText,[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($resetLfPath,$definition.Replace("`r`n","`n")+";",[Text.UTF8Encoding]::new($false))
  foreach ($sqlPath in @($fixturePath,$crlfPath,$assertionsPath,$lfPath,$assertionsPath,
    $resetLfPath,$lfPath,$assertionsPath,$crlfPath,$assertionsPath)) {
    & $psql -X -h 127.0.0.1 -p $port -U postgres -d okeyix_rating_test -v ON_ERROR_STOP=1 -f $sqlPath
    if ($LASTEXITCODE -ne 0) { throw "SQL failed: $sqlPath" }
  }
  Write-Output 'Local rating checks passed for CRLF/LF source and migration, including reapplication; no remote database used.'
} finally {
  if ($started) { & $pgCtl -D $dataPath -m fast stop *> (Join-Path $testRoot 'stop.log') }
}

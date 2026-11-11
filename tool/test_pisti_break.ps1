param([string]$PgBin='C:\Program Files\PostgreSQL\16\bin')
$ErrorActionPreference='Stop'
$workspace=Split-Path -Parent $PSScriptRoot
$testRoot=Join-Path $workspace ('.dart_tool\pisti-test-'+[guid]::NewGuid().ToString('N'))
$dataPath=Join-Path $testRoot 'data'
$port=56519
$psql=Join-Path $PgBin 'psql.exe'
$pgCtl=Join-Path $PgBin 'pg_ctl.exe'
$started=$false
$priorPgOptions=$env:PGOPTIONS
$env:PGOPTIONS='-c client_min_messages=error'
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
 & (Join-Path $PgBin 'initdb.exe') -D $dataPath -U postgres -A trust --no-locale -E UTF8 *> (Join-Path $testRoot 'init.log')
 if($LASTEXITCODE -ne 0){throw 'initdb failed'}
 Start-Process -FilePath $pgCtl -ArgumentList @('-D',"`"$dataPath`"",'-l',"`"$(Join-Path $testRoot 'server.log')`"",'-o',"`"-p $port -h 127.0.0.1`"",'start') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $testRoot 'start.log') -RedirectStandardError (Join-Path $testRoot 'start-error.log') | Out-Null
 $ready=$false
 for($attempt=0;$attempt -lt 40;$attempt++){
  & (Join-Path $PgBin 'pg_isready.exe') -h 127.0.0.1 -p $port -U postgres *> $null
  if($LASTEXITCODE -eq 0){$ready=$true;break}; Start-Sleep -Milliseconds 250
 }
 if(!$ready){throw 'Local PostgreSQL failed to start'}
 $actual=& $psql -X -w -At -h 127.0.0.1 -p $port -U postgres -d postgres -c 'SHOW data_directory'
 if([IO.Path]::GetFullPath($actual) -ne [IO.Path]::GetFullPath($dataPath)){throw 'Wrong local cluster'}
 $started=$true
 & (Join-Path $PgBin 'createdb.exe') -h 127.0.0.1 -p $port -U postgres okeyix_pisti_test
 foreach($relative in @('test/sql/pisti_fixture.sql','test/sql/pisti_invitation_fixture.sql','supabase/migrations/20261030000200_pisti.sql',
  'supabase/migrations/20261030000300_pisti_social_worker.sql','supabase/migrations/20261030000400_pisti_admin.sql',
  'supabase/migrations/20261031000100_pisti_invitation_seating.sql','test/sql/pisti_invitation_flow.sql','supabase/migrations/20261031000200_pisti_break.sql','test/sql/pisti_break_flow.sql')){
  & $psql -X -h 127.0.0.1 -p $port -U postgres -d okeyix_pisti_test -v ON_ERROR_STOP=1 -f (Join-Path $workspace $relative)
  if($LASTEXITCODE -ne 0){throw "SQL failed: $relative"}
 }
}finally{
 $env:PGOPTIONS=$priorPgOptions
 Remove-Item Env:PISTI_LOCAL_TEST -ErrorAction SilentlyContinue
 if($started){& $pgCtl -D $dataPath -m fast stop *> (Join-Path $testRoot 'stop.log')}
}

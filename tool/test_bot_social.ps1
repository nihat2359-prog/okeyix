param([string]$PgBin = 'C:\Program Files\PostgreSQL\16\bin')
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $workspace ('.dart_tool\bot-social-' + [guid]::NewGuid().ToString('N'))
$socialData = Join-Path $testRoot 'data'
$port = 56489
$psql = Join-Path $PgBin 'psql.exe'
$pgCtl = Join-Path $PgBin 'pg_ctl.exe'
New-Item -ItemType Directory -Path $testRoot | Out-Null
$started = $false
try {
  & (Join-Path $PgBin 'initdb.exe') -D $socialData -U postgres -A trust --no-locale -E UTF8 *> (Join-Path $testRoot 'init.log')
  if ($LASTEXITCODE -ne 0) { throw 'initdb failed' }
  Start-Process -FilePath $pgCtl -ArgumentList @('-D',"`"$socialData`"",'-l',"`"$testRoot\server.log`"",'-o',"`"-p $port -h 127.0.0.1`"",'start') -WindowStyle Hidden -RedirectStandardOutput (Join-Path $testRoot 'start.log') -RedirectStandardError (Join-Path $testRoot 'start-error.log')
  $ready = $false
  for ($attempt=0; $attempt -lt 40; $attempt++) {
    & (Join-Path $PgBin 'pg_isready.exe') -h 127.0.0.1 -p $port -U postgres *> $null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Start-Sleep -Milliseconds 250
  }
  if (!$ready) { throw 'Local test PostgreSQL did not start' }
  $actualSocialData = & $psql -X -w -At -h 127.0.0.1 -p $port -U postgres -d postgres -c 'SHOW data_directory'
  if ($LASTEXITCODE -ne 0 -or [IO.Path]::GetFullPath($actualSocialData) -ne [IO.Path]::GetFullPath($socialData)) {
    throw 'Port belongs to another instance; refusing to run tests'
  }
  $started = $true
  foreach ($sqlFile in @(
    'test/sql/bot_social_fixture.sql',
    'supabase/migrations/20261126000300_bot_social.sql',
    'supabase/migrations/20261126000400_bot_social_conversation.sql',
    'supabase/migrations/20261126000500_bot_social_hometowns.sql',
    'supabase/migrations/20261126000600_bot_social_personas.sql',
    'supabase/migrations/20261126000700_bot_social_character_identity.sql',
    'supabase/migrations/20261126000800_bot_social_coin_intent.sql',
    'test/sql/bot_social_conversation_assertions.sql'
    'test/sql/bot_social_persona_assertions.sql'
    'test/sql/bot_social_coin_assertions.sql'
  )) {
    & $psql -X -w -h 127.0.0.1 -p $port -U postgres -d postgres -v ON_ERROR_STOP=1 -f (Join-Path $workspace $sqlFile)
    if ($LASTEXITCODE -ne 0) { throw "SQL failed: $sqlFile" }
  }
} finally {
  if ($started) { & $pgCtl -D $socialData stop -m fast }
}

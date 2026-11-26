param([string]$PgBin = 'C:\Program Files\PostgreSQL\16\bin')
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $workspace ('.dart_tool\bot-avatars-' + [guid]::NewGuid().ToString('N'))
$dataPath = Join-Path $testRoot 'data'
$port = 56494
$psql = Join-Path $PgBin 'psql.exe'
$pgCtl = Join-Path $PgBin 'pg_ctl.exe'
$utf8 = [Text.UTF8Encoding]::new($false)
New-Item -ItemType Directory -Path $testRoot | Out-Null
function Invoke-Sql([string]$sql) {
  $file = Join-Path $testRoot 'step.sql'
  [IO.File]::WriteAllText($file,$sql,$utf8)
  & $psql -X -w -h 127.0.0.1 -p $port -U postgres -d okeyix_bot_pool_test -v ON_ERROR_STOP=1 -f $file
  if ($LASTEXITCODE -ne 0) { throw 'SQL test failed' }
}
$started = $false
try {
  & (Join-Path $PgBin 'initdb.exe') -D $dataPath -U postgres -A trust --no-locale -E UTF8 *> (Join-Path $testRoot 'init.log')
  if ($LASTEXITCODE -ne 0) { throw 'initdb failed' }
  $serverLog = Join-Path $testRoot 'server.log'
  $launcher = Start-Process -FilePath $pgCtl -ArgumentList @('-D',"`"$dataPath`"",'-l',"`"$serverLog`"",'-o',"`"-p $port -h 127.0.0.1`"",'start') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $testRoot 'start.log') -RedirectStandardError (Join-Path $testRoot 'start-error.log')
  for ($attempt=0; $attempt -lt 40; $attempt++) {
    & (Join-Path $PgBin 'pg_isready.exe') -h 127.0.0.1 -p $port -U postgres *> $null
    if ($LASTEXITCODE -eq 0) { break }
    Start-Sleep -Milliseconds 250
  }
  $actual = & $psql -X -w -At -h 127.0.0.1 -p $port -U postgres -d postgres -c 'SHOW data_directory'
  if ([IO.Path]::GetFullPath($actual) -ne [IO.Path]::GetFullPath($dataPath)) { throw 'Wrong cluster; refusing tests' }
  $started = $true
  & (Join-Path $PgBin 'createdb.exe') -h 127.0.0.1 -p $port -U postgres okeyix_bot_pool_test
  if ($LASTEXITCODE -ne 0) { throw 'createdb failed' }
  & $psql -X -w -h 127.0.0.1 -p $port -U postgres -d okeyix_bot_pool_test -v ON_ERROR_STOP=1 -f (Join-Path $workspace 'test/sql/bot_pool_fixture.sql')
  if ($LASTEXITCODE -ne 0) { throw 'fixture failed' }
  $assignments = [IO.File]::ReadAllText((Join-Path $workspace 'output/bot-avatars/v1/assignments.json'))
  Invoke-Sql (@'
CREATE FUNCTION public.fixture_assert(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'ASSERT: %',label; END IF; END $$;
CREATE SCHEMA storage;
CREATE TABLE storage.buckets(id text PRIMARY KEY,public boolean);
CREATE TABLE storage.objects(id uuid DEFAULT gen_random_uuid(),bucket_id text,name text,metadata jsonb);
INSERT INTO storage.buckets VALUES('avatars',true);
CREATE TABLE public.expected_avatars AS
SELECT * FROM jsonb_to_recordset($data$
'@ + $assignments + @'
$data$::jsonb) AS p(id uuid,username text,previous_avatar text,gender text,category text,storage_path text,sha256 text,bytes integer,url text);
INSERT INTO public.users(id,username,avatar_url,is_bot)
SELECT id,username,previous_avatar,true FROM public.expected_avatars;
INSERT INTO storage.objects(bucket_id,name,metadata)
SELECT 'avatars',storage_path,jsonb_build_object('size',bytes,'mimetype','image/jpeg') FROM public.expected_avatars;
INSERT INTO auth.users VALUES('ffffffff-ffff-4000-8000-000000000001');
INSERT INTO public.users(id,username,avatar_url,is_bot)
VALUES('ffffffff-ffff-4000-8000-000000000001','Auth Account','auth-avatar',true),
('ffffffff-ffff-4000-8000-000000000002','Human Account','human-avatar',false);
CREATE TABLE public.before_avatars AS
SELECT u.id,to_jsonb(u) AS user_row,to_jsonb(p) AS profile_row FROM public.users u JOIN public.profiles p USING(id);
CREATE TABLE public.missing_object AS SELECT * FROM storage.objects LIMIT 1;
DELETE FROM storage.objects WHERE id IN(SELECT id FROM public.missing_object);
'@)
  $migration = Join-Path $workspace 'supabase/migrations/20261126000200_natural_bot_avatars.sql'
  $saved = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $missingLog = Join-Path $testRoot 'missing-upload.log'
  & $psql -X -w -h 127.0.0.1 -p $port -U postgres -d okeyix_bot_pool_test -v ON_ERROR_STOP=1 -f $migration *> $missingLog
  $missingExit = $LASTEXITCODE
  $ErrorActionPreference = $saved
  $missingText = [regex]::Replace([IO.File]::ReadAllText($missingLog),'\s','')
  if ($missingExit -eq 0 -or !$missingText.Contains('BOT_AVATARS_UPLOAD_REQUIRED')) { throw 'Missing upload guard failed' }
  Invoke-Sql "SELECT public.fixture_assert(NOT EXISTS(SELECT 1 FROM public.users u JOIN public.before_avatars b USING(id) WHERE to_jsonb(u) IS DISTINCT FROM b.user_row),'missing upload rollback'); INSERT INTO storage.objects SELECT * FROM public.missing_object;"
  for ($run=0; $run -lt 2; $run++) {
    & $psql -X -w -h 127.0.0.1 -p $port -U postgres -d okeyix_bot_pool_test -v ON_ERROR_STOP=1 -f $migration
    if ($LASTEXITCODE -ne 0) { throw 'Avatar migration failed' }
  }
  Invoke-Sql @'
SELECT public.fixture_assert((SELECT count(*)=164 AND count(DISTINCT u.avatar_url)=164 FROM public.users u JOIN public.expected_avatars e USING(id) JOIN public.profiles p USING(id) WHERE u.avatar_url=e.url AND p.avatar=e.url),'164 matching distinct avatars');
SELECT public.fixture_assert(NOT EXISTS(SELECT 1 FROM public.users u JOIN public.profiles p USING(id) JOIN public.before_avatars b USING(id) WHERE (to_jsonb(u)-'avatar_url') IS DISTINCT FROM (b.user_row-'avatar_url') OR (to_jsonb(p)-'avatar') IS DISTINCT FROM (b.profile_row-'avatar')),'all other fields preserved');
SELECT public.fixture_assert(NOT EXISTS(SELECT 1 FROM public.users u JOIN public.before_avatars b USING(id) WHERE u.id::text LIKE 'ffffffff-%' AND to_jsonb(u) IS DISTINCT FROM b.user_row),'human and Auth identities untouched');
SELECT public.fixture_assert((SELECT count(*)=164 AND bool_and(previous_users_avatar LIKE 'assets/%') FROM okeyix_bot_avatar_private.assignments),'original rollback references survive rerun');
SET ROLE authenticated;
DO $$ BEGIN
  BEGIN PERFORM 1 FROM okeyix_bot_avatar_private.assignments; RAISE EXCEPTION 'Private audit exposed';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
'@
  Write-Output 'ALL BOT AVATAR TESTS PASSED (164 unique mappings, upload guard rollback, gameplay preservation, human/Auth exclusion, private backups, rerun)'
} finally {
  if ($started) { & $pgCtl -D $dataPath stop -m fast }
}

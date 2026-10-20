param(
  [Parameter(Mandatory=$true)][string]$InventoryPath,
  [Parameter(Mandatory=$true)][string]$OutputPath
)
$ErrorActionPreference = 'Stop'
# Deliberately copy ONLY the five game function bodies under review. Other
# trigger bodies can contain production credentials and must never be exported.
$inventory = (Get-Content -LiteralPath $InventoryPath -Raw -Encoding utf8 | ConvertFrom-Json)[0].statistics_integration_inventory
$names = @('tables','table_players','users','profiles','wallet_transactions','rating_transactions',
  'recent_opponents','match_moves','table_discards','table_finish_snapshots',
  'okeyix_stat_sessions','okeyix_stat_rounds','okeyix_stat_players')
$sql = [Collections.Generic.List[string]]::new()
$sql.Add(@'
-- GENERATED LOCAL FIXTURE ONLY. Not a production schema or migration.
DO $$ BEGIN
  IF current_database() NOT LIKE 'okeyix_stat_test_%'
    OR inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet
  THEN RAISE EXCEPTION 'LOCAL_TEST_DATABASE_REQUIRED'; END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
END $$;
ALTER ROLE postgres BYPASSRLS;
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
$$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS
$$ SELECT nullif(current_setting('request.jwt.claim.role',true),'') $$;
GRANT USAGE ON SCHEMA public,auth TO anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION auth.uid(),auth.role() TO anon,authenticated,service_role;
'@)
foreach ($table in $inventory.tables | Where-Object {$_.name -in $names}) {
  if (-not $table.exists) { throw "Fixture relation missing: $($table.name)" }
  foreach ($col in $table.columns) {
    if ($col.default_or_expression -match "nextval\('([^']+)'::regclass\)") {
      $sql.Add('CREATE SEQUENCE ' + $Matches[1] + ';')
    }
  }
  $columns = foreach ($col in $table.columns) {
    $line = '"' + $col.name + '" ' + $col.type
    if ($col.generated -eq 's') { $line += ' GENERATED ALWAYS AS (' + $col.default_or_expression + ') STORED' }
    elseif ($null -ne $col.default_or_expression) { $line += ' DEFAULT ' + $col.default_or_expression }
    if ($col.not_null) { $line += ' NOT NULL' }
    $line
  }
  $sql.Add('CREATE TABLE public."' + $table.name + '" (' + ($columns -join ",`n") + ');')
}
# Source FK dependencies/auth tables are omitted intentionally. All checks,
# unique keys and all THREE permanent-statistics FKs are kept exactly.
foreach ($constraint in ($inventory.constraints_including_incoming_fks | Sort-Object @{Expression={if ($_.type -eq 'f') {1} else {0}}})) {
  $table = $constraint.table -replace '^public\.', ''
  if ($table -notin $names) { continue }
  if ($constraint.type -eq 'f' -and $table -notlike 'okeyix_stat_*') { continue }
  $sql.Add('ALTER TABLE public."' + $table + '" ADD CONSTRAINT "' + $constraint.name + '" ' + $constraint.definition + ';')
}
foreach ($index in $inventory.indexes | Where-Object {$_.table -like 'okeyix_stat_*'}) {
  # Constraint-backed indexes were already created above.
  if ($index.definition -match 'one_open_idx|one_winner_idx|history_idx') { $sql.Add($index.definition + ';') }
}
foreach ($table in $inventory.tables | Where-Object {$_.name -like 'okeyix_stat_*'}) {
  $sql.Add('ALTER TABLE public."' + $table.name + '" ENABLE ROW LEVEL SECURITY;')
}
foreach ($policy in $inventory.rls_policies | Where-Object {$_.table -like 'okeyix_stat_*'}) {
  $roles = ($policy.roles | ForEach-Object {'"' + $_ + '"'}) -join ','
  $line = 'CREATE POLICY "' + $policy.name + '" ON public."' + $policy.table + '" FOR ' + $policy.command + ' TO ' + $roles
  if ($null -ne $policy.using) { $line += ' USING (' + $policy.using + ')' }
  if ($null -ne $policy.with_check) { $line += ' WITH CHECK (' + $policy.with_check + ')' }
  $sql.Add($line + ';')
}
foreach ($name in @('start_game','game_finish','leave_table','game_timeout_move','game_discard')) {
  $function = @($inventory.functions | Where-Object {$_.schema -eq 'public' -and $_.name -eq $name})
  if ($function.Count -ne 1) { throw "Ambiguous fixture function: $name" }
  $sql.Add($function[0].definition + ';')
}
# Actual player-count trigger is important to departure/low-balance cleanup.
$playerTrigger = @($inventory.functions | Where-Object {$_.name -eq 'handle_table_player_change'})
if ($playerTrigger.Count -ne 1) { throw 'Player trigger missing' }
$sql.Add($playerTrigger[0].definition + ';')
$sql.Add(($inventory.triggers | Where-Object {$_.name -eq 'trg_table_players_change'}).definition + ';')
$sql.Add(@'
-- Deterministic solver stubs: tests exercise integration, NOT Okey rule correctness.
CREATE FUNCTION public.okey_validate_finish(jsonb) RETURNS boolean LANGUAGE sql AS
$$ SELECT coalesce(nullif(current_setting('test.finish_valid',true),'')::boolean,true) $$;
CREATE FUNCTION public._okey_is_pairs_finish(jsonb) RETURNS boolean LANGUAGE sql AS $$ SELECT true $$;
CREATE FUNCTION public.okey_invalid_pairs_tiles(jsonb) RETURNS jsonb LANGUAGE sql AS $$ SELECT '[]'::jsonb $$;
CREATE FUNCTION public.okey_invalid_finish_tiles(jsonb) RETURNS jsonb LANGUAGE sql AS $$ SELECT '[]'::jsonb $$;
CREATE FUNCTION public.okey_can_finish(jsonb) RETURNS boolean LANGUAGE sql AS $$ SELECT true $$;
CREATE FUNCTION public._tile_is_joker(jsonb) RETURNS boolean LANGUAGE sql AS
$$ SELECT coalesce(($1->>'is_joker')::boolean,false) $$;
CREATE FUNCTION public._hand_remove_first(jsonb,jsonb) RETURNS jsonb LANGUAGE sql AS
$$ SELECT coalesce(jsonb_agg(x),'[]'::jsonb) FROM jsonb_array_elements($1) x WHERE x->>'id'<>$2->>'id' $$;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon,authenticated,service_role;
'@)
[IO.File]::WriteAllText($OutputPath, ($sql -join "`n"), [Text.UTF8Encoding]::new($false))
Write-Output 'Local fixture generated; only allowlisted game definitions were copied.'

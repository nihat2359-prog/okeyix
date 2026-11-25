$ErrorActionPreference = 'Stop'
$assetRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../artifacts'))
$validation = Get-Content -LiteralPath (Join-Path $assetRoot 'validation.json') -Raw | ConvertFrom-Json
if (-not $validation.passed) { throw 'Store asset validation must pass before packaging.' }
$notes = @('UPLOAD-GUIDE.txt', 'manifest.json', 'validation.json', 'copy.json') | ForEach-Object { Join-Path $assetRoot $_ }
foreach ($store in @(@('app_store', 'App-Store'), @('google_play', 'Google-Play'))) {
  $inputs = @((Join-Path $assetRoot $store[0])) + $notes
  $destination = Join-Path $assetRoot ('OKEYIX-' + $store[1] + '-TR-EN.zip')
  Compress-Archive -LiteralPath $inputs -DestinationPath $destination -Force
  Write-Output $destination
}

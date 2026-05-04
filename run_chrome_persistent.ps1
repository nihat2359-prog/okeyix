$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$profileDir = Join-Path $projectRoot ".chrome_profile"

if (-not (Test-Path -LiteralPath $profileDir)) {
  New-Item -ItemType Directory -Path $profileDir | Out-Null
}

Set-Location -LiteralPath $projectRoot

flutter run -d chrome --web-browser-flag="--user-data-dir=$profileDir"

param([string]$Flutter = 'D:\flutter\bin\flutter.bat')
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$keyFile = Join-Path $workspace '.vscode\dev-guest.local.json'
if (!(Test-Path -LiteralPath $keyFile)) {
  throw 'Sabit test kimliği dosyası bulunamadı. Yeni anahtar üretmeyin; mevcut dev-guest.local.json dosyanızı geri yükleyin.'
}
$config = Get-Content -LiteralPath $keyFile -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($config.OKEYIX_DEV_GUEST_KEY)) {
  throw 'Yerel sabit test kimliği boş; yeni hesap açılmaması için çalıştırma durduruldu.'
}
Push-Location $workspace
try {
  & $Flutter run -d chrome --web-hostname=localhost --web-port=7357 "--dart-define-from-file=$keyFile"
  exit $LASTEXITCODE
} finally {
  Pop-Location
}

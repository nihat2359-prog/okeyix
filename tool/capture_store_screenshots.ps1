param(
  [string]$DeviceId = "",
  [string]$Platform = "android",
  [string]$OutDir = "release/screenshots/android",
  [string[]]$Shots = @(
    "01_login",
    "02_lobby",
    "03_create_table",
    "04_table_list",
    "05_in_game",
    "06_profile",
    "07_store"
  )
)

$ErrorActionPreference = "Stop"

if ($Platform -ne "android") {
  Write-Error "Bu script su an sadece android icin hazirlandi. Platform: android kullanin."
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Get-AndroidDeviceId {
  if ($DeviceId -and $DeviceId.Trim().Length -gt 0) {
    return $DeviceId.Trim()
  }

  $lines = adb devices | Select-Object -Skip 1
  $devices = @()
  foreach ($line in $lines) {
    if ($line -match "^\s*(\S+)\s+device\s*$") {
      $devices += $Matches[1]
    }
  }

  if ($devices.Count -eq 0) {
    throw "Bagli Android cihaz bulunamadi. USB debugging acik olmali."
  }

  return $devices[0]
}

$resolvedDevice = Get-AndroidDeviceId
Write-Host "Kullanilan cihaz: $resolvedDevice"
Write-Host "Cekimler: $($Shots -join ', ')"

foreach ($shot in $Shots) {
  Write-Host ""
  Write-Host "Ekrani hazirla: $shot"
  Read-Host "Hazir oldugunda Enter'a bas"

  $remote = "/sdcard/$shot.png"
  $local = Join-Path $OutDir "$shot.png"

  adb -s $resolvedDevice shell screencap -p $remote | Out-Null
  adb -s $resolvedDevice pull $remote $local | Out-Null
  adb -s $resolvedDevice shell rm $remote | Out-Null

  Write-Host "Kaydedildi: $local"
}

Write-Host ""
Write-Host "Tum ekran goruntuleri tamamlandi."

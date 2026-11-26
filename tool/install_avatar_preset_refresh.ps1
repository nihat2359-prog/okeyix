param([switch]$Repair)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$workspace = Split-Path -Parent $PSScriptRoot
$root = Join-Path $workspace 'output/avatar-presets-v2'
$plan = Get-Content -LiteralPath (Join-Path $root 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$generated = Get-Content -LiteralPath (Join-Path $root 'generated.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($generated.Count -ne 32 -or @($generated.id | Select-Object -Unique).Count -ne 32) { throw '32 unique generated presets required' }
$registry = Join-Path $workspace 'lib/ui/avatar_preset.dart'
if ((Get-FileHash -LiteralPath $registry -Algorithm SHA256).Hash.ToLowerInvariant() -ne $plan.registry_sha256) { throw 'Avatar registry changed; check compatibility first' }
$staging = Join-Path $workspace '.dart_tool/avatar-refresh/staged'
$backup = Join-Path $workspace '.dart_tool/avatar-refresh/originals'
$rollback = Join-Path $workspace '.dart_tool/avatar-refresh/rollback'
New-Item -ItemType Directory -Force -Path $staging,$backup,$rollback | Out-Null
$previous = $null
if ($Repair) { $previous = Get-Content -LiteralPath (Join-Path $root 'verification.json') -Raw -Encoding UTF8 | ConvertFrom-Json }
$staged = @()
foreach ($entry in $plan.entries) {
  $image = $generated | Where-Object id -eq $entry.id
  if (!$image) { throw "Missing preset $($entry.id)" }
  $target = Join-Path $workspace $entry.target
  $actualHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
  $previousEntry = $previous.files | Where-Object id -eq $entry.id
  if ($actualHash -ne $entry.original_sha256 -and !($Repair -and $actualHash -eq $previousEntry.sha256)) { throw "Existing preset changed: $($entry.id)" }
  $source = [Drawing.Image]::FromFile($image.path)
  $bitmap = [Drawing.Bitmap]::new(256,256,[Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $graphics = [Drawing.Graphics]::FromImage($bitmap)
  $prepared = Join-Path $staging ($entry.id + '.png')
  try {
    $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
    $edge = [Math]::Min($source.Width,$source.Height)
    $rect = [Drawing.RectangleF]::new(($source.Width-$edge)/2,($source.Height-$edge)/2,$edge,$edge)
    $graphics.DrawImage($source,[Drawing.RectangleF]::new(0,0,256,256),$rect,[Drawing.GraphicsUnit]::Pixel)
    $bitmap.Save($prepared,[Drawing.Imaging.ImageFormat]::Png)
  } finally { $graphics.Dispose(); $bitmap.Dispose(); $source.Dispose() }
  $staged += [pscustomobject]@{id=$entry.id;prepared=$prepared;target=$target;backup=(Join-Path $backup ($entry.id+'.png'));rollback=(Join-Path $rollback ($entry.id+'.png'))}
}
Push-Location $workspace
try {
  & dart (Join-Path $PSScriptRoot 'compact_avatar_preset_pngs.dart')
  if ($LASTEXITCODE -ne 0) { throw 'PNG optimization failed' }
} finally { Pop-Location }
$hashes = @($staged | ForEach-Object { Get-FileHash -LiteralPath $_.prepared -Algorithm SHA256 })
if (@($hashes.Hash | Select-Object -Unique).Count -ne 32) { throw 'Duplicate generated avatar content' }
# Back up and validate every entry before replacing any registered asset.
foreach ($item in $staged) {
  if (!(Test-Path -LiteralPath $item.backup)) { Copy-Item -LiteralPath $item.target -Destination $item.backup }
  Copy-Item -LiteralPath $item.target -Destination $item.rollback
}
try {
  foreach ($item in $staged) { Copy-Item -LiteralPath $item.prepared -Destination $item.target -Force }
} catch {
  foreach ($item in $staged) { Copy-Item -LiteralPath $item.rollback -Destination $item.target -Force }
  throw
}
foreach ($entry in $plan.untouched_bot_assets) {
  if ((Get-FileHash -LiteralPath (Join-Path $workspace $entry.target) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.sha256) { throw 'Bot asset changed unexpectedly' }
}
$files = @($staged | ForEach-Object { Get-Item -LiteralPath $_.target })
Write-Output ([pscustomobject]@{replaced=32;pixels=256;totalBytes=($files|Measure-Object Length -Sum).Sum;maximumBytes=($files|Measure-Object Length -Maximum).Maximum;registryUnchanged=$true} | ConvertTo-Json -Compress)

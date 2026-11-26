param([int]$Size = 256)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Join-Path (Split-Path -Parent $PSScriptRoot) 'output/bot-avatars/v1'
$manifest = Get-Content -LiteralPath (Join-Path $root 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$generated = Get-Content -LiteralPath (Join-Path $root 'generated.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$imageRoot = Join-Path $root 'images'
New-Item -ItemType Directory -Force -Path $imageRoot | Out-Null
$encoder = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object MimeType -eq 'image/jpeg'
foreach ($entry in $generated) {
  $account = $manifest | Where-Object id -eq $entry.id
  if (!$account) { throw 'Unknown account in generated image list' }
  $destination = Join-Path $imageRoot $account.file
  $source = [Drawing.Image]::FromFile($entry.path)
  $bitmap = New-Object Drawing.Bitmap($Size,$Size)
  $graphics = [Drawing.Graphics]::FromImage($bitmap)
  try {
    $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
    $edge = [Math]::Min($source.Width,$source.Height)
    $rect = [Drawing.RectangleF]::new(($source.Width-$edge)/2,($source.Height-$edge)/2,$edge,$edge)
    $graphics.DrawImage($source,[Drawing.RectangleF]::new(0,0,$Size,$Size),$rect,[Drawing.GraphicsUnit]::Pixel)
    foreach ($quality in @(82,75,68,60)) {
      $parameters = New-Object Drawing.Imaging.EncoderParameters(1)
      try {
        $parameters.Param[0] = New-Object Drawing.Imaging.EncoderParameter([Drawing.Imaging.Encoder]::Quality,[long]$quality)
        $bitmap.Save($destination,$encoder,$parameters)
      } finally { $parameters.Dispose() }
      if ((Get-Item -LiteralPath $destination).Length -le 30720) { break }
    }
    if ((Get-Item -LiteralPath $destination).Length -gt 30720) { throw "Image exceeds 30KB: $($entry.id)" }
  } finally { $graphics.Dispose(); $bitmap.Dispose(); $source.Dispose() }
}
$files = @(Get-ChildItem -LiteralPath $imageRoot -Filter '*.jpg')
$hashes = @($files | Get-FileHash -Algorithm SHA256)
if (@($hashes.Hash | Select-Object -Unique).Count -ne $files.Count) { throw 'Duplicate avatar image content' }
Write-Output ([pscustomobject]@{count=$files.Count; pixels=$Size; totalBytes=($files | Measure-Object Length -Sum).Sum; maximumBytes=($files | Measure-Object Length -Maximum).Maximum} | ConvertTo-Json -Compress)

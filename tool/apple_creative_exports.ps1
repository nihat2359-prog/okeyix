$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$appleRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../artifacts/apple-v2'))
$appleCreative=Join-Path $appleRoot 'creative'
$appleReview=Join-Path $appleRoot 'review'
New-Item -ItemType Directory -Path $appleCreative,$appleReview -Force | Out-Null
function New-AppleCanvas([int]$Width,[int]$Height) {
  $bitmap=New-Object Drawing.Bitmap($Width,$Height,[Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $graphics=[Drawing.Graphics]::FromImage($bitmap)
  $graphics.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $graphics.PixelOffsetMode=[Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $graphics.SmoothingMode=[Drawing.Drawing2D.SmoothingMode]::AntiAlias
  return @($bitmap,$graphics)
}
function Save-AppleReview($Bitmap,[string]$Name,[Drawing.Rectangle]$Safe) {
  $preview=New-AppleCanvas $Bitmap.Width $Bitmap.Height
  $preview[1].DrawImageUnscaled($Bitmap,0,0)
  $pen=New-Object Drawing.Pen([Drawing.Color]::FromArgb(245,80,235,200),8)
  $pen.DashStyle=[Drawing.Drawing2D.DashStyle]::Dash
  $preview[1].DrawRectangle($pen,$Safe)
  $preview[0].Save((Join-Path $appleReview $Name),[Drawing.Imaging.ImageFormat]::Png)
  $pen.Dispose();$preview[1].Dispose();$preview[0].Dispose()
}
$headerPath=Join-Path $appleRoot 'artwork-sources/header-master.png'
if(Test-Path -LiteralPath $headerPath) {
  $header=[Drawing.Image]::FromFile($headerPath)
  $canvas=New-AppleCanvas 3840 1646
  $canvas[1].DrawImage($header,0,0,3840,1646)
  $canvas[0].Save((Join-Path $appleCreative 'header-3840x1646.png'),[Drawing.Imaging.ImageFormat]::Png)
  Save-AppleReview $canvas[0] 'header-safe-area.png' (New-Object Drawing.Rectangle(1097,493,1646,661))
  $header.Dispose();$canvas[1].Dispose();$canvas[0].Dispose()
}
$background=[Drawing.Image]::FromFile((Join-Path $appleRoot 'artwork-sources/search-background.png'))
$logo=[Drawing.Image]::FromFile((Join-Path $appleRoot 'artwork-sources/okeyix-logo.png'))
$game=[Drawing.Image]::FromFile((Join-Path $appleRoot 'sources/01_Oyun_Masasi.png'))
$canvas=New-AppleCanvas 3840 2560
$canvas[1].DrawImage($background,0,0,3840,2560)
# Both exact brand artwork and unchanged original gameplay lie in Apple's safe area.
$logoHeight=[int][Math]::Round(900*$logo.Height/$logo.Width)
$canvas[1].DrawImage($logo,1470,765,900,$logoHeight)
$panelX=1210;$panelY=1080;$panelWidth=1420;$panelHeight=711
$panelBorder=New-Object Drawing.Pen([Drawing.Color]::FromArgb(239,206,126),6)
$canvas[1].DrawRectangle($panelBorder,$panelX-4,$panelY-4,$panelWidth+8,$panelHeight+8)
$canvas[1].DrawImage($game,(New-Object Drawing.Rectangle($panelX,$panelY,$panelWidth,$panelHeight)),14,724,1050,526,[Drawing.GraphicsUnit]::Pixel)
$canvas[0].Save((Join-Path $appleCreative 'search-3840x2560.png'),[Drawing.Imaging.ImageFormat]::Png)
Save-AppleReview $canvas[0] 'search-safe-area.png' (New-Object Drawing.Rectangle(836,765,2168,1030))
$small=New-AppleCanvas 1920 1280
$small[1].DrawImage($canvas[0],0,0,1920,1280)
$small[0].Save((Join-Path $appleCreative 'search-1920x1280.png'),[Drawing.Imaging.ImageFormat]::Png)
$small[1].Dispose();$small[0].Dispose();$panelBorder.Dispose();$canvas[1].Dispose();$canvas[0].Dispose()
$background.Dispose();$logo.Dispose();$game.Dispose()
Write-Output 'Apple creative exports and separate safe-area review images saved.'

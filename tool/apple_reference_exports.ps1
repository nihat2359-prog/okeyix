$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$appleRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../artifacts/apple-v2'))
$appleFormats = @(
  @('iphone-6.9',1320,2868),
  @('iphone-6.5',1284,2778),
  @('iphone-6.3',1206,2622),
  @('ipad-13',2064,2752)
)
$appleExports = @()
foreach ($appleSourceFile in (Get-ChildItem -LiteralPath (Join-Path $appleRoot 'sources') -Filter '0*.png')) {
  $appleImage = [Drawing.Bitmap]::FromFile($appleSourceFile.FullName)
  foreach ($appleFormat in $appleFormats) {
    $appleWidth=[int]$appleFormat[1]; $appleHeight=[int]$appleFormat[2]
    $appleBitmap=New-Object Drawing.Bitmap($appleWidth,$appleHeight,[Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $appleGraphics=[Drawing.Graphics]::FromImage($appleBitmap)
    $appleGraphics.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $appleGraphics.PixelOffsetMode=[Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    # Preserve the complete approved poster, including all text and real UI.
    # Only the surrounding canvas grows to fit Apple's different aspect ratios.
    $appleColor=$appleImage.GetPixel(5,5)
    $appleBounds=New-Object Drawing.Rectangle(0,0,$appleWidth,$appleHeight)
    $appleBrush=New-Object Drawing.Drawing2D.LinearGradientBrush($appleBounds,$appleColor,[Drawing.Color]::FromArgb(0,15,12),[single]90)
    $appleGraphics.FillRectangle($appleBrush,$appleBounds)
    $appleScale=[Math]::Min($appleWidth/$appleImage.Width,$appleHeight/$appleImage.Height)
    $appleDrawWidth=[int][Math]::Round($appleImage.Width*$appleScale)
    $appleDrawHeight=[int][Math]::Round($appleImage.Height*$appleScale)
    $appleX=[int][Math]::Floor(($appleWidth-$appleDrawWidth)/2)
    $appleY=[int][Math]::Floor(($appleHeight-$appleDrawHeight)/2)
    if ($appleY -gt 0) {
      # Extend only the outermost background rows, then fade outward. Text and
      # panels keep the same uniform scale; the join has no flat color seam.
      $appleGraphics.DrawImage($appleImage,([Drawing.Rectangle]::new(0,0,$appleWidth,($appleY+1))),0,0,$appleImage.Width,1,[Drawing.GraphicsUnit]::Pixel)
      $appleTopFade=New-Object Drawing.Drawing2D.LinearGradientBrush(([Drawing.Rectangle]::new(0,0,$appleWidth,($appleY+1))),[Drawing.Color]::FromArgb(110,0,16,12),[Drawing.Color]::FromArgb(0,0,16,12),[single]90)
      $appleGraphics.FillRectangle($appleTopFade,0,0,$appleWidth,$appleY+1)
      $appleTopFade.Dispose()
      $appleBottomY=$appleY+$appleDrawHeight
      $appleBottomHeight=$appleHeight-$appleBottomY
      $appleGraphics.DrawImage($appleImage,(New-Object Drawing.Rectangle(0,$appleBottomY,$appleWidth,$appleBottomHeight)),0,($appleImage.Height-1),$appleImage.Width,1,[Drawing.GraphicsUnit]::Pixel)
      $appleBottomFade=New-Object Drawing.Drawing2D.LinearGradientBrush((New-Object Drawing.Rectangle(0,$appleBottomY,$appleWidth,$appleBottomHeight)),[Drawing.Color]::FromArgb(0,0,16,12),[Drawing.Color]::FromArgb(230,0,16,12),[single]90)
      $appleGraphics.FillRectangle($appleBottomFade,0,$appleBottomY,$appleWidth,$appleBottomHeight)
      $appleBottomFade.Dispose()
    }
    $appleGraphics.DrawImage($appleImage,$appleX,$appleY,$appleDrawWidth,$appleDrawHeight)
    $appleDirectory=Join-Path $appleRoot ('screenshots/'+$appleFormat[0])
    New-Item -ItemType Directory -Path $appleDirectory -Force | Out-Null
    $appleDestination=Join-Path $appleDirectory $appleSourceFile.Name
    $appleBitmap.Save($appleDestination,[Drawing.Imaging.ImageFormat]::Png)
    $appleBrush.Dispose();$appleGraphics.Dispose();$appleBitmap.Dispose()
    $appleExports += [pscustomobject]@{path=('screenshots/'+$appleFormat[0]+'/'+$appleSourceFile.Name);width=$appleWidth;height=$appleHeight;source=$appleSourceFile.Name;sourceBounds=@($appleX,$appleY,$appleDrawWidth,$appleDrawHeight);method='uniform contain; complete original poster retained; emerald canvas extension'}
  }
  $appleImage.Dispose()
}
$appleExports | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $appleRoot 'screenshot-manifest.json') -Encoding UTF8
Write-Output ('Exported '+$appleExports.Count+' Apple screenshots from four original Android PNGs.')


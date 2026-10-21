param([string]$Source='.dart_tool/maiden_source',[string]$Output='.dart_tool/maiden_textures')
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Force $Output | Out-Null
$encoder=[System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object MimeType -eq 'image/jpeg'
foreach($file in Get-ChildItem -LiteralPath "$Source/textures" -Filter '*.png') {
  $image=[System.Drawing.Image]::FromFile($file.FullName)
  # Reserve 1K for the tower masonry; secondary surfaces use 512px maps.
  $limit=if($file.Name -match 'tower_(base|mid)_baseColor') {1024} else {512}
  $ratio=[Math]::Min([double]1,[double]$limit/[Math]::Max($image.Width,$image.Height))
  $bitmap=New-Object System.Drawing.Bitmap ([Math]::Max(1,[int]($image.Width*$ratio))),([Math]::Max(1,[int]($image.Height*$ratio)))
  $graphics=[System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $graphics.DrawImage($image,0,0,$bitmap.Width,$bitmap.Height)
  $parameters=New-Object System.Drawing.Imaging.EncoderParameters 1
  $parameters.Param[0]=New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality),([long]90)
  $target=Join-Path (Resolve-Path $Output) ($file.BaseName+'.jpg')
  $bitmap.Save($target,$encoder,$parameters)
  $parameters.Dispose();$graphics.Dispose();$bitmap.Dispose();$image.Dispose()
}

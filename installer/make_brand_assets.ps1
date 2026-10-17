<#
  Regenera los iconos y gráficos de marca a partir de brand\logo.svg y brand\logo_small.svg:
    windows\runner\resources\app_icon.ico   (256/128/64/48 con el logo completo; 32/24/16 con la versión simple)
    installer\store\logo.png                (icono para la Microsoft Store)
    installer\assets\wizard.bmp / wizard_small.bmp   (imágenes del asistente de Inno Setup)
    brand\lumora_lockup.png                 (logo + nombre, para el README)
  Necesita un Chromium sin interfaz (Helium/Chrome). Uso: .\make_brand_assets.ps1 [-Chrome <ruta a chrome.exe>]
#>
param([string]$Chrome = 'C:\Users\Administrator\AppData\Local\imput\Helium\Application\chrome.exe')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$full = Get-Content (Join-Path $root 'brand\logo.svg') -Raw
$small = Get-Content (Join-Path $root 'brand\logo_small.svg') -Raw
$tmp = Join-Path $env:TEMP ('lumora_brand_' + [guid]::NewGuid().ToString('N').Substring(0, 8)); New-Item -ItemType Directory $tmp | Out-Null

function Render([string]$html, [string]$out, [int]$w, [int]$h) {
  $ww = [Math]::Max($w, 600); $wh = [Math]::Max($h, 600)   # Chromium no hace capturas de ventanas muy pequeñas: se captura grande y se recorta
  $page = Join-Path $tmp ([guid]::NewGuid().ToString('N').Substring(0, 8) + '.html')
  Set-Content $page $html -Encoding UTF8
  $prof = Join-Path $tmp ('p_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
  $raw = Join-Path $tmp ([guid]::NewGuid().ToString('N').Substring(0, 8) + '.png')
  $url = 'file:///' + (($page -replace '\\', '/') -replace ' ', '%20')
  $p = Start-Process $Chrome -ArgumentList @('--headless=new', '--disable-gpu', '--hide-scrollbars', '--default-background-color=00000000', '--force-device-scale-factor=1',
      "--window-size=$ww,$wh", '--no-first-run', '--disable-extensions', '--virtual-time-budget=2500', "--user-data-dir=`"$prof`"", "--screenshot=`"$raw`"", "`"$url`"") -PassThru -WindowStyle Hidden
  for ($i = 0; $i -lt 100 -and -not (Test-Path $raw); $i++) { Start-Sleep -Milliseconds 200 }
  Start-Sleep -Milliseconds 600
  Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*$prof*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  if (-not (Test-Path $raw)) { throw "No se pudo renderizar $out" }
  $src = [System.Drawing.Image]::FromFile($raw)
  $dst = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($dst); $g.Clear([System.Drawing.Color]::Transparent)
  $g.DrawImage($src, (New-Object System.Drawing.Rectangle 0, 0, $w, $h), (New-Object System.Drawing.Rectangle 0, 0, $w, $h), [System.Drawing.GraphicsUnit]::Pixel)
  $g.Dispose(); $src.Dispose()
  if (Test-Path $out) { Remove-Item $out -Force }
  $dst.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $dst.Dispose()
}
# El SVG de marca está a 512 px: se renderiza grande una vez y se reduce con GDI+ (mejor calidad que renderizar a 16 px).
function Sized([string]$svg, [int]$s) { return [regex]::Replace($svg, '(<svg[^>]*?)width="512" height="512"', "`$1width=`"$s`" height=`"$s`"", 1) }
function IconPng([string]$svg, [int]$s, [string]$out) {
  $big = Join-Path $tmp ('big_' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.png')
  Render "<!doctype html><html><body style='margin:0;background:transparent'>$(Sized $svg 512)</body></html>" $big 512 512
  $src = [System.Drawing.Image]::FromFile($big)
  $dst = New-Object System.Drawing.Bitmap $s, $s, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($dst)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic; $g.SmoothingMode = 'HighQuality'; $g.PixelOffsetMode = 'HighQuality'; $g.Clear([System.Drawing.Color]::Transparent)
  $g.DrawImage($src, 0, 0, $s, $s); $g.Dispose(); $src.Dispose()
  if (Test-Path $out) { Remove-Item $out -Force }
  $dst.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $dst.Dispose()
}
# 1) iconos PNG y .ico (entradas PNG)
$sizes = @(@(256, $full), @(128, $full), @(64, $full), @(48, $full), @(32, $small), @(24, $small), @(16, $small))
$entries = @()
foreach ($e in $sizes) {
  $png = Join-Path $tmp "i$($e[0]).png"; IconPng $e[1] $e[0] $png
  $entries += , @($e[0], [IO.File]::ReadAllBytes($png))
}
$ms = New-Object IO.MemoryStream; $bw = New-Object IO.BinaryWriter $ms
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$entries.Count)
$offset = 6 + 16 * $entries.Count
foreach ($e in $entries) {
  $w = if ($e[0] -ge 256) { 0 } else { $e[0] }
  $bw.Write([byte]$w); $bw.Write([byte]$w); $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([uint16]1); $bw.Write([uint16]32)
  $bw.Write([uint32]$e[1].Length); $bw.Write([uint32]$offset); $offset += $e[1].Length
}
foreach ($e in $entries) { $bw.Write($e[1]) }
[IO.File]::WriteAllBytes((Join-Path $root 'windows\runner\resources\app_icon.ico'), $ms.ToArray())
IconPng $full 256 (Join-Path $root 'installer\store\logo.png')

# 2) imágenes del asistente de Inno Setup (BMP; el fondo se rellena porque BMP no tiene transparencia)
New-Item -ItemType Directory -Force (Join-Path $root 'installer\assets') | Out-Null
$wiz = @"
<!doctype html><html><body style="margin:0"><div style="position:relative;width:164px;height:314px;overflow:hidden;background:radial-gradient(circle at 30% 85%,#0d6b5b 0,#083a3c 38%,#04141b 80%);font-family:'Segoe UI';color:#eaf6f3">
<div style="position:absolute;left:22px;top:34px">$(Sized $full 120)</div>
<div style="position:absolute;left:0;right:0;top:170px;text-align:center;font:600 30px 'Segoe UI Variable Display','Segoe UI'">Lumora</div>
<div style="position:absolute;left:0;right:0;top:212px;text-align:center;font:600 10px 'Segoe UI';letter-spacing:4px;color:#19e3a1">IPTV PLAYER</div>
</div></body></html>
"@
$wizPng = Join-Path $tmp 'wiz.png'; Render $wiz $wizPng 164 314
$bmp = New-Object System.Drawing.Bitmap $wizPng; $bmp.Save((Join-Path $root 'installer\assets\wizard.bmp'), [System.Drawing.Imaging.ImageFormat]::Bmp); $bmp.Dispose()
$sm = "<!doctype html><html><body style='margin:0;width:55px;height:55px;background:#ffffff'>$(Sized $full 55)</body></html>"
$smPng = Join-Path $tmp 'wsm.png'; Render $sm $smPng 55 55
$bmp = New-Object System.Drawing.Bitmap $smPng; $bmp.Save((Join-Path $root 'installer\assets\wizard_small.bmp'), [System.Drawing.Imaging.ImageFormat]::Bmp); $bmp.Dispose()

# 3) logo + nombre para el README
$lock = @"
<!doctype html><html><body style="margin:0;width:680px;height:220px;background:#06121a;display:flex;align-items:center;gap:30px;padding-left:36px;box-sizing:border-box;font-family:'Segoe UI'">
$(Sized $full 170)
<div><div style="font:600 96px 'Segoe UI Variable Display','Segoe UI';color:#eaf6f3;line-height:1">Lumora</div>
<div style="font:600 20px 'Segoe UI';letter-spacing:9px;color:#19e3a1;margin-top:10px">IPTV PLAYER</div></div></body></html>
"@
Render $lock (Join-Path $root 'brand\lumora_lockup.png') 680 220
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host 'Gráficos de marca regenerados.'

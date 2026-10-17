<#
  Construye una versión para repartir a otros usuarios, de principio a fin:
  analiza, prueba, compila, genera el instalador y el latest.json firmado.

  Antes (una sola vez):
    1. .\new_signing_key.ps1                 (clave de firma de actualizaciones; ya hecho si existe installer\signing)
    2. Crea installer\update_url.txt con UNA línea: la carpeta HTTPS donde estarán latest.json y el instalador.
       Con una release de GitHub:  https://github.com/USUARIO/REPO/releases/latest/download

  Uso:   .\build_release.ps1 -Notes "Qué cambia en esta versión"
         (sube la versión en pubspec.yaml y lumora.iss antes de ejecutarlo)

  Firma de código: si hay un certificado configurado (sign.ps1), firma binarios e instalador antes de calcular el hash.

  Resultado en installer\output:  Lumora-Setup-<version>.exe  y  latest.json
  Súbelos a esa dirección (en GitHub: Releases > Draft a new release > adjunta los dos archivos > Publish).
  Las apps ya instaladas encontrarán la versión nueva solas.
#>
param(
  [string]$Notes = '',
  [switch]$SkipTests,
  [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$env:PATH = "D:\tools\flutter\bin;D:\tools\git\cmd;$env:PATH"

$urlFile = Join-Path $PSScriptRoot 'update_url.txt'
if (-not (Test-Path $urlFile)) { throw "Falta $urlFile con la dirección HTTPS de las actualizaciones (ver la cabecera de este script)." }
$url = (Get-Content $urlFile -Raw).Trim().TrimEnd('/')
if ($url -notmatch '^https://') { throw "La dirección de actualizaciones debe empezar por https:// (ahora: $url)" }

$pubspec = Get-Content (Join-Path $root 'pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*([0-9.]+)') { throw 'No se encontró la versión en pubspec.yaml' }
$version = $Matches[1]
$iss = Get-Content (Join-Path $PSScriptRoot 'lumora.iss') -Raw
if ($iss -notmatch "#define AppVersion `"$([regex]::Escape($version))`"") { throw "lumora.iss no tiene la versión $version. Súbela en los dos sitios." }
Write-Host "Versión $version  ·  actualizaciones desde $url"
if ($DryRun) { Write-Host 'DryRun: todo correcto, no se ha compilado nada.'; return }

Push-Location $root
try {
  flutter analyze; if ($LASTEXITCODE -ne 0) { throw 'flutter analyze con avisos' }
  if (-not $SkipTests) { flutter test; if ($LASTEXITCODE -ne 0) { throw 'hay tests que fallan' } }
  flutter build windows --release "--dart-define=LUMORA_UPDATE_URL=$url"; if ($LASTEXITCODE -ne 0) { throw 'falló la compilación' }
  # Firma de código (opcional, ver FIRMA.md): firma los .exe/.dll de la compilación y el instalador.
  $sign = Join-Path $PSScriptRoot 'sign.ps1'
  $signing = (& powershell -NoProfile -ExecutionPolicy Bypass -File $sign -Check) -ne 'none'
  $isccArgs = @()
  if ($signing) {
    Write-Host "Firma de código activada ($(& powershell -NoProfile -ExecutionPolicy Bypass -File $sign -Check))"
    $release = Join-Path $root 'build\windows\x64\runner\Release'
    $bins = Get-ChildItem $release -Recurse -Include *.exe,*.dll | Select-Object -ExpandProperty FullName
    & powershell -NoProfile -ExecutionPolicy Bypass -File $sign @bins; if ($LASTEXITCODE -ne 0) { throw 'falló la firma de los binarios' }
    $isccArgs = @('/DSignInstaller', "/Slumorasign=powershell -NoProfile -ExecutionPolicy Bypass -File `"$sign`" `$f")
  } else {
    Write-Warning 'Sin firma de código: Windows mostrará SmartScreen y Smart App Control puede bloquear el instalador (ver FIRMA.md).'
  }
  & 'D:\tools\InnoSetup\ISCC.exe' @isccArgs (Join-Path $PSScriptRoot 'lumora.iss'); if ($LASTEXITCODE -ne 0) { throw 'falló el instalador' }
} finally { Pop-Location }
& (Join-Path $PSScriptRoot 'publish_update.ps1') -Notes $Notes
Write-Host "`nListo. Sube a $url :`n  $(Join-Path $PSScriptRoot "output\Lumora-Setup-$version.exe")`n  $(Join-Path $PSScriptRoot 'output\latest.json')"

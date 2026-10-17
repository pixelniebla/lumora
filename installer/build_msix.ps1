<#
  Crea el paquete MSIX para la Microsoft Store: installer\output\Lumora-Store-<version>.msix (sin firmar;
  la Store lo firma al publicarlo). Ver TIENDA.md.

  Antes, una sola vez: reserva el nombre "Lumora" en Partner Center y copia sus tres valores de
  "Product identity" a installer\store\identity.json:
     { "identityName": "...", "publisher": "CN=...", "publisherDisplayName": "..." }

  Uso:  .\build_msix.ps1            (compila y empaqueta)
        .\build_msix.ps1 -NoBuild   (reutiliza build\windows\x64\runner\Release)
#>
param([switch]$NoBuild)
$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
$env:PATH = "D:\tools\flutter\bin;D:\tools\git\cmd;$env:PATH"
$release = Join-Path $root 'build\windows\x64\runner\Release'

$pubspec = Get-Content (Join-Path $root 'pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*([0-9]+)\.([0-9]+)\.([0-9]+)') { throw 'No se encontró la versión en pubspec.yaml' }
$msixVersion = "$($Matches[1]).$($Matches[2]).$($Matches[3]).0"   # la Store se reserva el cuarto número (debe ser 0)

$idFile = Join-Path $PSScriptRoot 'store\identity.json'
$extra = @()
if (Test-Path $idFile) {
  $id = Get-Content $idFile -Raw | ConvertFrom-Json
  $extra = @('--identity-name', $id.identityName, '--publisher', $id.publisher, '--publisher-display-name', $id.publisherDisplayName)
  Write-Host "Identidad de la Store: $($id.identityName)"
} else {
  Write-Warning 'Falta installer\store\identity.json: se usa una identidad de PRUEBA. La Store rechazará este paquete; sirve solo para comprobar el empaquetado.'
}

# Los archivos que genera msix (manifiesto, imágenes, .pri) no deben quedar en la carpeta que usa el instalador de Inno Setup.
function Clean-Release {
  foreach ($n in 'AppxManifest.xml', 'Images', 'priconfig.xml') { Remove-Item (Join-Path $release $n) -Recurse -Force -ErrorAction SilentlyContinue }
  Get-ChildItem $release -Filter 'resources*.pri' -ErrorAction SilentlyContinue | Remove-Item -Force
  Get-ChildItem $release -Filter '*.msix' -ErrorAction SilentlyContinue | Remove-Item -Force
}

Push-Location $root
try {
  if (-not $NoBuild) { flutter build windows --release; if ($LASTEXITCODE -ne 0) { throw 'falló la compilación' } }
  Clean-Release
  $out = Join-Path $PSScriptRoot 'output'
  $msix = Join-Path $out "Lumora-Store-$msixVersion.msix"
  Remove-Item $msix -Force -ErrorAction SilentlyContinue

  # 1) manifiesto, imágenes y recursos (el paquete msix); su makeappx interno falla en algunos equipos,
  #    así que el empaquetado final lo hace el makeappx del Windows SDK.
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'   # si su makeappx interno falla, seguimos con el del SDK
  dart run msix:create --version $msixVersion --output-path $out --output-name "Lumora-Store-$msixVersion" @extra 2>&1 | Out-Host
  $ErrorActionPreference = $prev
  if (-not (Test-Path (Join-Path $release 'AppxManifest.xml'))) { throw 'msix no generó AppxManifest.xml' }

  # 2) empaquetar con el SDK
  if (-not (Test-Path $msix)) {
    $makeappx = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Recurse -Filter makeappx.exe -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -match '\\x64\\' } | Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
    if (-not $makeappx) { throw 'No hay makeappx.exe: instala el Windows 10/11 SDK.' }
    & $makeappx pack /o /d $release /p $msix | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'makeappx falló' }
  }
  Write-Host "`nPaquete creado: $msix ($([math]::Round((Get-Item $msix).Length / 1MB, 1)) MB)"
} finally {
  Clean-Release
  Pop-Location
}

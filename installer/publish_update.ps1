<#
  Publica una actualización para el actualizador de la app.

  Escribe latest.json junto al instalador en installer\output (o -OutDir), firmado con la clave
  privada de installer\signing. La app comprueba esa carpeta, o cualquier ubicación HTTPS con
  los mismos dos archivos:
      latest.json
      Lumora-Setup-<version>.exe

  Uso:  .\publish_update.ps1 -Notes "Qué cambia en esta versión"
  (La primera vez, crea la clave con .\new_signing_key.ps1 y recompila la app.)
#>
param(
  [string]$Notes = '',
  [string]$OutDir = (Join-Path $PSScriptRoot 'output')
)
$ErrorActionPreference = 'Stop'

$pubspec = Get-Content (Join-Path $PSScriptRoot '..\pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*([0-9.]+)') { throw 'No se encontró la versión en pubspec.yaml' }
$version = $Matches[1]

$installer = Join-Path $OutDir "Lumora-Setup-$version.exe"
if (-not (Test-Path $installer)) { throw "No existe $installer. Compila primero el instalador." }

$keyFile = Join-Path $PSScriptRoot 'signing\lumora_update_private.xml'
if (-not (Test-Path $keyFile)) { throw "Falta la clave de firma ($keyFile). Ejecuta new_signing_key.ps1." }

$hash = (Get-FileHash $installer -Algorithm SHA256).Hash.ToLower()
$leaf = Split-Path $installer -Leaf

# Firma RSA-SHA256 (PKCS#1 v1.5) de "version\nurl\nsha256"; la app lo verifica antes de instalar.
$rsa = New-Object Security.Cryptography.RSACryptoServiceProvider
$rsa.PersistKeyInCsp = $false
$rsa.FromXmlString([IO.File]::ReadAllText($keyFile))
$payload = [Text.Encoding]::UTF8.GetBytes("$version`n$leaf`n$hash")
$sig = [Convert]::ToBase64String($rsa.SignData($payload, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1))

$manifest = [ordered]@{
  version = $version
  url     = $leaf
  sha256  = $hash
  notes   = $Notes
  sig     = $sig
}
$json = $manifest | ConvertTo-Json
[IO.File]::WriteAllText((Join-Path $OutDir 'latest.json'), $json, (New-Object Text.UTF8Encoding($false)))
Write-Host "Publicada la versión $version`n$json"

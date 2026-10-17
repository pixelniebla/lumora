<#
  Firma archivos (.exe / .dll / instalador) con Authenticode. Se omite sin error si no hay firma configurada,
  y FALLA si hay una configurada y la firma no sale bien (así nunca se publica un instalador "a medias").

  Configuración (variables de entorno o installer\signing\sign.json, que está en .gitignore):
    LUMORA_SIGN_MODE   pfx | store | azure          (vacío = no firmar)
    pfx   : LUMORA_PFX (ruta al .pfx), LUMORA_PFX_PASSWORD
    store : LUMORA_CERT_THUMBPRINT  (certificado ya instalado en Cert:\CurrentUser\My o LocalMachine\My,
            p. ej. un token USB / SimplySign de Certum)
    azure : LUMORA_AZURE_DLIB (Azure.CodeSigning.Dlib.dll), LUMORA_AZURE_METADATA (metadata.json)  [Azure Trusted Signing]
    LUMORA_SIGN_TIMESTAMP  servidor de sello de tiempo (por defecto http://timestamp.digicert.com; "none" = sin sello)
    LUMORA_SIGN_VERIFY     0 = no exigir que la firma sea de confianza (solo para pruebas con certificado autofirmado)

  Uso:  .\sign.ps1 archivo1 archivo2 ...        |        .\sign.ps1 -Check   (dice si hay firma configurada)
#>
param(
  [switch]$Check,
  [Parameter(ValueFromRemainingArguments = $true)] [string[]]$Files
)
$ErrorActionPreference = 'Stop'

$cfg = $null
$cfgFile = Join-Path $PSScriptRoot 'signing\sign.json'
if (Test-Path $cfgFile) { $cfg = Get-Content $cfgFile -Raw | ConvertFrom-Json }
function Setting($envName, $jsonName) {
  $v = [Environment]::GetEnvironmentVariable($envName)
  if ([string]::IsNullOrEmpty($v) -and $cfg -and $cfg.PSObject.Properties[$jsonName]) { $v = [string]$cfg.$jsonName }
  return $v
}

$mode = (Setting 'LUMORA_SIGN_MODE' 'mode')
if ($Check) { if ([string]::IsNullOrEmpty($mode)) { 'none' } else { $mode }; return }
if ([string]::IsNullOrEmpty($mode)) { Write-Host "sign.ps1: sin firma configurada, se omite ($($Files.Count) archivo/s)"; return }

$ts = Setting 'LUMORA_SIGN_TIMESTAMP' 'timestamp'
if ([string]::IsNullOrEmpty($ts)) { $ts = if ($mode -eq 'azure') { 'http://timestamp.acs.microsoft.com' } else { 'http://timestamp.digicert.com' } }
$verify = (Setting 'LUMORA_SIGN_VERIFY' 'verify') -ne '0'

# signtool del Windows SDK (el más reciente, x64)
$signtool = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -match '\\x64\\' } | Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
if ($mode -eq 'azure' -and -not $signtool) { throw 'El modo azure necesita signtool (Windows SDK).' }

function Sign-One([string]$file) {
  if (-not (Test-Path $file)) { throw "No existe $file" }
  $args = @('sign', '/fd', 'SHA256', '/d', 'Lumora', '/du', 'https://github.com/pixelniebla/lumora')
  if ($ts -ne 'none') { $args += @('/tr', $ts, '/td', 'SHA256') }
  switch ($mode) {
    'pfx' {
      $pfx = Setting 'LUMORA_PFX' 'pfx'; $pw = Setting 'LUMORA_PFX_PASSWORD' 'pfxPassword'
      if (-not $pfx -or -not (Test-Path $pfx)) { throw "Falta el .pfx (LUMORA_PFX): $pfx" }
      if ($signtool) { $args += @('/f', $pfx); if ($pw) { $args += @('/p', $pw) } }
      else {
        $sec = if ($pw) { ConvertTo-SecureString $pw -AsPlainText -Force } else { $null }
        $cert = Get-PfxCertificate -FilePath $pfx -Password $sec
        $r = Set-AuthenticodeSignature -FilePath $file -Certificate $cert -HashAlgorithm SHA256 -TimestampServer $(if ($ts -ne 'none') { $ts } else { '' })
        if (-not $r.SignerCertificate) { throw "No se pudo firmar $file : $($r.StatusMessage)" }
        return
      }
    }
    'store' {
      $thumb = Setting 'LUMORA_CERT_THUMBPRINT' 'thumbprint'
      if (-not $thumb) { throw 'Falta LUMORA_CERT_THUMBPRINT' }
      if ($signtool) { $args += @('/sha1', $thumb) }
      else {
        $cert = Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My -ErrorAction SilentlyContinue | Where-Object Thumbprint -eq $thumb | Select-Object -First 1
        if (-not $cert) { throw "No hay certificado con huella $thumb" }
        $r = Set-AuthenticodeSignature -FilePath $file -Certificate $cert -HashAlgorithm SHA256 -TimestampServer $(if ($ts -ne 'none') { $ts } else { '' })
        if (-not $r.SignerCertificate) { throw "No se pudo firmar $file : $($r.StatusMessage)" }
        return
      }
    }
    'azure' {
      $dlib = Setting 'LUMORA_AZURE_DLIB' 'azureDlib'; $meta = Setting 'LUMORA_AZURE_METADATA' 'azureMetadata'
      if (-not $dlib -or -not $meta) { throw 'Faltan LUMORA_AZURE_DLIB y LUMORA_AZURE_METADATA' }
      $args += @('/dlib', $dlib, '/dmdf', $meta)
    }
    default { throw "Modo de firma desconocido: $mode (usa pfx, store o azure)" }
  }
  & $signtool @args $file
  if ($LASTEXITCODE -ne 0) { throw "signtool falló con código $LASTEXITCODE en $file" }
}

foreach ($f in $Files) {
  Sign-One $f
  $sig = Get-AuthenticodeSignature $f
  if (-not $sig.SignerCertificate) { throw "$f no quedó firmado" }
  if ($verify -and $sig.Status -ne 'Valid') { throw "La firma de $f no es válida ($($sig.Status): $($sig.StatusMessage))" }
  Write-Host "firmado: $(Split-Path $f -Leaf)  [$($sig.SignerCertificate.Subject)]  $($sig.Status)"
}

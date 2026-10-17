# Firma de código de Lumora

Sin firma, Windows muestra SmartScreen y **Smart App Control** puede bloquear el instalador (error 4551).
La firma se hace con `installer\sign.ps1`; `build_release.ps1` la usa solo si hay un certificado configurado
(si no, compila sin firma y avisa). Si hay un certificado configurado y la firma falla, **la compilación falla**:
nunca se publica un instalador a medias.

## 1) Elegir certificado (de más a menos recomendable; comprueba precios y requisitos actuales)
| Opción | Notas |
|---|---|
| **Microsoft Store (MSIX)** | No necesita certificado propio: Microsoft firma el paquete. Ver `TIENDA.md`. |
| **Azure Trusted Signing** | Suscripción mensual de Microsoft; comprueba que admita a particulares en tu país. Modo `azure`. |
| **Certificado OV / de código abierto** (Certum, Sectigo, SSL.com…) | Verificación de identidad; algunos vienen en token USB o en la nube (SimplySign). Modo `store` (token/almacén) o `pfx`. |
| SignPath Foundation | Rechazado en 2026-10-16 por falta de reputación pública; se puede volver a pedir (`SIGNPATH_SOLICITUD.md`). |

## 2) Configurar `installer\signing\sign.json` (carpeta ignorada por git; nunca la subas)
```json
{ "mode": "pfx",   "pfx": "C:\\ruta\\lumora.pfx", "pfxPassword": "..." }
{ "mode": "store", "thumbprint": "HUELLA_DEL_CERTIFICADO" }
{ "mode": "azure", "azureDlib": "C:\\...\\Azure.CodeSigning.Dlib.dll", "azureMetadata": "C:\\...\\metadata.json" }
```
También valen variables de entorno (`LUMORA_SIGN_MODE`, `LUMORA_PFX`, `LUMORA_PFX_PASSWORD`,
`LUMORA_CERT_THUMBPRINT`, `LUMORA_AZURE_DLIB`, `LUMORA_AZURE_METADATA`, `LUMORA_SIGN_TIMESTAMP`).
Comprobar: `.\installer\sign.ps1 -Check` (muestra el modo o `none`).

## 3) Publicar una versión firmada
`.\installer\build_release.ps1 -Notes "..."` firma `Lumora.exe` y todas las DLL, firma el instalador y su
desinstalador (directiva `SignTool` de Inno Setup) y **después** calcula el hash y firma `latest.json`, de modo que el
actualizador automático verifica el instalador ya firmado. Sube a la release de GitHub el `.exe` y el `latest.json`.

## 4) Probar sin certificado real
Con un certificado autofirmado de pruebas (`New-SelfSignedCertificate -Type CodeSigningCert`), `LUMORA_SIGN_MODE=store`,
`LUMORA_CERT_THUMBPRINT=<huella>`, `LUMORA_SIGN_TIMESTAMP=none` y `LUMORA_SIGN_VERIFY=0` se comprueba que todo el
circuito funciona (esa firma **no** es de confianza). Con `LUMORA_SIGN_VERIFY` sin cambiar, una firma no válida
hace fallar el script.

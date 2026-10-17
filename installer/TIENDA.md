# Publicar Lumora en la Microsoft Store (MSIX)

Ventaja: Microsoft firma el paquete, así que desaparecen SmartScreen y el bloqueo de Smart App Control, y la Store
actualiza la app (en esa versión el actualizador propio se desactiva solo). El instalador `.exe` de GitHub sigue
existiendo para quien lo prefiera.

## Qué hace falta de tu parte (cuentas y revisión)
1. Cuenta de desarrollador en https://partner.microsoft.com/dashboard (pago único aprox. 19 $ para particulares; comprueba el precio).
2. En Partner Center: **Aplicaciones y juegos → Nuevo producto → Aplicación o juego MSIX** y reserva el nombre «Lumora»
   (si está ocupado, otro como «Lumora IPTV Player»; el nombre visible puede diferir del identificador).
3. **Product management → Product identity**: copia tres valores a `installer\store\identity.json`:
```json
{ "identityName": "Package/Identity/Name", "publisher": "Package/Identity/Publisher (CN=...)", "publisherDisplayName": "Package/Properties/PublisherDisplayName" }
```

## Crear el paquete
`.\installer\build_msix.ps1` (sube antes la versión en `pubspec.yaml` y `lumora.iss`). Genera
`installer\output\Lumora-Store-X.Y.Z.0.msix`, **sin firmar** (la Store lo firma). Sin `identity.json` crea un paquete de
prueba con identidad falsa que la Store rechazaría. La versión usa el formato X.Y.Z.0 (la Store reserva el cuarto número).

## Enviar a certificación
Partner Center → tu aplicación → **Nuevo envío**:
- **Paquetes:** sube el `.msix`.
- **Precio y disponibilidad:** gratis.
- **Propiedades:** categoría *Fotografía y vídeo* o *Entretenimiento*; URL de política de privacidad:
  `https://github.com/pixelniebla/lumora/blob/main/PRIVACY.md`; clasificación por edades: cuestionario IARC (sin contenido propio,
  sin compras, sin chat; el contenido depende de las listas del usuario: responde con honestidad).
- **Listado (es/en):** textos más abajo; capturas 1366×768 o mayores (lista de canales, reproductor, guía, multivista; usa listas de prueba sin contenido protegido).
- **Notas para certificación** (campo de texto): ver más abajo. Incluye que la app necesita la capacidad restringida
  `runFullTrust` (app de escritorio Win32/Flutter empaquetada con Desktop Bridge).

### Descripción (es)
Lumora es un reproductor de IPTV para Windows. Añade tus propias listas M3U o Xtream Codes y tu guía XMLTV y disfruta de
TV en directo, películas y series con guía de programación, favoritos, multivista de hasta 4 pantallas, grabación y
recordatorios programados, control parental con PIN y copia de seguridad cifrada. Las contraseñas se guardan en el
Administrador de credenciales de Windows. Lumora no incluye canales ni contenido: solo reproduce lo que tú configures.

### Description (en)
Lumora is an IPTV player for Windows. Add your own M3U or Xtream Codes playlists and XMLTV guide to watch live TV,
movies and series with a program guide, favorites, up to 4-screen multiview, scheduled recordings and reminders,
parental PIN control and encrypted backups. Passwords are stored in the Windows Credential Manager. Lumora includes no
channels or content: it only plays what you configure.

### Notas para certificación
"Lumora is a media player. It ships no content: the user adds their own playlists (M3U/Xtream) and guide URLs.
To test, add any publicly available test stream, e.g. an M3U with a test HLS stream, via 'Añadir lista'.
The app uses the restricted capability runFullTrust because it is a Win32 desktop (Flutter) application packaged with
the Desktop Bridge; it embeds libmpv/FFmpeg (GPL-3.0, source links in the repository README).
It uses internetClient / privateNetworkClientServer to reach the user's playlist providers (some on a LAN).
The in-app updater is disabled in the Store build. Privacy policy: https://github.com/pixelniebla/lumora/blob/main/PRIVACY.md"

## Aspectos a vigilar
- **Licencia GPL-3.0:** Lumora incluye libmpv/FFmpeg (GPLv3). La Store añade condiciones de uso a los usuarios; si Microsoft
  o un usuario lo cuestiona, la licencia obliga a ofrecer el código fuente (está en el repositorio público).
- **Política de contenido:** la revisión puede pedir más información o rechazar apps IPTV; déjales claro que no hay contenido incluido.
- **Datos locales:** la versión de la Store guarda sus datos en el contenedor del paquete (no comparte configuración con la versión del instalador).

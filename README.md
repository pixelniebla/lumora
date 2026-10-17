<p align="center"><img src="brand/lumora_lockup.png" alt="Lumora" width="560"></p>

# Lumora

Reproductor IPTV para Windows (Flutter + mpv). / IPTV player for Windows.

> **Lumora es solo un reproductor.** No incluye, no distribuye ni recomienda canales, listas ni contenido de ningún tipo. Cada usuario añade sus propias listas (M3U o Xtream Codes) a las que tenga derecho de acceso.
> *Lumora is only a player: it ships no channels, playlists or content.*

## Características
- Listas M3U y Xtream Codes (TV en vivo, películas, series), varias listas a la vez
- Guía EPG (XMLTV) con caché, rejilla de guía, favoritos, historial y «seguir viendo»
- Multivista (hasta 4 canales), mini ventana, atajos de teclado, pantalla completa
- Grabación de canales en directo (.ts) y grabaciones/recordatorios programados desde la guía
- Control parental con PIN, copia de seguridad cifrada, 4 idiomas (es, en, pt, fr)
- Las contraseñas se guardan en el Administrador de credenciales de Windows, no en archivos

## Descarga
Instalador para Windows 10/11 (64 bits): [Releases](https://github.com/pixelniebla/lumora/releases/latest).
La app se actualiza sola; cada actualización va firmada y se verifica antes de instalarse.

## Compilar
Requisitos: Flutter estable (3.47.x), Visual Studio 2022 con «Desktop development with C++», Inno Setup 6.
```
flutter pub get
flutter analyze
flutter test
flutter build windows --release
iscc installer\lumora.iss
```
Para repartir versiones: ver [`installer/DISTRIBUCION.md`](installer/DISTRIBUCION.md).

## Privacidad
Política completa: [PRIVACY.md](PRIVACY.md).
Lumora no recoge ni envía datos a ningún servidor propio ni de terceros. Solo se conecta a las direcciones que
el usuario configura (sus listas y guías) y a este repositorio de GitHub para comprobar actualizaciones.
Las credenciales de las listas permanecen en el equipo del usuario.

## Política de firma de código / Code signing policy
Free code signing provided by [SignPath.io](https://signpath.io), certificate by [SignPath Foundation](https://signpath.org).
Los ejecutables y el instalador publicados se construyen a partir de este repositorio en GitHub Actions y los firma
SignPath. Roles: autor y aprobador: @pixelniebla. Lumora no transmite información a terceros.

## Licencia
Lumora se distribuye bajo la **GNU GPL v3 o posterior** (ver [`LICENSE`](LICENSE)). El instalador incluye
**libmpv** y **FFmpeg** (binarios de GPL v3) procedentes de [media-kit/libmpv-win32-video-build](https://github.com/media-kit/libmpv-win32-video-build);
su código fuente está disponible en [mpv](https://github.com/mpv-player/mpv) y [FFmpeg](https://ffmpeg.org/download.html)
y en el repositorio de ese build. El resto de dependencias (media_kit, provider, http, etc.) son MIT/BSD, compatibles con GPL v3.

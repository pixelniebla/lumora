# Solicitud de firma gratuita a SignPath Foundation (para pegar en https://signpath.org/apply)

> Las condiciones de SignPath Foundation pueden cambiar: comprueba el formulario y su página de requisitos.
> No hay garantía de aprobación ni plazo fijo (suele tardar de días a semanas). Lo rellenas tú con tu correo.

**Project name:** Lumora
**Repository URL:** https://github.com/pixelniebla/lumora
**Homepage:** https://github.com/pixelniebla/lumora
**License:** GNU GPL v3 or later (OSI-approved)
**Download page:** https://github.com/pixelniebla/lumora/releases/latest

**Short description:**
Lumora is an IPTV player for Windows built with Flutter and mpv. It plays M3U / Xtream Codes playlists and
XMLTV guides that the user supplies. It ships no channels or content. Features: live TV, VOD, EPG grid,
multiview, scheduled recordings, parental PIN, encrypted backup, auto-update with signed manifests.

**Privacy / telemetry:** None. The app only connects to the endpoints the user configures and to GitHub to
check for updates. Credentials are stored in the Windows Credential Manager.
(La política está en el README, sección «Privacidad» y «Política de firma de código».)

**What will be signed:** `Lumora-Setup-X.Y.Z.exe` (Inno Setup installer) and `Lumora.exe`, built from the
repository by the GitHub Actions workflow `.github/workflows/build.yml` (tags `v*`).

**Build system:** GitHub Actions (windows-latest), Flutter 3.47.7, Inno Setup 6. Reproducible from source.

**Team / roles:** Author, reviewer and approver: pixelniebla (single maintainer, GitHub 2FA enabled).

**Third-party components:** libmpv and FFmpeg binaries (GPL v3) from media-kit/libmpv-win32-video-build, fetched
at build time; their sources are linked in the README. Remaining dependencies are MIT/BSD (pub.dev).

## Después de la aprobación
1. Instala la app de GitHub de SignPath y crea el proyecto `lumora` con la política de firma (release-signing).
2. En `.github/workflows/build.yml` añade el paso `signpath/github-action-submit-signing-request` tras subir el
   artefacto sin firmar, y firma `Lumora-Setup-*.exe`.
3. Regenera `latest.json` firmado (`installer\publish_update.ps1`) con el instalador ya firmado (cambia su SHA-256).

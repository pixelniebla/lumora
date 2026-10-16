# Repartir Lumora a otros usuarios

## Una sola vez
1. Crea un repositorio en GitHub (puede ser privado si las descargas las haces tú; para que las apps de otros
   se actualicen solas debe ser **público**, porque descargan sin iniciar sesión).
2. Crea `installer\update_url.txt` con una línea:
   `https://github.com/USUARIO/REPO/releases/latest/download`
3. La clave de firma ya existe en `installer\signing` (no la compartas ni la subas; haz una copia segura).

## Cada versión nueva
1. Sube la versión en `pubspec.yaml` (`version: 1.3.2+9`) y en `installer\lumora.iss` (`AppVersion`).
2. `.\installer\build_release.ps1 -Notes "Qué cambia"` — analiza, prueba, compila, crea el instalador y el
   `latest.json` firmado en `installer\output`.
3. En GitHub: Releases > Draft a new release > etiqueta `v1.3.2` > adjunta `Lumora-Setup-1.3.2.exe` y
   `latest.json` > Publish.

Las apps instaladas comprueban `…/releases/latest/download/latest.json`, verifican la firma y el hash y se
actualizan. Un usuario nuevo solo necesita el `Lumora-Setup-X.exe` (mándaselo o ponle el enlace a la release).

## Primera vez
Las versiones ya repartidas (o compiladas sin `update_url.txt`) buscan actualizaciones en la carpeta local del
desarrollador: esos usuarios deben instalar a mano **una** versión hecha con `build_release.ps1`; a partir de
ahí se actualizan solos. Windows mostrará el aviso de SmartScreen (instalador sin firma de código).

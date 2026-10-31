#!/usr/bin/env bash
# Comprobación real de bundle y firma en macOS; no comprueba dictado ni permisos TCC.
set -euo pipefail
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "La comprobación de la app requiere macOS y codesign." >&2
  exit 1
fi
APP="${1:?Indica la ruta de Dilo.app}"
PLIST="$APP/Contents/Info.plist"
read_plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST"; }
# Bash 3.2 (macOS) no aplica errexit a todos los comandos compuestos [[ ... ]].
# Las guardas de integridad deben rechazar explícitamente, no depender de set -e.
reject() { echo "Bundle rechazado: $1 ($APP)" >&2; exit 1; }
[[ "$(read_plist CFBundleIdentifier)" == "local.dictado.DictadoMac" ]] || reject CFBundleIdentifier
[[ "$(read_plist CFBundleExecutable)" == "DictadoMac" ]] || reject CFBundleExecutable
[[ "$(read_plist CFBundleDisplayName)" == "Dilo" ]] || reject CFBundleDisplayName
[[ "$(read_plist CFBundleName)" == "Dilo" ]] || reject CFBundleName
[[ "$(read_plist CFBundleIconFile)" == "Dilo.icns" ]] || reject CFBundleIconFile
[[ -x "$APP/Contents/MacOS/DictadoMac" ]] || reject ejecutable
[[ -s "$APP/Contents/Resources/Dilo.icns" ]] || reject icono
codesign --verify --deep --strict "$APP"
echo "Bundle e integridad de firma correctos: $APP"

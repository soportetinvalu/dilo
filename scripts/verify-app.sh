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
[[ "$(read_plist CFBundleIdentifier)" == "local.dictado.DictadoMac" ]]
[[ "$(read_plist CFBundleExecutable)" == "DictadoMac" ]]
[[ "$(read_plist CFBundleDisplayName)" == "Dilo" ]]
[[ "$(read_plist CFBundleName)" == "Dilo" ]]
[[ "$(read_plist CFBundleIconFile)" == "Dilo.icns" ]]
[[ -x "$APP/Contents/MacOS/DictadoMac" ]]
[[ -s "$APP/Contents/Resources/Dilo.icns" ]]
codesign --verify --deep --strict "$APP"
echo "Bundle e integridad de firma correctos: $APP"

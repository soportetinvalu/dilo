#!/usr/bin/env bash
# Compila Dictado y lo empaqueta como dist/Dictado.app (firma ad-hoc, para uso personal).
#
# Uso:
#   ./scripts/build.sh                      # compila y firma ad-hoc
#   SIGN_IDENTITY="Mi certificado" ./scripts/build.sh   # firma con un certificado propio (permisos más estables)
#   INSTALL=1 ./scripts/build.sh            # además copia la app a /Applications
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Dictado"
EXE_NAME="DictadoMac"
BUNDLE_ID="local.dictado.DictadoMac"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"   # "-" = firma ad-hoc
APP_DIR="dist/${APP_NAME}.app"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Este script solo funciona en macOS (necesita AppKit y codesign)." >&2
  exit 1
fi
if ! command -v swift >/dev/null 2>&1; then
  echo "No se encuentra 'swift'. Instala las herramientas de línea de comandos con:  xcode-select --install" >&2
  exit 1
fi

echo "==> Compilando (release). La primera vez descarga FluidAudio y tarda unos minutos…"
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)"

echo "==> Montando ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${BIN_PATH}/${EXE_NAME}" "${APP_DIR}/Contents/MacOS/${EXE_NAME}"
cp Resources/Info.plist "${APP_DIR}/Contents/Info.plist"

# Paquetes de recursos de las dependencias (si los hay).
shopt -s nullglob
for bundle in "${BIN_PATH}"/*.bundle; do
  cp -R "${bundle}" "${APP_DIR}/Contents/Resources/"
done
shopt -u nullglob

echo "==> Firmando (identidad: ${SIGN_IDENTITY})"
codesign --force --deep --sign "${SIGN_IDENTITY}" \
  --identifier "${BUNDLE_ID}" \
  --entitlements Resources/DictadoMac.entitlements \
  "${APP_DIR}"
codesign --verify --deep --strict "${APP_DIR}"

if [[ "${INSTALL:-0}" == "1" ]]; then
  echo "==> Copiando a /Applications"
  rm -rf "/Applications/${APP_NAME}.app"
  cp -R "${APP_DIR}" "/Applications/${APP_NAME}.app"
fi

echo
echo "Listo: ${APP_DIR}"
echo "Para abrirla:  ./scripts/run.sh"

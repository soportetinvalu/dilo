#!/usr/bin/env bash
# Compila Dilo sin borrar apps previas. INSTALL=1 instala en ~/Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Este script solo funciona en macOS (necesita AppKit y codesign)." >&2
  exit 1
fi
if [[ "$(uname -m)" != "arm64" ]]; then
  echo "Se necesita un Mac Apple Silicon y Terminal sin Rosetta." >&2
  exit 1
fi
if ! command -v swift >/dev/null 2>&1; then
  echo "Faltan las herramientas de Xcode. Abre Instalar herramientas.command y después vuelve a intentarlo." >&2
  exit 1
fi
SWIFT_VERSION="$(swift --version)"
if [[ ! "$SWIFT_VERSION" =~ Swift\ version\ ([0-9]+) ]] || (( ${BASH_REMATCH[1]} < 6 )); then
  echo "Se necesita Swift 6 o superior (Xcode 16+). Versión detectada: $SWIFT_VERSION" >&2
  exit 1
fi
MACOS_VERSION="$(sw_vers -productVersion)"
if (( ${MACOS_VERSION%%.*} < 14 )); then
  echo "Se necesita macOS 14 o posterior. Detectado: $MACOS_VERSION" >&2
  exit 1
fi

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
echo "==> Compilando Dilo. La primera vez descarga FluidAudio y puede tardar varios minutos…"
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)"
mkdir -p dist
STAGE="$(mktemp -d "$PWD/dist/.dilo-build.XXXXXX")"
APP_DIR="$STAGE/Dilo.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_PATH/DictadoMac" "$APP_DIR/Contents/MacOS/DictadoMac"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/Dilo.icns "$APP_DIR/Contents/Resources/Dilo.icns"

shopt -s nullglob
for bundle in "$BIN_PATH"/*.bundle; do
  cp -R "$bundle" "$APP_DIR/Contents/Resources/"
done
shopt -u nullglob

# CI entrega los pesos dentro del bundle; la compilación local sigue siendo ligera.
if [[ -n "${DILO_MODEL_DIR:-}" ]]; then
  python3 scripts/download-model.py "$DILO_MODEL_DIR" --verify-only
  cp -R "$DILO_MODEL_DIR" "$APP_DIR/Contents/Resources/ParakeetV3"
  cp Resources/parakeet-v3.lock.json "$APP_DIR/Contents/Resources/"
fi
cp -R Resources/licenses "$APP_DIR/Contents/Resources/"
cp THIRD_PARTY_NOTICES.md "$APP_DIR/Contents/Resources/"

codesign --force --deep --sign "$SIGN_IDENTITY" \
  --identifier local.dictado.DictadoMac \
  --entitlements Resources/DictadoMac.entitlements "$APP_DIR"
./scripts/verify-app.sh "$APP_DIR"

# Preservar, no borrar, cualquier compilación previa.
BACKUP=""
if [[ -e dist/Dilo.app || -L dist/Dilo.app ]]; then
  BACKUP="$(mktemp -d "$PWD/dist/Dilo-anterior.XXXXXX")/Dilo.app"
  mv dist/Dilo.app "$BACKUP"
  echo "Compilación anterior conservada en: $BACKUP"
fi
if ! mv "$APP_DIR" dist/Dilo.app; then
  if [[ -n "$BACKUP" && ! -e dist/Dilo.app && ! -L dist/Dilo.app ]]; then
    mv "$BACKUP" dist/Dilo.app
  fi
  echo "No se pudo publicar la compilación. Los archivos se conservan en dist/." >&2
  exit 1
fi

if [[ "${INSTALL:-0}" == "1" ]]; then
  ./scripts/install.sh "$PWD/dist/Dilo.app"
fi
echo "Listo: $PWD/dist/Dilo.app"

#!/usr/bin/env bash
# Instalación local, sin sudo ni borrados. La app anterior solo se mueve a un respaldo.
set -euo pipefail
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "La instalación requiere macOS." >&2
  exit 1
fi
SOURCE="${1:?Indica la ruta a Dilo.app}"
DEST_DIR="$HOME/Applications"
DEST="$DEST_DIR/Dilo.app"
VERIFY_SCRIPT="$(cd "$(dirname "$0")" && pwd)/verify-app.sh"
"$VERIFY_SCRIPT" "$SOURCE"
mkdir -p "$DEST_DIR"
# Se copia y comprueba antes de pedir cerrar la app o mover una instalación.
STAGE="$(mktemp -d "$DEST_DIR/.Dilo-nueva.XXXXXX")"
ditto "$SOURCE" "$STAGE/Dilo.app"
"$VERIFY_SCRIPT" "$STAGE/Dilo.app"

if pgrep -x -u "$(id -u)" DictadoMac >/dev/null; then
  echo "Cierra Dictado/Dilo desde su menú (Salir) y vuelve aquí. No se forzará su cierre."
  exit 1
fi
BACKUP=""
if [[ -e "$DEST" || -L "$DEST" ]]; then
  # No sustituir una aplicación distinta que casualmente se llame Dilo.
  OLD_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Contents/Info.plist")"
  if [[ "$OLD_ID" != "local.dictado.DictadoMac" ]]; then
    echo "Ya existe otra aplicación llamada Dilo. No se ha movido ni sustituido." >&2
    exit 1
  fi
  BACKUP="$(mktemp -d "$DEST_DIR/Dilo-respaldo.XXXXXX")/Dilo.app"
  mv "$DEST" "$BACKUP"
  echo "Copia anterior conservada en: $BACKUP"
fi
if ! mv "$STAGE/Dilo.app" "$DEST"; then
  if [[ -n "$BACKUP" && ! -e "$DEST" && ! -L "$DEST" ]]; then
    mv "$BACKUP" "$DEST"
  fi
  echo "No se pudo instalar. La copia preparada sigue en: $STAGE" >&2
  exit 1
fi
# Lectura y verificación del destino exacto antes de declarar éxito.
if ! "$VERIFY_SCRIPT" "$DEST"; then
  # Apartar la copia no validada sin borrarla y recuperar la anterior, si existe.
  if mv "$DEST" "$STAGE/Dilo-no-validada.app"; then
    if [[ -n "$BACKUP" ]]; then
      mv "$BACKUP" "$DEST"
      echo "Se ha recuperado la instalación anterior en: $DEST" >&2
    fi
  fi
  echo "La verificación final falló; actualización cancelada. Archivos conservados en: $STAGE" >&2
  echo "No se han borrado archivos. No abras la copia no validada." >&2
  exit 1
fi
echo "Dilo instalada y firma comprobada en: $DEST"
echo "Las preferencias y modelos no se han modificado. macOS puede pedir permisos de nuevo."

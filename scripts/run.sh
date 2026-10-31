#!/usr/bin/env bash
# Abre Dilo (la compila antes si hace falta).
#   ./scripts/run.sh          # abre dist/Dilo.app
#   ./scripts/run.sh --logs   # además muestra los registros de la app en la Terminal
set -euo pipefail

cd "$(dirname "$0")/.."

APP_DIR="dist/Dilo.app"

if [[ ! -d "${APP_DIR}" ]]; then
  ./scripts/build.sh
fi

# No interrumpir grabaciones ni cerrar procesos a la fuerza.
if pgrep -x -u "$(id -u)" DictadoMac >/dev/null; then
  echo "Cierra Dictado/Dilo desde su menú → Salir antes de abrir esta copia." >&2
  exit 1
fi

open "${APP_DIR}"
echo "Dilo abierto. Busca el icono del micrófono en la barra de menú."

if [[ "${1:-}" == "--logs" ]]; then
  echo "Mostrando registros (Ctrl+C para salir)…"
  log stream --style compact --predicate 'subsystem == "local.dictado.DictadoMac"'
fi

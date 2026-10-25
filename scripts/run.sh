#!/usr/bin/env bash
# Abre Dictado (la compila antes si hace falta).
#   ./scripts/run.sh          # abre dist/Dictado.app
#   ./scripts/run.sh --logs   # además muestra los registros de la app en la Terminal
set -euo pipefail

cd "$(dirname "$0")/.."

APP_DIR="dist/Dictado.app"

if [[ ! -d "${APP_DIR}" ]]; then
  ./scripts/build.sh
fi

# Si ya hay una copia en marcha, se cierra para abrir la nueva.
pkill -x DictadoMac 2>/dev/null || true
sleep 0.5

open "${APP_DIR}"
echo "Dictado abierto. Busca el icono del micrófono en la barra de menú."

if [[ "${1:-}" == "--logs" ]]; then
  echo "Mostrando registros (Ctrl+C para salir)…"
  log stream --style compact --predicate 'subsystem == "local.dictado.DictadoMac"'
fi

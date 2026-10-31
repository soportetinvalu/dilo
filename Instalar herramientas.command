#!/usr/bin/env bash
# Solicita el instalador oficial de Apple; no usa sudo ni instala nada en Linux.
set -euo pipefail
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Este asistente requiere macOS." >&2
  exit 1
fi
if xcode-select -p >/dev/null 2>&1; then
  echo "Ya hay herramientas instaladas. Comprueba que sean Xcode 16+ / Swift 6+:"
  swift --version
  echo "Si son antiguas, actualízalas desde Ajustes del Sistema → General → Actualización de software."
else
  xcode-select --install
  echo "Completa el instalador de Apple. Después abre Actualizar Dilo.command."
fi
read -r -p "Pulsa Intro para cerrar… " _ || true

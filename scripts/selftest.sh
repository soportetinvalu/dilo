#!/usr/bin/env bash
# Pruebas de la lógica que no depende de AppKit (teclas, prompt de pulido, lanzador de procesos).
# Funciona en macOS y en Linux con Swift instalado. No toca permisos ni red.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="$(mktemp -d)/selftest"
swiftc -O -o "${OUT}" \
  Sources/DictadoMac/HotkeyBinding.swift \
  Sources/DictadoMac/PolishPrompt.swift \
  Sources/DictadoMac/ProcessRunner.swift \
  SelfTests/main.swift
"${OUT}"

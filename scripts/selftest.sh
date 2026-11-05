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

# El controlador usa Combine/os de macOS; prueba las clases de producción, no réplicas.
if [[ "$(uname -s)" == Darwin ]]; then
  swiftc -O -parse-as-library -o "${OUT}-login" \
    Sources/DictadoMac/HotkeyBinding.swift \
    Sources/DictadoMac/PolishPrompt.swift \
    Sources/DictadoMac/ProcessRunner.swift \
    Sources/DictadoMac/CodexConnection.swift \
    Sources/DictadoMac/AppSettings.swift \
    Sources/DictadoMac/TextPolisher.swift \
    SelfTests/CodexLoginTests.swift
  "${OUT}-login" 2>&1 | tee "${OUT}-login.txt"
  python3 - "${OUT}-login.txt" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
assert 'AUTH-SYNTHETIC-PRIVATE' not in text, 'La salida del login no debe llegar a los logs'
print('Privacidad: salida sintética de autenticación ausente del log.')
PY
  python3 scripts/test-codex-login-mutation.py
fi

#!/usr/bin/env bash
# Pruebas de la lógica que no depende de AppKit (teclas, prompt de pulido, lanzador de procesos).
# Funciona en macOS y en Linux con Swift instalado. No toca permisos ni red.
set -euo pipefail
cd "$(dirname "$0")/.."

SANDBOX="$(mktemp -d)"
trap 'rm -rf -- "$SANDBOX"' EXIT
OUT="$SANDBOX/selftest"
mkdir -p "$SANDBOX/home" "$SANDBOX/tmp" "$SANDBOX/codex"
# Entorno del ejecutable sintético: ni HOME real, ni auth heredada, ni PATH del host.
run_login_test() {
  env -i HOME="$SANDBOX/home" CFFIXED_USER_HOME="$SANDBOX/home" \
    TMPDIR="$SANDBOX/tmp" CODEX_HOME="$SANDBOX/codex" PATH=/usr/bin:/bin "$@"
}
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
  run_login_test "${OUT}-login" 2>&1 | tee "${OUT}-login.txt"
  python3 - "${OUT}-login.txt" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
assert 'AUTH-SYNTHETIC-PRIVATE' not in text, 'La salida del login no debe llegar a los logs'
print('Privacidad: salida sintética de autenticación ausente del log.')
PY
  run_login_test "$(command -v python3)" scripts/test-codex-login-mutation.py

  swiftc -parse-as-library -o "${OUT}-comparison" \
    Sources/DictadoMac/LastDictationComparison.swift \
    Sources/DictadoMac/DictationComparisonWindow.swift \
    Sources/DictadoMac/DictationController.swift \
    SelfTests/DictationComparisonTests.swift
  run_login_test "${OUT}-comparison" 2>&1 | tee "${OUT}-comparison.txt"
  python3 - "${OUT}-comparison.txt" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
for marker in ['SYNTHETIC-BEFORE-731', 'SYNTHETIC-AFTER-947', 'SYNTHETIC-SECOND-583', 'SYNTHETIC-THIRD-269']:
    assert marker not in text, 'Los textos sintéticos no deben llegar al log'
print('Privacidad: textos de comparación ausentes del log del arnés.')
PY
  run_login_test "$(command -v python3)" scripts/test-comparison-mutations.py
fi

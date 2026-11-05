#!/usr/bin/env python3
"""Contraprueba nativa offline: quitar la guarda de sesión debe volver roja la suite.
Solo CLI sintético y fuentes temporales; no altera el checkout ni inicia OAuth.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="dilo-login-mutation-") as temporary:
    directory = Path(temporary)
    source = (ROOT / "Sources/DictadoMac/TextPolisher.swift").read_text()
    guard = "guard status == .notLoggedIn, let url = codexURL else {"
    assert source.count(guard) == 1
    mutant = directory / "TextPolisher.swift"
    mutant.write_text(source.replace(guard, "guard let url = codexURL else {"))
    executable = directory / "login-mutant"
    sources = [ROOT / "Sources/DictadoMac" / (name + ".swift") for name in [
        "HotkeyBinding", "PolishPrompt", "ProcessRunner", "CodexConnection", "AppSettings",
    ]]
    compile_result = subprocess.run([
        "swiftc", "-O", "-parse-as-library", "-o", str(executable),
        *map(str, sources), str(mutant), str(ROOT / "SelfTests/CodexLoginTests.swift"),
    ], capture_output=True, text=True, timeout=120)
    assert compile_result.returncode == 0, "La contraprueba debe compilar; un error de tipos no acredita la guarda"
    result = subprocess.run([str(executable)], capture_output=True, text=True, timeout=90)
    assert result.returncode == 1, "La suite aceptó un login que reemplaza sesiones"
    assert "FALLA sesión ChatGPT existente no se sustituye" in result.stdout
    assert "FALLA no hace logout ni login sobre sesión API key" in result.stdout
    assert "AUTH-SYNTHETIC-PRIVATE" not in result.stdout + result.stderr
    print("Contraprueba: mutante compilado rechazado por sustituir sesiones ChatGPT y API key; sin OAuth real.")

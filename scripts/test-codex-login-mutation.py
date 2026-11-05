#!/usr/bin/env python3
"""Contrapruebas nativas offline; ningún CLI ni cuenta reales.
Un fallo de compilación no demuestra que se detecte la regresión.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ["HotkeyBinding", "PolishPrompt", "ProcessRunner", "CodexConnection", "AppSettings", "TextPolisher"]
with tempfile.TemporaryDirectory(prefix="dilo-login-mutation-") as temporary:
    directory = Path(temporary)
    guard = "guard status == .notLoggedIn, let url = codexURL else {"
    mutations = [
        ("session", "TextPolisher", [(guard, "guard let url = codexURL else {")], [
            "FALLA sesión ChatGPT existente no se sustituye",
            "FALLA no hace logout ni login sobre sesión API key",
        ]),
        ("parent-only", "CodexConnection", [
            ("kill(-pid, SIGKILL)", "kill(pid, SIGKILL)"),
            ("kill(-child, SIGKILL)", "kill(child, SIGKILL)"),
        ], [
            "FALLA wrapper cancel no persiste sesión después de detenerlo",
            "FALLA wrapper timeout no persiste sesión después de detenerlo",
        ]),
    ]
    for name, changed, replacements, required_failures in mutations:
        source = (ROOT / "Sources/DictadoMac" / (changed + ".swift")).read_text()
        for old, new in replacements:
            assert source.count(old) == 1
            source = source.replace(old, new)
        mutant = directory / (changed + ".swift")
        mutant.write_text(source)
        executable = directory / ("login-mutant-" + name)
        sources = [mutant if item == changed else ROOT / "Sources/DictadoMac" / (item + ".swift") for item in SOURCES]
        compile_result = subprocess.run([
            "swiftc", "-O", "-parse-as-library", "-o", str(executable),
            *map(str, sources), str(ROOT / "SelfTests/CodexLoginTests.swift"),
        ], capture_output=True, text=True, timeout=120)
        assert compile_result.returncode == 0, "La contraprueba debe compilar: " + compile_result.stderr
        # Entorno nuevo y permitido; no hereda autenticación ni configuración del usuario.
        home = directory / (name + "-home")
        home.mkdir()
        tmp = directory / (name + "-tmp")
        tmp.mkdir()
        env = {"HOME": str(home), "CFFIXED_USER_HOME": str(home), "TMPDIR": str(tmp),
               "CODEX_HOME": str(home / ".codex"), "PATH": "/usr/bin:/bin"}
        result = subprocess.run([str(executable)], env=env, capture_output=True, text=True, timeout=90)
        assert result.returncode == 1, "La suite aceptó el mutante " + name
        for message in required_failures:
            assert message in result.stdout, result.stdout
        assert "ok limpieza de temporales y preferencias sintéticas" in result.stdout
        assert not list(tmp.iterdir()), "El mutante dejó temporales"
        assert "AUTH-SYNTHETIC-PRIVATE" not in result.stdout + result.stderr
        print("Contraprueba " + name + ": compiló y falló por la regresión prevista; limpieza verificada, sin OAuth real.")

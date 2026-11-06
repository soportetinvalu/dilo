#!/usr/bin/env python3
"""Contrapruebas en copias temporales; exige fallo funcional, no de compilación."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCES = [
    "Sources/DictadoMac/LastDictationComparison.swift",
    "Sources/DictadoMac/DictationComparisonWindow.swift",
    "Sources/DictadoMac/DictationController.swift",
    "SelfTests/DictationComparisonTests.swift",
]
MUTATIONS = [
    (SOURCES[2], "comparison.capture(raw: raw, finalText: finalText, step: polishStep)",
     "comparison.capture(raw: finalText, finalText: finalText, step: polishStep)",
     "conserva antes y después distintos de la misma ejecución"),
    (SOURCES[2], "comparison.clear()", "// mutant: no clear",
     "siguiente inicio borra también la vista abierta antes de grabar"),
    (SOURCES[1], "comparison.clear()", "// mutant: no clear",
     "cerrar borra el resultado y libera la ventana y su vista"),
    (SOURCES[2], "polishStep = .fallback", "polishStep = .completed",
     "fallback etiquetado sin atribuir respuesta a ChatGPT"),
]

for index, (target, old, new, expected) in enumerate(MUTATIONS):
    with tempfile.TemporaryDirectory(prefix="dilo-comparison-mutation-") as tmp:
        folder = Path(tmp)
        paths = []
        for name in SOURCES:
            text = (ROOT / name).read_text()
            if name == target:
                assert text.count(old) == 1, (target, old)
                text = text.replace(old, new)
            path = folder / Path(name).name
            path.write_text(text)
            paths.append(str(path))
        binary = str(folder / "probe")
        build = subprocess.run(["/usr/bin/swiftc", "-parse-as-library", "-o", binary, *paths],
                               capture_output=True, text=True, timeout=180)
        assert build.returncode == 0, build.stdout + build.stderr
        run = subprocess.run([binary], capture_output=True, text=True, timeout=30)
        assert run.returncode == 1 and "FALLA " + expected in run.stdout, run.stdout + run.stderr
        assert "SYNTHETIC-BEFORE-731" not in run.stdout + run.stderr
        print(f"ok contraprueba {index + 1}: fallo funcional detectado: {expected}")

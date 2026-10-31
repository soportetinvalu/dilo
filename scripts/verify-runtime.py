#!/usr/bin/env python3
"""Audita en macOS dependencias Mach-O: solo sistema o archivos dentro de la app."""
import json
from pathlib import Path
import platform
import subprocess
import sys


def check_dependency(dependency, binary, app):
    if dependency.startswith(("/System/Library/", "/usr/lib/")):
        return "sistema macOS"
    if dependency.startswith("@rpath/libswift") and dependency.endswith(".dylib"):
        return "runtime Swift del sistema (macOS 14+)"
    candidates = []
    for prefix, directory in [("@executable_path/", app / "Contents/MacOS"),
                              ("@loader_path/", binary.parent),
                              ("@rpath/", app / "Contents/Frameworks")]:
        if dependency.startswith(prefix):
            candidates.append(directory / dependency[len(prefix):])
    for candidate in candidates:
        if candidate.is_file() and candidate.resolve().is_relative_to(app.resolve()):
            return str(candidate.relative_to(app))
    raise ValueError("Dependencia externa o ausente: " + dependency + " en " + str(binary))


def main():
    if platform.system() != "Darwin":
        raise SystemExit("Esta auditoría requiere macOS y otool; no simula un resultado Apple.")
    app = Path(sys.argv[1]).resolve()
    report = []
    for binary in sorted(p for p in app.rglob("*") if p.is_file() and not p.is_symlink()):
        # No pasar los 600 MB de pesos a file/otool innecesariamente.
        if "ParakeetV3" in binary.relative_to(app).parts:
            continue
        kind = subprocess.check_output(["file", "-b", str(binary)], text=True)
        if "Mach-O" not in kind:
            continue
        output = subprocess.check_output(["otool", "-L", str(binary)], text=True)
        dependencies = [line.strip().split(" (", 1)[0] for line in output.splitlines()[1:] if line.strip()]
        report.append({"binary": str(binary.relative_to(app)), "dependencies": {
            dep: check_dependency(dep, binary, app) for dep in dependencies}})
    if not any(x["binary"] == "Contents/MacOS/DictadoMac" for x in report):
        raise ValueError("Falta el ejecutable Mach-O principal")
    print(json.dumps({"mach_o": report, "external_dependencies": 0}, indent=2))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Empaqueta solo los fuentes/recursos autorizados y verifica el ZIP generado.
Uso: python3 scripts/package-source.py /ruta/dilo-v0.1.1-fuentes.zip
No compila ni contiene una aplicación binaria. No requiere dependencias externas.
"""
from pathlib import Path
import hashlib
import json
import stat
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
TOP_FILES = [
    ".gitignore", "LICENSE", "THIRD_PARTY_NOTICES.md", "Package.swift", "README.md",
    "EMPEZAR AQUI.txt", "LEEME CHRISTIAN.md", "LEEME CHRISTIAN.txt", "VERIFICACION.md",
    "Actualizar Dilo.command", "Instalar herramientas.command", "Package.resolved",
    "BUILD_GITHUB.md", ".github/workflows/dilo-macos.yml", "LEEME-DILO-APP.txt",
    "Resources/licenses/CC-BY-4.0.txt", "Resources/licenses/FluidAudio-LICENSE",
    "Resources/licenses/NemoTextProcessing-LICENSE",
]
DIRECTORIES = {
    "Sources": {".swift"}, "SelfTests": {".swift"},
    "Resources": {".plist", ".entitlements", ".png", ".icns", ".json"},
    "Tools": {".swift"},
    "scripts": {".py", ".sh"}, "Tests": {".py", ".md", ".json"},
}

def main():
    if len(sys.argv) != 2:
        raise SystemExit("Uso: package-source.py /ruta/entrega.zip")
    output = Path(sys.argv[1]).resolve()
    if output.suffix != ".zip":
        raise SystemExit("La entrega debe tener extensión .zip")
    paths = [ROOT / name for name in TOP_FILES]
    for directory, suffixes in DIRECTORIES.items():
        for path in (ROOT / directory).rglob("*"):
            if path.is_file() and path.suffix in suffixes and not any(part.startswith(".") or part == "__pycache__" for part in path.relative_to(ROOT).parts):
                paths.append(path)
    paths = sorted(set(paths))
    if any(path.is_symlink() for path in paths):
        raise SystemExit("No se empaquetan enlaces simbólicos.")
    contents = {str(path.relative_to(ROOT)): path.read_bytes() for path in paths}
    hashes = {name: hashlib.sha256(data).hexdigest() for name, data in contents.items()}
    manifest = json.dumps({"tipo": "fuentes, no binario macOS", "sha256": hashes}, indent=2, ensure_ascii=False).encode()
    output.parent.mkdir(parents=True, exist_ok=True)
    # Modo exclusivo: no pisa entregas anteriores.
    with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in paths:
            archive.write(path, "Dilo/" + str(path.relative_to(ROOT)))
        archive.writestr("Dilo/CONTENIDO-SHA256.json", manifest)
    with zipfile.ZipFile(output) as archive:
        assert archive.testzip() is None, "CRC de ZIP incorrecto"
        names = archive.namelist()
        assert len(names) == len(set(names)) == len(contents) + 1
        assert all(name.startswith("Dilo/") and ".." not in Path(name).parts for name in names)
        assert archive.read("Dilo/CONTENIDO-SHA256.json") == manifest
        for name, data in contents.items():
            assert archive.read("Dilo/" + name) == data, name
            assert hashlib.sha256(archive.read("Dilo/"+name)).hexdigest() == hashes[name], name
        for name in ["Actualizar Dilo.command", "Instalar herramientas.command", "scripts/build.sh", "scripts/install.sh", "scripts/verify-app.sh", "scripts/run.sh"]:
            mode = archive.getinfo("Dilo/"+name).external_attr >> 16
            assert mode & stat.S_IXUSR, name + " no es ejecutable"
        assert not any(".app/" in name or "/.git/" in name or "/.build/" in name or name.endswith(".env") for name in names)
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    checksum_path = output.with_suffix(output.suffix + ".sha256")
    with checksum_path.open("x") as checksum:
        checksum.write(digest + "  " + output.name + "\n")
    print(json.dumps({
        "archivo": str(output), "bytes": output.stat().st_size,
        "archivos_fuente_y_recursos": len(contents), "entradas_zip": len(names),
        "sha256": digest, "checksum": str(checksum_path),
        "crc_zip": "correcto", "bytes_y_hashes": "todos coinciden con el checkout",
        "asistentes_ejecutables": True, "binario_macos_incluido": False,
    }, indent=2, ensure_ascii=False))

if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Genera el icono de Dilo sin rediseñar ni recortar la imagen original.
Solo para regenerar recursos: requiere Pillow. El Mac no necesita Python.
"""
from io import BytesIO
from pathlib import Path
import struct
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
# Nombre iconset, píxeles reales, tipo ICNS (incluidos tamaños Retina).
SIZES = [
    ("icon_16x16.png", 16, b"icp4"),
    ("icon_16x16@2x.png", 32, b"ic11"),
    ("icon_32x32.png", 32, b"icp5"),
    ("icon_32x32@2x.png", 64, b"ic12"),
    ("icon_128x128.png", 128, b"ic07"),
    ("icon_128x128@2x.png", 256, b"ic13"),
    ("icon_256x256.png", 256, b"ic08"),
    ("icon_256x256@2x.png", 512, b"ic14"),
    ("icon_512x512.png", 512, b"ic09"),
    ("icon_512x512@2x.png", 1024, b"ic10"),
]

def generate():
    original = Image.open(ROOT / "Resources/Dilo-original.png")
    if original.width != original.height:
        raise ValueError("La imagen debe ser cuadrada; no se recorta automáticamente.")
    iconset = ROOT / "Resources/Dilo.iconset"
    iconset.mkdir(exist_ok=True)
    chunks = []
    for name, size, kind in SIZES:
        output = BytesIO()
        original.resize((size, size), Image.Resampling.LANCZOS).save(output, format="PNG")
        data = output.getvalue()
        (iconset / name).write_bytes(data)
        chunks.append(kind + struct.pack(">I", len(data) + 8) + data)
    payload = b"".join(chunks)
    (ROOT / "Resources/Dilo.icns").write_bytes(b"icns" + struct.pack(">I", len(payload) + 8) + payload)
    print("Icono ICNS e iconset generados a partir de Dilo-original.png.")

if __name__ == "__main__":
    generate()

#!/usr/bin/env python3
"""Compara únicamente las tres fixtures públicas versionadas; nunca audio del usuario."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import unicodedata

ROOT = Path(__file__).resolve().parents[1]


def words(text):
    # Ignora puntuación y caja, conserva tildes y palabras (incluidas repeticiones).
    return re.findall(r"\w+", unicodedata.normalize("NFC", text).lower())


def distance(reference, hypothesis):
    row = list(range(len(hypothesis) + 1))
    for i, expected in enumerate(reference, 1):
        new = [i]
        for j, actual in enumerate(hypothesis, 1):
            new.append(min(new[-1] + 1, row[j] + 1, row[j-1] + (expected != actual)))
        row = new
    return row[-1]


def verified_fixtures():
    manifest = ROOT / "Tests/Fixtures/spanish-public.json"
    data = json.loads(manifest.read_text())
    if data["dataset"] != "PolyAI/minds14" or data["license"] != "CC-BY-4.0" or len(data["samples"]) != 3:
        raise ValueError("Solo se permiten las tres fixtures públicas autorizadas")
    for entry in data["samples"]:
        path = manifest.parent / entry["path"]
        if path.parent != manifest.parent or path.is_symlink():
            raise ValueError("Ruta de fixture no permitida")
        raw = path.read_bytes()
        if len(raw) != entry["size"] or hashlib.sha256(raw).hexdigest() != entry["sha256"]:
            raise ValueError("Fixture pública corrupta: " + entry["path"])
    return manifest, data


def score(fixtures, transcripts):
    if [x["path"] for x in transcripts] != [x["path"] for x in fixtures]:
        raise ValueError("Faltan resultados o el orden no coincide con las fixtures")
    samples = []
    for fixture, result in zip(fixtures, transcripts):
        reference, hypothesis = words(fixture["reference"]), words(result["text"])
        if not reference or not hypothesis:
            raise ValueError("Referencia o transcripción vacía")
        errors = distance(reference, hypothesis)
        samples.append(dict(path=fixture["path"], reference=fixture["reference"], text=result["text"],
                            reference_words=len(reference), word_errors=errors, wer=errors / len(reference)))
    total = sum(x["reference_words"] for x in samples)
    errors = sum(x["word_errors"] for x in samples)
    return dict(samples=samples, reference_words=total, word_errors=errors, wer=errors / total)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("helper", type=Path)
    parser.add_argument("original_model", type=Path)
    parser.add_argument("work", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    manifest, fixtures = verified_fixtures()
    args.work.mkdir(parents=True, exist_ok=False)
    comparison = args.work / "ParakeetV2"
    comparison.mkdir()
    # Solo la comparación conserva v2, fuera de la app y sin modificar sus pesos.
    for path in args.original_model.iterdir():
        if not path.name.startswith("Encoder"):
            (comparison / path.name).symlink_to(path.resolve(), target_is_directory=path.is_dir())
    spec = importlib.util.spec_from_file_location("download", ROOT / "scripts/download-model.py")
    download = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(download)
    lock = json.loads((ROOT / "Tests/encoder-v2-comparison.lock.json").read_text())
    for entry in lock["files"]:
        download.fetch_entry(comparison, lock, entry)
    results = {}
    for variant, model in [("int8", args.original_model), ("int8V2", comparison)]:
        home = args.work / (variant + "-home")
        home.mkdir()
        output = args.work / (variant + ".json")
        subprocess.run([str(args.helper.resolve()), "--public-fixtures", str(model.resolve()), variant,
                        str(manifest), str(output.resolve()), "confirm-public"],
                       env=dict(os.environ, HOME=str(home.resolve())), check=True)
        results[variant] = score(fixtures["samples"], json.loads(output.read_text()))
    report = dict(dataset=fixtures["dataset"], revision=fixtures["revision"], samples=3,
                  normalization="NFC, minúsculas, palabras Unicode sin puntuación; conserva tildes",
                  polish=False, results=results,
                  limits="Tres grabaciones públicas de telefonía; referencias originales con posibles errores. No demuestra precisión general ni reproduce el micrófono del usuario.")
    args.output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({k: {f: v[f] for f in ["reference_words", "word_errors", "wer"]} for k, v in results.items()}, indent=2))
    # Guarda amplia contra modelos que cargan pero no reconocen; no exige superioridad.
    if results["int8"]["wer"] > 0.65:
        raise ValueError("El encoder restaurado no supera la guarda básica de voz pública (WER > 0.65)")


if __name__ == "__main__":
    main()

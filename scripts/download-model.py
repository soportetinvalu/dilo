#!/usr/bin/env python3
"""Descarga pública fijada por revisión y hashes; --verify-only nunca usa red."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path, PurePosixPath
import time
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def verify(path, entry):
    if not path.is_file() or path.is_symlink() or path.stat().st_size != entry["size"]:
        return False
    sha = hashlib.sha256()
    blob = hashlib.sha1(("blob " + str(entry["size"]) + "\0").encode())
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            sha.update(chunk)
            blob.update(chunk)
    return sha.hexdigest() == entry["sha256"] if "sha256" in entry else blob.hexdigest() == entry["git_blob_sha1"]


def fetch_entry(directory, lock, entry, verify_only=False):
    name = PurePosixPath(entry["path"])
    if name.is_absolute() or ".." in name.parts or "\\" in str(name):
        raise ValueError("Ruta insegura en lock")
    path = directory.joinpath(*name.parts)
    if not path.resolve().is_relative_to(directory.resolve()):
        raise ValueError("Ruta fuera del destino")
    if verify(path, entry):
        return
    if verify_only:
        raise ValueError("Modelo ausente o corrupto: " + str(name))
    path.parent.mkdir(parents=True, exist_ok=True)
    url = "https://huggingface.co/" + lock["repo"] + "/resolve/" + lock["revision"] + "/" + urllib.parse.quote(str(name))
    part = path.with_name(path.name + ".part")
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=180) as response, part.open("wb") as output:
                for chunk in iter(lambda: response.read(1024 * 1024), b""):
                    output.write(chunk)
            if not verify(part, entry):
                raise ValueError("Hash o tamaño incorrecto: " + str(name))
            part.replace(path)
            return
        except Exception:
            if attempt == 2:
                raise
            time.sleep(2 ** attempt)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    lock = json.loads((ROOT / "Resources/parakeet-v3.lock.json").read_text())
    if not args.verify_only:
        args.directory.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(lambda entry: fetch_entry(args.directory, lock, entry, args.verify_only), lock["files"]))
    print(json.dumps({"repo": lock["repo"], "revision": lock["revision"],
                      "files_verified": len(lock["files"]), "bytes_verified": sum(x["size"] for x in lock["files"]),
                      "network_disabled": args.verify_only}, indent=2))


if __name__ == "__main__":
    main()

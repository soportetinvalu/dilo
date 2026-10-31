#!/usr/bin/env python3
"""Pruebas locales del empaquetado CI; los dobles no acreditan ejecución en Mac."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


class ModelIntegrity(unittest.TestCase):
    def test_app_and_smoke_select_the_packaged_encoder_variant(self):
        lock = json.loads((ROOT / "Resources/parakeet-v3.lock.json").read_text())
        self.assertIn("Encoder.mlmodelc", {x["path"].split("/")[0] for x in lock["files"]})
        for source in ["Sources/DictadoMac/BundledParakeet.swift",
                       "Tools/DiloModelCheck/DiloModelCheck.swift"]:
            self.assertRegex((ROOT / source).read_text(), r"encoderPrecision: \.int8[,)\s]")

    def test_obsolete_encoder_is_rejected_without_deleting_it(self):
        download = module("component_guard", "scripts/download-model.py")
        lock = json.loads((ROOT / "Resources/parakeet-v3.lock.json").read_text())
        with tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR", str(ROOT / "Tests"))) as tmp:
            directory = Path(tmp)
            (directory / "Encoder.mlmodelc").mkdir()
            download.validate_components(directory, lock)
            (directory / "Encoder_v2.mlmodelc").mkdir()
            with self.assertRaisesRegex(ValueError, "Encoder_v2"):
                download.validate_components(directory, lock)
            self.assertTrue((directory / "Encoder_v2.mlmodelc").is_dir())

    def test_public_fixtures_and_wer_are_real_and_discriminate_errors(self):
        compare = module("speech_comparison", "scripts/compare-public-speech.py")
        _, fixture = compare.verified_fixtures()
        source_package = module("source_with_public_audio", "scripts/package-source.py")
        for entry in fixture["samples"]:
            self.assertIn("Tests/Fixtures/" + entry["path"], source_package.TOP_FILES)
        self.assertNotIn(".wav", source_package.DIRECTORIES["Tests"])
        exact = [dict(path=x["path"], text=x["reference"]) for x in fixture["samples"]]
        self.assertEqual(compare.score(fixture["samples"], exact)["wer"], 0)
        broken = [dict(path=x["path"], text="palabra equivocada") for x in fixture["samples"]]
        self.assertGreater(compare.score(fixture["samples"], broken)["wer"], 0.65)
        with self.assertRaises(ValueError):
            compare.score(fixture["samples"], exact[:-1])
        self.assertEqual(compare.distance(["a", "b", "c"], ["a", "d", "c", "e"]), 2)
        self.assertNotEqual(compare.words("sí"), compare.words("si"))

    def test_verified_bytes_and_corruption_are_distinguished(self):
        download = module("dilo_download", "scripts/download-model.py")
        with tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR", str(ROOT / "Tests"))) as tmp:
            path = Path(tmp) / "model.bin"
            data = b"contenido de prueba; no es Core ML"
            path.write_bytes(data)
            entry = {"size": len(data), "sha256": hashlib.sha256(data).hexdigest()}
            self.assertTrue(download.verify(path, entry))
            path.write_bytes(b"X" * len(data))
            self.assertFalse(download.verify(path, entry))
            path.unlink()
            self.assertFalse(download.verify(path, entry))

    def test_git_blob_hash_and_traversal(self):
        download = module("dilo_download2", "scripts/download-model.py")
        with tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR", str(ROOT / "Tests"))) as tmp:
            path = Path(tmp) / "vocab.json"
            data = b"{}"
            path.write_bytes(data)
            entry = {"path": "vocab.json", "size": 2,
                     "git_blob_sha1": hashlib.sha1(b"blob 2\0" + data).hexdigest()}
            self.assertTrue(download.verify(path, entry))
            download.fetch_entry(Path(tmp), {}, entry, verify_only=True)
            path.write_bytes(b"[]")
            with self.assertRaises(ValueError):
                download.fetch_entry(Path(tmp), {}, entry, verify_only=True)
            for name in ["../escape", "/absolute", "bad\\path"]:
                with self.assertRaises(ValueError):
                    download.fetch_entry(Path(tmp), {}, dict(entry, path=name), verify_only=True)

    def test_lock_has_all_v3_int8_components_and_fixed_revision(self):
        lock = json.loads((ROOT / "Resources/parakeet-v3.lock.json").read_text())
        self.assertRegex(lock["revision"], r"^[a-f0-9]{40}$")
        names = {x["path"].split("/")[0] for x in lock["files"]}
        self.assertEqual(names, {"Encoder.mlmodelc", "Decoder.mlmodelc",
                                 "JointDecisionv3.mlmodelc", "Preprocessor.mlmodelc",
                                 "parakeet_vocab.json", "README.md"})
        self.assertEqual(len(lock["files"]), len({x["path"] for x in lock["files"]}))
        for entry in lock["files"]:
            self.assertGreater(entry["size"], 0)
            self.assertTrue("sha256" in entry or "git_blob_sha1" in entry)


class RuntimePolicy(unittest.TestCase):
    def test_system_and_bundled_allowed_but_external_missing_rejected(self):
        audit = module("dilo_audit", "scripts/verify-runtime.py")
        with tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR", str(ROOT / "Tests"))) as tmp:
            app = Path(tmp) / "Dilo.app"
            binary = app / "Contents/MacOS/DictadoMac"
            library = app / "Contents/Frameworks/local.dylib"
            library.parent.mkdir(parents=True)
            library.write_bytes(b"doble de prueba, no Mach-O")
            self.assertEqual(audit.check_dependency("/usr/lib/libSystem.B.dylib", binary, app), "sistema macOS")
            self.assertEqual(audit.check_dependency("@rpath/local.dylib", binary, app), "Contents/Frameworks/local.dylib")
            for dep in ["@rpath/missing.dylib", "/opt/homebrew/lib/leak.dylib", "/Users/runner/work/.build/lib.dylib"]:
                with self.assertRaises(ValueError):
                    audit.check_dependency(dep, binary, app)


if __name__ == "__main__":
    unittest.main(verbosity=2)

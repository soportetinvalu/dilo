#!/usr/bin/env python3
"""Validación Linux de recursos y scripts. NO simula una prueba de macOS.
Pillow se usa solo en las pruebas del icono. Herramientas Apple se sustituyen
explícitamente en las pruebas de fallos de instalación/empaquetado.
"""
from pathlib import Path
from io import BytesIO
import hashlib
import importlib.util
import json
import os
import plistlib
import shutil
import struct
import subprocess
import tempfile
import unittest
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ORIGINAL_SHA = "859b57d5872d081706f3b2a44e444771b184f4533db59366d9f4777007ab23af"

# Solo dos literales de ayuda pueden diferir de la base en SettingsView.
# No se enmascaran bloques Swift ni se actualizan los hashes de la base.
SETTINGS_COPY_CHANGES = {
    'La tecla todavía no funciona: faltan permisos (mira «Permisos» más abajo). Se activará sola al concederlos.':
    'La tecla no está activa. Revisa «Permisos» más abajo; si sigue sin responder tras concederlos, consulta LEEME CHRISTIAN.txt.',
    'Activa «Dictado» en cada lista de Ajustes del Sistema → Privacidad y seguridad. Si acabas de recompilar la app y deja de funcionar, quita «Dictado» de la lista (botón −) y vuelve a añadirla.':
    'Activa «Dilo» en Privacidad y seguridad. Si los permisos figuran activos pero no funcionan, sal de Dilo y, si el panel ofrece −/+, quita solo su entrada y añade la copia actual desde tu carpeta de usuario → Aplicaciones → Dilo. Quitar la entrada no elimina la app ni tus ajustes. En Micrófono, o sin −/+, desactiva y activa el permiso si es posible; vuelve a abrir Dilo y concédelo si se solicita. Consulta LEEME CHRISTIAN.txt para los pasos. No se restablecen permisos automáticamente y volver a concederlos no garantiza resolver el fallo.',
}

class Resources(unittest.TestCase):
    def test_names_identity_and_settings_domain(self):
        p = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
        self.assertEqual(p["CFBundleName"], "Dilo")
        self.assertEqual(p["CFBundleDisplayName"], "Dilo")
        self.assertEqual(p["CFBundleIdentifier"], "local.dictado.DictadoMac")
        self.assertEqual(p["CFBundleExecutable"], "DictadoMac")
        self.assertEqual(p["CFBundleIconFile"], "Dilo.icns")
        self.assertTrue(p["LSUIElement"])
        self.assertEqual(p["CFBundleShortVersionString"], "0.1.1")
        self.assertEqual(p["CFBundleVersion"], "2")
        self.assertIn("Dilo necesita", p["NSMicrophoneUsageDescription"])

    def test_original_exact_and_all_icns_pixels(self):
        original_data = (ROOT / "Resources/Dilo-original.png").read_bytes()
        self.assertEqual(hashlib.sha256(original_data).hexdigest(), ORIGINAL_SHA)
        spec = importlib.util.spec_from_file_location("make_icon", ROOT / "scripts/make-icon.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        data = (ROOT / "Resources/Dilo.icns").read_bytes()
        self.assertEqual(data[:4], b"icns")
        self.assertEqual(struct.unpack(">I", data[4:8])[0], len(data))
        original = Image.open(BytesIO(original_data))
        pos = 8
        chunks = []
        while pos < len(data):
            kind = data[pos:pos+4]
            length = struct.unpack(">I", data[pos+4:pos+8])[0]
            self.assertGreater(length, 8)
            payload = data[pos+8:pos+length]
            chunks.append((kind, payload))
            pos += length
        self.assertEqual(pos, len(data))
        self.assertEqual(len(chunks), len(module.SIZES))
        for (name, size, kind), (actual_kind, payload) in zip(module.SIZES, chunks):
            with self.subTest(name=name):
                self.assertEqual(actual_kind, kind)
                self.assertEqual((ROOT / "Resources/Dilo.iconset" / name).read_bytes(), payload)
                image = Image.open(BytesIO(payload))
                self.assertEqual(image.size, (size, size))
                self.assertEqual(image.tobytes(), original.resize((size, size), Image.Resampling.LANCZOS).tobytes())
        with Image.open(ROOT / "Resources/Dilo.icns") as icns:
            self.assertEqual(icns.format, "ICNS")
            self.assertEqual(len(icns.info["sizes"]), 10)
            icns.load()

    def test_functional_sources_preserved(self):
        baseline = json.loads((ROOT / "Tests/dictation-baseline.json").read_text())
        for path, digest in baseline["files"].items():
            with self.subTest(path=path):
                data = (ROOT / path).read_bytes()
                if path.endswith("AppDelegate.swift"):
                    data = data.replace(b'accessibilityDescription: "Dilo"', b'accessibilityDescription: "Dictado"')
                    data = data.replace(b'Salir de Dilo', b'Salir de Dictado')
                    data = data.replace("Dilo — Ajustes".encode(), "Dictado — Ajustes".encode())
                elif path.endswith("SettingsView.swift"):
                    for original, revised in SETTINGS_COPY_CHANGES.items():
                        old = ('Text("' + original + '")').encode()
                        new = ('Text("' + revised + '")').encode()
                        self.assertEqual(data.count(new), 1)
                        data = data.replace(new, old)
                    data = data.replace("«Dilo»".encode(), "«Dictado»".encode())
                elif path.endswith("ParakeetTranscriber.swift"):
                    # Única llamada cambiada: carga local en CI, descarga original sin bundle.
                    self.assertEqual(data.count(b"AsrModels.diloLoad("), 1)
                    data = data.replace(b"AsrModels.diloLoad(", b"AsrModels.downloadAndLoad(")
                elif path == "Package.swift":
                    data = data.replace("// Dilo —".encode(), "// Dictado Mac —".encode())
                    helper = b'''        .executableTarget(
            name: "DiloModelCheck",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            path: "Tools/DiloModelCheck"
        ),
'''
                    self.assertEqual(data.count(helper), 1)
                    data = data.replace(helper, b"")
                self.assertEqual(hashlib.sha256(data).hexdigest(), digest)

    def test_shell_syntax_and_safe_commands(self):
        paths = sorted((ROOT / "scripts").glob("*.sh")) + sorted(ROOT.glob("*.command"))
        for path in paths:
            with self.subTest(path=path.name):
                r = subprocess.run(["bash", "-n", str(path)], capture_output=True, text=True)
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertTrue(os.access(path, os.X_OK))
        for path in [ROOT / "scripts/build.sh", ROOT / "scripts/install.sh", ROOT / "scripts/run.sh"]:
            text = "\n".join(line for line in path.read_text().splitlines() if not line.lstrip().startswith("#"))
            for forbidden in ["rm -", "pkill ", "sudo ", "tccutil reset", "defaults write", "xattr -"]:
                self.assertNotIn(forbidden, text)

    @unittest.skipUnless(os.uname().sysname == "Linux", "Guarda específica de Linux")
    def test_real_scripts_reject_linux(self):
        for name in ["scripts/build.sh", "scripts/install.sh", "scripts/verify-app.sh", "Actualizar Dilo.command", "Instalar herramientas.command"]:
            with self.subTest(name=name):
                r = subprocess.run(["bash", str(ROOT/name)], input="\n", capture_output=True, text=True)
                self.assertEqual(r.returncode, 1, r.stdout+r.stderr)
                self.assertIn("macOS" if name != "Actualizar Dilo.command" else "Mac", r.stdout+r.stderr)

class MacInstructions(unittest.TestCase):
    def guide(self):
        return (ROOT / "LEEME CHRISTIAN.txt").read_text(encoding="utf-8")

    def assert_gatekeeper_guidance(self, text):
        block = text.split("SI MACOS BLOQUEA", 1)[1].split("AL ABRIR DILO", 1)[0]
        developer, malware = block.split("- Si advierte de malware,", 1)
        self.assertIn("desarrollador no identificado", developer)
        self.assertIn("Privacidad y seguridad", developer)
        self.assertIn("si macOS ofrece esa opción", developer)
        self.assertIn("detente: no lo abras ni intentes eludir el aviso", malware)
        self.assertIn("No uses Abrir igualmente para una advertencia de malware", malware)
        self.assertNotIn("clic secundario", block)
        for command in ["xattr -", "spctl --", "sudo ", "tccutil reset"]:
            self.assertNotIn(command, text)

    def test_plain_text_guide_is_linked_and_packaged(self):
        for path in ["EMPEZAR AQUI.txt", "README.md", "LEEME CHRISTIAN.md",
                     "Sources/DictadoMac/SettingsView.swift", "Actualizar Dilo.command"]:
            with self.subTest(path=path):
                self.assertIn("LEEME CHRISTIAN.txt", (ROOT/path).read_text())
        spec = importlib.util.spec_from_file_location("package_source", ROOT/"scripts/package-source.py")
        assert spec is not None and spec.loader is not None
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        self.assertIn("LEEME CHRISTIAN.txt", module.TOP_FILES)
        self.assertIn("no se ha compilado ni probado en macOS", self.guide())

    def test_manual_permission_recovery_and_no_guarantee(self):
        block = self.guide().split("SI LOS PERMISOS FIGURAN ACTIVOS PERO NO FUNCIONAN", 1)[1].split("ICONO Y PRUEBA", 1)[0]
        compact = " ".join(block.split())
        for required in ["Sal de Dilo", "Accesibilidad", "no elimina la app, tus ajustes ni tus archivos",
                         "si está disponible", "Si aparece el botón +", "~/Applications/Dilo.app",
                         "Monitoreo de entrada", "En Micrófono", "Conceder… si aparece",
                         "quitar y añadir una entrada no siempre basta",
                         "no restablecen ni cambian permisos automáticamente", "guarda una captura"]:
            with self.subTest(required=required):
                self.assertIn(required, compact)
        app = (ROOT/"Sources/DictadoMac/SettingsView.swift").read_text()
        self.assertNotIn("Se activará sola al concederlos", app)
        self.assertIn("no garantiza resolver el fallo", app)

    def test_command_blocking_and_folder_access(self):
        guide = self.guide()
        self.assert_gatekeeper_guidance(guide)
        folder = guide.split("4. Si macOS pregunta", 1)[1].split("5. Dilo se abrirá", 1)[0]
        compact = " ".join(folder.split())
        for required in ["Terminal", "Descargas", "permite ese acceso solo si corresponde",
                         "Archivos y carpetas → Terminal", "No hace falta dar Acceso total al disco"]:
            self.assertIn(required, compact)

    def test_warning_check_rejects_unsafe_or_missing_stop(self):
        guide = self.guide()
        for broken in [guide.replace("detente: no lo abras ni intentes eludir el aviso", "continúa y ábrelo"),
                       guide.replace("No uses Abrir igualmente para una advertencia de malware", ""),
                       guide.replace("si macOS ofrece esa opción", "siempre")]:
            with self.assertRaises(AssertionError):
                self.assert_gatekeeper_guidance(broken)

# Mocks explícitos: prueban ramas shell y conservación de archivos, NO Swift ni Apple.
MOCK = r"""#!/usr/bin/env python3
from pathlib import Path
import os, plistlib, shutil, sys
name = Path(sys.argv[0]).name
args = sys.argv[1:]
if name == 'uname':
    print('Darwin' if args == ['-s'] else os.environ.get('ARCH', 'arm64'))
elif name == 'sw_vers': print(os.environ.get('MACOS_VERSION', '14.7'))
elif name == 'swift':
    if '--version' in args: print('Apple Swift version '+os.environ.get('SWIFT_VERSION', '6.1'))
    elif '--show-bin-path' in args: print(os.environ['BIN_PATH'])
    elif os.environ.get('FAIL_BUILD'): sys.exit(3)
elif name == 'PlistBuddy':
    p = plistlib.loads(Path(args[-1]).read_bytes())
    print(p[args[1].split(':')[-1]])
elif name == 'codesign':
    target = args[-1]
    if os.environ.get('FAIL_SIGN'): sys.exit(1)
    if os.environ.get('FAIL_COPIED') and '.Dilo-nueva.' in target: sys.exit(1)
    if os.environ.get('FAIL_FINAL') and target == os.environ['HOME']+'/Applications/Dilo.app': sys.exit(1)
elif name == 'ditto':
    if os.environ.get('FAIL_COPY'): sys.exit(1)
    shutil.copytree(*args)
elif name == 'pgrep': sys.exit(0 if os.environ.get('RUNNING') else 1)
elif name == 'mv':
    if os.environ.get('FAIL_MOVE') and '.Dilo-nueva.' in args[0] and args[-1].endswith('/Applications/Dilo.app'): sys.exit(1)
    shutil.move(*args)
else: raise RuntimeError(name)
"""

class ScriptSafetyWithMocks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix=".dilo-test-", dir=ROOT / "Tests")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.home = self.base / "usuario con espacios"
        self.home.mkdir()
        self.work = self.base / "fuente con espacios"
        self.work.mkdir()
        shutil.copytree(ROOT / "scripts", self.work / "scripts")
        shutil.copytree(ROOT / "Resources", self.work / "Resources")
        shutil.copy2(ROOT / "THIRD_PARTY_NOTICES.md", self.work / "THIRD_PARTY_NOTICES.md")
        self.mockbin = self.base / "mockbin"
        self.mockbin.mkdir()
        dispatcher = self.mockbin / "dispatcher"
        dispatcher.write_text(MOCK)
        dispatcher.chmod(0o755)
        for name in ["uname", "sw_vers", "swift", "PlistBuddy", "codesign", "ditto", "pgrep", "mv"]:
            (self.mockbin / name).symlink_to(dispatcher)
        # Solo en la copia de prueba se sustituye la ruta Apple absoluta.
        for name in ["install.sh", "verify-app.sh"]:
            path = self.work / "scripts" / name
            path.write_text(path.read_text().replace("/usr/libexec/PlistBuddy", str(self.mockbin / "PlistBuddy")))
        self.binpath = self.base / "binario simulado"
        self.binpath.mkdir()
        executable = self.binpath / "DictadoMac"
        executable.write_text("#!/bin/sh\n# DOBLE DE PRUEBA, NO ES UNA APP MAC\nexit 0\n")
        executable.chmod(0o755)
        (self.binpath / "dependency.bundle").mkdir()
        self.env = {"PATH":str(self.mockbin)+":"+os.defpath, "HOME":str(self.home), "BIN_PATH":str(self.binpath)}
        self.source = self.base / "nueva/Dilo.app"
        self.make_app(self.source, "nueva")
        self.dest = self.home / "Applications/Dilo.app"
        self.make_app(self.dest, "anterior")
        self.original = self.home / "Applications/Dictado.app"
        self.make_app(self.original, "original")
        pref = self.home / "Library/Preferences/local.dictado.DictadoMac.plist"
        pref.parent.mkdir(parents=True)
        pref.write_bytes(plistlib.dumps({"polishEnabled": False, "hotkey": "personalizada"}))
        self.preferences = pref
        self.before_preferences = pref.read_bytes()

    def make_app(self, target, marker):
        (target / "Contents/MacOS").mkdir(parents=True)
        (target / "Contents/Resources").mkdir()
        shutil.copy2(ROOT / "Resources/Info.plist", target / "Contents/Info.plist")
        shutil.copy2(ROOT / "Resources/Dilo.icns", target / "Contents/Resources/Dilo.icns")
        exe = target / "Contents/MacOS/DictadoMac"
        exe.write_text(marker)
        exe.chmod(0o755)

    def run_script(self, name="install.sh", **extra):
        args = [str(self.work / "scripts" / name)]
        if name == "install.sh": args.append(str(self.source))
        return subprocess.run(args, cwd=self.work, env=dict(self.env, **extra), capture_output=True, text=True)

    def marker(self, path): return (path / "Contents/MacOS/DictadoMac").read_text()

    def assert_untouched(self):
        self.assertEqual(self.marker(self.dest), "anterior")
        self.assertEqual(self.marker(self.original), "original")
        self.assertEqual(self.preferences.read_bytes(), self.before_preferences)

    def test_install_keeps_backup_original_and_settings(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertEqual(self.marker(self.dest), "nueva")
        backups = list((self.home / "Applications").glob("Dilo-respaldo.*/Dilo.app"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(self.marker(backups[0]), "anterior")
        self.assertEqual(self.marker(self.original), "original")
        self.assertEqual(self.preferences.read_bytes(), self.before_preferences)

    def test_first_install_preserves_original_and_preferences(self):
        self.dest.rename(self.home / "Dilo-apartada-por-la-prueba.app")
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertEqual(self.marker(self.dest), "nueva")
        self.assertEqual(list((self.home / "Applications").glob("Dilo-respaldo.*")), [])
        self.assertEqual(self.marker(self.original), "original")
        self.assertEqual(self.preferences.read_bytes(), self.before_preferences)

    def test_failed_signature_copy_and_running_do_not_touch_previous(self):
        for condition in ["FAIL_SIGN", "FAIL_COPY", "FAIL_COPIED", "RUNNING"]:
            with self.subTest(condition=condition):
                result = self.run_script(**{condition:"1"})
                self.assertNotEqual(result.returncode, 0, result.stdout+result.stderr)
                self.assert_untouched()

    def test_failed_publish_rolls_back(self):
        result = self.run_script(FAIL_MOVE="1")
        self.assertNotEqual(result.returncode, 0)
        self.assert_untouched()

    def test_failed_final_check_rolls_back_without_deleting_new_app(self):
        result = self.run_script(FAIL_FINAL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assert_untouched()
        failed = list((self.home / "Applications").glob(".Dilo-nueva.*/Dilo-no-validada.app"))
        self.assertEqual(len(failed), 1)
        self.assertEqual(self.marker(failed[0]), "nueva")

    def test_unrelated_existing_app_is_not_replaced(self):
        path = self.dest / "Contents/Info.plist"
        p = plistlib.loads(path.read_bytes())
        p["CFBundleIdentifier"] = "other.Dilo"
        path.write_bytes(plistlib.dumps(p))
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assert_untouched()

    def test_missing_icon_or_changed_identity_is_rejected(self):
        path = self.source / "Contents/Info.plist"
        original = path.read_bytes()
        for key in ["CFBundleIconFile", "CFBundleIdentifier", "CFBundleExecutable",
                    "CFBundleDisplayName", "CFBundleName"]:
            with self.subTest(key=key):
                p = plistlib.loads(original)
                p[key] = "incorrecto"
                path.write_bytes(plistlib.dumps(p))
                result = self.run_script()
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("Bundle rechazado: " + key, result.stderr)
                self.assert_untouched()
        path.write_bytes(original)
        (self.source / "Contents/Resources/Dilo.icns").unlink()
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assert_untouched()

    def test_build_packages_icon_and_keeps_previous_build(self):
        result = self.run_script("build.sh")
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        target = self.work / "dist/Dilo.app"
        self.assertEqual((target/"Contents/Resources/Dilo.icns").read_bytes(), (ROOT/"Resources/Dilo.icns").read_bytes())
        self.assertTrue((target/"Contents/Resources/dependency.bundle").is_dir())
        first = self.marker(target)
        result = self.run_script("build.sh")
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        backup = list((self.work/"dist").glob("Dilo-anterior.*/Dilo.app"))
        self.assertEqual(len(backup), 1)
        self.assertEqual(self.marker(backup[0]), first)
        self.assert_untouched()

    def test_build_failures_leave_installed_app_untouched(self):
        for condition in [{"FAIL_BUILD":"1"}, {"FAIL_SIGN":"1"}, {"SWIFT_VERSION":"5.9"}, {"ARCH":"x86_64"}, {"MACOS_VERSION":"13.6"}]:
            with self.subTest(condition=condition):
                result = self.run_script("build.sh", INSTALL="1", **condition)
                self.assertNotEqual(result.returncode, 0, result.stdout+result.stderr)
                self.assert_untouched()

if __name__ == "__main__":
    unittest.main(verbosity=2)

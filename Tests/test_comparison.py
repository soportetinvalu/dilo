#!/usr/bin/env python3
"""Guardas estáticas de alcance; no sustituyen la ejecución nativa en CI."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class ComparisonScope(unittest.TestCase):
    def test_diagnostic_has_no_persistence_network_clipboard_or_permissions(self):
        for name in ['LastDictationComparison.swift', 'DictationComparisonWindow.swift']:
            text = (ROOT / 'Sources/DictadoMac' / name).read_text()
            for forbidden in ['FileManager', 'UserDefaults', 'Logger(', 'print(', 'URLSession',
                              'Process(', 'NSPasteboard', 'TextInserter', 'Permissions.',
                              'requestAccess', 'Data(contentsOf:', '.write(', '.textSelection',
                              'autosaveName', 'Codex', 'AudioRecorder']:
                with self.subTest(source=name, forbidden=forbidden):
                    self.assertNotIn(forbidden, text)

    def test_menu_is_explicit_and_only_latest_idle_result(self):
        app = (ROOT / 'Sources/DictadoMac/AppDelegate.swift').read_text()
        self.assertIn('title: "Ver último antes y después…"', app)
        self.assertIn('compare.isEnabled = controller.state == .idle && controller.comparison.snapshot != nil', app)
        action = app.split('@objc private func showComparison()', 1)[1].split('@objc private func togglePolish()', 1)[0]
        self.assertIn('guard controller.state == .idle else { return }', action)
        self.assertIn('comparisonWindow.show()', action)
        self.assertIn('func applicationWillTerminate', action)
        self.assertIn('controller.comparison.clear()', action)
        self.assertEqual(app.count('comparisonWindow.show()'), 1)

    def test_native_tests_are_wired_and_mutants_require_real_assertions(self):
        runner = (ROOT / 'scripts/selftest.sh').read_text()
        for source in ['LastDictationComparison.swift', 'DictationComparisonWindow.swift',
                       'DictationController.swift', 'DictationComparisonTests.swift']:
            self.assertIn(source, runner)
        self.assertIn('scripts/test-comparison-mutations.py', runner)
        script = (ROOT / 'scripts/test-comparison-mutations.py').read_text()
        self.assertIn('assert build.returncode == 0', script)
        self.assertIn('run.returncode == 1 and "FALLA " + expected in run.stdout', script)

if __name__ == '__main__':
    unittest.main()

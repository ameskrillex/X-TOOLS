"""Compare legacy-suite failures with the immutable base without editing either script."""
import importlib.util
import io
from pathlib import Path
import unittest
from unittest.mock import patch

root = Path(__file__).resolve().parents[1]
read_text = Path.read_text
baseline = (root/'update/current/versions/3.5.303/X-TOOL.lua').read_text('utf-8')


def run(use_baseline):
    def read(path, *args, **kwargs):
        if use_baseline and path.resolve() == root/'X-TOOL.lua':
            return baseline
        return read_text(path, *args, **kwargs)
    suite = unittest.TestSuite()
    with patch.object(Path, 'read_text', read):
        for path in sorted((root/'tests').glob('test_*.py')):
            if path.name == 'test_aegis_responses.py':
                continue
            spec = importlib.util.spec_from_file_location(path.stem, path)
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            suite.addTests(unittest.defaultTestLoader.loadTestsFromModule(mod))
        result = unittest.TextTestRunner(stream=io.StringIO()).run(suite)
    failures = sorted((test.id(), 'failure') for test, _ in result.failures)
    failures += sorted((test.id(), 'error') for test, _ in result.errors)
    print(('baseline' if use_baseline else 'current'), 'tests', result.testsRun,
          'failures', len(result.failures), 'errors', len(result.errors))
    return sorted(failures)


old = run(True)
new = run(False)
assert old == new, (set(new)-set(old), set(old)-set(new))
print('Legacy failure identities match the unmodified base; no new failing legacy tests.')

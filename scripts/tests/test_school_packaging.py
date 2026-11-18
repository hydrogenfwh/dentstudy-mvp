import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
from package_school_library import package


class SchoolPackagingTests(unittest.TestCase):
    def test_index_omits_bodies_and_roundtrips_every_readable_document(self):
        canonical = SCRIPTS.parent / 'mobile/assets/school_library.json'
        original = json.loads(canonical.read_text())
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / 'school_library.json'
            target.write_bytes(canonical.read_bytes())
            stats = package(target)
            self.assertLess(stats['indexBytes'], 250_000)
            self.assertLess(stats['indexBytes'], stats['canonicalBytes'] / 40)
            index = json.loads(target.with_name('school_library_index.json').read_text())
            for before, after in zip(original['schools'], index['schools']):
                self.assertEqual(before['id'], after['id'])
                self.assertEqual(before['materialBundles'], after['materialBundles'])
                self.assertEqual(len(before['documents']), len(after['documents']))
                for full, metadata in zip(before['documents'], after['documents']):
                    self.assertNotIn('text', metadata)
                    self.assertNotIn('recalledItems', metadata)
                    self.assertEqual(metadata['hasText'], bool(full['text'].strip()))
                    if not metadata['hasText']:
                        self.assertNotIn('bodyAsset', metadata)
                        continue
                    body = target.parent / metadata['bodyAsset'].removeprefix('assets/')
                    content = body.read_bytes()
                    self.assertEqual(body.stem, hashlib.sha256(content).hexdigest())
                    self.assertEqual(json.loads(content), {'id': full['id'], 'text': full['text']})
            # Content-addressed references are deterministic on repeated builds.
            previous = target.with_name('school_library_index.json').read_bytes()
            package(target)
            self.assertEqual(previous, target.with_name('school_library_index.json').read_bytes())


if __name__ == '__main__':
    unittest.main()

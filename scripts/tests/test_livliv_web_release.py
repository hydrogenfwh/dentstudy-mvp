"""Catch a release that drops the on-site LivLiv player, characters or audio."""
import hashlib
import json
import os
from pathlib import Path
import re
import unittest
import wave


WEB = Path(os.environ.get("DENTSTUDY_WEB_ROOT", Path(__file__).resolve().parents[2] / "mobile/web"))


class LivLivReleaseTest(unittest.TestCase):
    def test_room_ships_with_a_model_and_spoken_line_for_every_choice(self):
        root = WEB / "livliv"
        self.assertIn('livliv/pointer-bridge.js', (WEB / 'index.html').read_text())
        self.assertIn('data-voice', (root / 'conversation.html').read_text())
        self.assertIn('Player', (root / 'dist/index.js').read_text())
        choices = re.findall(r"^    \['(\w+)',", (root / 'conversation.js').read_text(), re.M)
        catalog = {item['id'] for item in json.loads((root / 'library/index.json').read_text())}
        lines = json.loads((root / 'voices/lines.json').read_text())
        self.assertEqual(len(choices), 19)
        self.assertEqual(set(choices), catalog)
        self.assertEqual(catalog, set(lines))
        recordings = set()
        for role in choices:
            with self.subTest(role=role):
                folder = root / role if role == 'p01' else root / 'library' / role
                model = (folder / 'model.json').read_text()
                self.assertEqual(json.loads(model)['format'], 'livliv-model')
                textures = re.findall(r'"(textures/[^"]+)"', model)
                self.assertTrue(textures)
                for image in ['avatar.webp', 'cover.webp', *textures]:
                    self.assertEqual((folder / image).read_bytes()[8:12], b'WEBP')
                self.assertTrue(lines[role].strip())
                with wave.open(str(root / 'voices' / f'{role}.wav')) as clip:
                    self.assertEqual((clip.getframerate(), clip.getnchannels()), (24000, 1))
                    self.assertGreater(clip.getnframes(), clip.getframerate())
                    recordings.add(hashlib.sha256(clip.readframes(clip.getnframes())).digest())
        self.assertEqual(len(recordings), len(choices))


if __name__ == '__main__':
    unittest.main()

import copy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from merge_legacy_subject_chapters import (
    ANATOMY, ASSIGNMENTS, FILES, apply_assignments, without_placement,
)


class LegacyChapterMergeTests(unittest.TestCase):
    def test_placement_is_complete_and_source_data_is_unchanged(self):
        current = json.loads(FILES[0].read_text())
        original = json.loads((ROOT / 'question-bank/backups/subject-chapter-merge-20261024/all_questions.json').read_text())
        self.assertEqual(len(current['questions']), 21327)
        self.assertEqual(len(ASSIGNMENTS), 223)
        self.assertEqual([q['id'] for q in current['questions']],
                         [q['id'] for q in original['questions']])
        for before, after in zip(original['questions'], current['questions']):
            if after['id'] in ASSIGNMENTS:
                self.assertEqual(without_placement(before), without_placement(after))
                self.assertEqual(after['chapterByMode']['执医'], ASSIGNMENTS[after['id']])
            else:
                self.assertEqual(before, after)
        self.assertEqual(apply_assignments(current), current)

    def test_source_exports_have_the_same_placement_and_keep_their_own_labels(self):
        for path in FILES[1:]:
            bank = json.loads(path.read_text())
            self.assertEqual(apply_assignments(bank), bank)
            for q in bank['questions']:
                if q['id'] in ASSIGNMENTS:
                    self.assertEqual(q['chapterByMode']['执医'], ASSIGNMENTS[q['id']])
                    self.assertEqual(q['citation']['chapter'], q['subject'])

    def test_conflicting_placement_is_rejected(self):
        q = next(q for q in json.loads(FILES[0].read_text())['questions']
                 if q['id'] == 'YS1000-0001')
        bad = copy.deepcopy(q)
        bad['chapterByMode']['执医'] = '其他章节'
        with self.assertRaises(ValueError):
            apply_assignments({'questions': [bad]})
        self.assertEqual(ASSIGNMENTS['YS1000-0001'], ANATOMY)


if __name__ == '__main__':
    unittest.main()

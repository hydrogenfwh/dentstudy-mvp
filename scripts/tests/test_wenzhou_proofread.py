import json
from pathlib import Path
import sys
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
from wenzhou_proofread import PAGES, proofread
from wenzhou_answers import key


class WenzhouProofreadTests(unittest.TestCase):
    def test_dental_glyph_requires_context_and_preserves_normal_words(self):
        self.assertEqual(proofread('骀面、殆力、覆殆、息止骀间隙、对骀牙、骀支托'),
                         '𬌗面、𬌗力、覆𬌗、息止𬌗间隙、对𬌗牙、𬌗支托')
        normal = '颌骨、咬合、高频电刀、频率、脉搏频弱、踝部、殆尽、骀荡、天然牙随着力的加载'
        self.assertEqual(proofread(normal), normal)

    def test_source_page_repairs_are_scoped_and_repeatable(self):
        before = '由频、舌例两个相对的卡环臀和近、远中两个骀支托'
        self.assertEqual(proofread(before, 201),
                         '由颊、舌侧两个相对的卡环臂和近、远中两个𬌗支托')
        self.assertIn('由频', proofread(before, 200))
        self.assertEqual(proofread('棘层松解', 4), '棘层松解')
        for page, patches in PAGES.items():
            for original in patches:
                corrected = proofread(original, page)
                self.assertEqual(proofread(corrected, page), corrected, (page, original))

    def test_legacy_aliases_keep_the_same_answer_identity(self):
        for before, after in [('牙髋治疗过程中如何控制感染', '牙髓治疗过程中如何控制感染'),
                              ('错畸形的矫治目标', '错𬌗畸形的矫治目标'),
                              ('下颌第一磨牙的面形态', '下颌第一磨牙的𬌗面形态')]:
            self.assertEqual(key(before), key(after))

    def test_published_text_and_paired_answers_use_the_correct_glyph(self):
        payload = json.loads((SCRIPTS.parent / 'mobile/assets/school_library.json').read_text())
        school = next(s for s in payload['schools'] if s['id'] == 'wenzhou-medical-university')
        items = {q['id']: q for d in school['documents'] for q in d.get('recalledItems', [])}
        self.assertEqual(len(items), 466)
        self.assertGreaterEqual(sum(bool(q.get('answer')) for q in items.values()), 252)
        half = items['WZ-R-197-35']['answer']
        for expected in ['由颊、舌侧', '卡环臂', '𬌗支托', '前后有缺隙']:
            self.assertIn(expected, half)
        adjustment = items['WZ-R-198-52']['answer']
        for expected in ['对𬌗牙', '𬌗边缘嵴', '保持𬌗面形态', '前伸𬌗后牙的𬌗干扰']:
            self.assertIn(expected, adjustment)
        for document in school['documents']:
            self.assertNotRegex(document['text'], r'[骀殆]|卡环臀|舌例|牙髋')
        self.assertTrue(items['WZ-R-023-13']['answer'])
        self.assertTrue(items['WZ-R-160-22']['answer'])


if __name__ == '__main__':
    unittest.main()

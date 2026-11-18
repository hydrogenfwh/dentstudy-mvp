import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import sys

SCRIPT = Path(__file__).resolve().parents[1] / 'build_dalian_school_assets.py'
sys.path.insert(0, str(SCRIPT.parent))
SPEC = importlib.util.spec_from_file_location('dalian_assets', SCRIPT)
assets = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(assets)


class SchoolAssetsTests(unittest.TestCase):
    def document(self, id, text, **extra):
        return dict(id=id, text=text, section='materials', subject='口腔修复学',
                    state='candidate', courseSupplement=False,
                    sourceFiles=[id + '.doc'], schoolEvidence=[], **extra)

    def test_identical_complete_text_merges_but_conflicting_answers_do_not(self):
        a = self.document('a', '题目\n 答案A')
        b = self.document('b', '题目   答案A')
        b['state'] = 'reference'
        c = self.document('c', '题目 答案B')
        documents, bundles = assets.merge_materials([a, b, c])
        self.assertEqual(len(documents), 2)
        self.assertEqual(documents[0]['sourceFiles'], ['a.doc', 'b.doc'])
        self.assertEqual(documents[0]['mergedRecordIds'], ['a', 'b'])
        self.assertEqual(bundles[0]['sourceDocumentCount'], 3)
        self.assertEqual([i for g in bundles[0]['groups'] for i in g['documentIds']], ['a', 'c'])

    def test_missing_text_sources_are_preserved_in_pending_group(self):
        documents, bundles = assets.merge_materials([
            self.document('scan1', ''), self.document('scan2', '')])
        self.assertEqual(len(documents), 2)
        self.assertEqual(bundles[0]['groups'][0]['id'], 'pending')

    def test_clean_marks_unknown_symbols_without_guessing_answers(self):
        self.assertEqual(assets.clean('错\ue000畸形【答疑编号123】'), '错[原文特殊符号待核对]畸形')
        self.assertNotIn('\x01', assets.clean('甲\x01乙'))

    def test_generic_titles_keep_subject_context(self):
        self.assertEqual(assets.title_of('最全考研资料/7修复资料/简答.doc'), '修复资料 · 简答')
        self.assertEqual(assets.title_of('口组/3.docx'), '口组 · 3')

    def test_scans_are_listed_without_invented_text_and_media_are_excluded(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shared = root / 'shared'
            shared.mkdir()
            registry = [
                dict(primaryMode='考研', state='needs_ocr', sourceId='scan',
                     relativePath='真题/20年真题.pdf', subjectHint='综合', extension='.pdf',
                     schoolEvidence=[], branch='回忆资料', sha256='a'),
                dict(primaryMode='考研', state='media_reference'),
                dict(primaryMode='执医', state='candidate'),
            ]
            (shared / 'source_registry.json').write_text(json.dumps(registry))
            target = root / 'school_library.json'
            summary = assets.build(root, target)
            document = json.loads(target.read_text())['schools'][0]['documents'][0]
            self.assertEqual(summary['documents'], 1)
            self.assertEqual(summary['newScoredQuestions'], 0)
            self.assertEqual(document['section'], 'recalled')
            self.assertEqual(document['claimedYears'], [2020])
            self.assertFalse(document['yearVerified'])
            self.assertEqual(document['text'], '')
            self.assertEqual(document['questionIds'], [])


if __name__ == '__main__':
    unittest.main()

import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'build_question_bench.py'
SPEC = importlib.util.spec_from_file_location('question_bench', SCRIPT)
bench = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bench)


class BenchTests(unittest.TestCase):
    def row(self, path, **extra):
        return dict(relative_path=path, path='/original/' + path, sha256='a' * 64,
                    bytes=123, extension=Path(path).suffix, **extra)

    def question(self, number, modes, chapter='二、基础'):
        return dict(id=str(number), modes=modes, chapter=chapter, subject='口腔修复学',
                    collection='测试资料', chapterByMode={'考研': '一、考研基础'})

    def test_chapters_natural_order(self):
        values = ['十一、甲', '八、乙', '二、丙', '一、丁', '二十四、戊', '第3章 丙']
        self.assertEqual(sorted(values, key=bench.chapter_number),
                         ['一、丁', '二、丙', '第3章 丙', '八、乙', '十一、甲', '二十四、戊'])

    def test_mode_view_preserves_question_and_shared_ids(self):
        questions = [self.question(1, ['考研', '执医']), self.question(2, ['考研'])]
        snapshot = copy.deepcopy(questions)
        self.assertEqual(bench.mode_catalog(questions, '执医')['questionIds'], ['1'])
        c = bench.mode_catalog(questions, '考研')
        self.assertEqual(c['count'], 2)
        self.assertEqual(c['collections'][0]['subjects'][0]['chapters'][0]['name'], '一、考研基础')
        self.assertEqual(questions, snapshot)

    def test_final_exam_is_not_official_paper(self):
        raw = self.row('11/本科生期末复习题/口外/1口外.doc', option_markers=10)
        row = bench.source_record(raw, '本科复习题')
        self.assertEqual(row['primaryMode'], '考研')
        self.assertEqual(row['branch'], '本科期末与课程补充')
        self.assertIsNone(row['verifiedExamYear'])
        self.assertFalse(row['allowAutoImport'])

    def test_research_paper_inside_final_folder_needs_pairing(self):
        raw = self.row('本科生期末复习题/研究生试卷修复/2010年研究生试题A卷.doc')
        row = bench.source_record(raw, '【答案】A\n' * 20)
        self.assertEqual(row['state'], 'needs_pairing')
        self.assertNotEqual(row['branch'], '本科期末与课程补充')

    def test_licensing_routes_without_automatic_crosslisting(self):
        row = bench.source_record(self.row('牙体/口腔执业医师习题.doc'), '【答案】A\n' * 20)
        self.assertEqual(row['primaryMode'], '执医')
        self.assertEqual(row['state'], 'candidate')
        self.assertFalse(row['allowAutoImport'])

    def test_upgrade_exam_is_not_licensing(self):
        row = bench.source_record(self.row('口腔专升本口外练习题.pdf', pages_with_50_chars=20), '练习题')
        self.assertEqual(row['primaryMode'], '考研')
        self.assertEqual(row['branch'], '本科期末与课程补充')

    def test_scans_and_index_are_not_answered_questions(self):
        scan = bench.source_record(self.row('初试名解.pdf', pages=45, pages_with_50_chars=0), '')
        index = bench.source_record(self.row('口腔组织病理学名词解释.doc'), '神经嵴1\n鳃弓3')
        self.assertEqual(scan['state'], 'needs_ocr')
        self.assertEqual(index['state'], 'reference')

    def test_misplaced_subject_uses_filename(self):
        self.assertEqual(bench.infer_subject('6黏膜资料/华西口腔医学院牙周病学复习题.docx'), '牙周病学')

    def test_build_preserves_inputs_and_exports_replay(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / 'source.txt'
            source.write_text('【答案】A\n' * 12)
            bank = root / 'bank.json'
            bank.write_text(json.dumps({'questions': [self.question(1, ['考研', '执医'])]}))
            manifest = root / 'audit.json'
            manifest.write_text(json.dumps([dict(self.row('口内出题.docx'), text_file=str(source))]))
            before = (bank.read_bytes(), source.read_bytes(), manifest.read_bytes())
            result = bench.build(bank, manifest, root / 'bench')
            self.assertEqual(result['newQuestionsImported'], 0)
            self.assertEqual(result['sharedExistingQuestions'], 1)
            self.assertEqual((bank.read_bytes(), source.read_bytes(), manifest.read_bytes()), before)
            replay = root / 'bench/shared/input_manifest.json'
            result2 = bench.build(bank, replay, root / 'bench')
            self.assertEqual(result, result2)


if __name__ == '__main__':
    unittest.main()

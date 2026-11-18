import importlib.util
import json
from pathlib import Path
import re
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import build_wenzhou_school_assets as assets
import build_dalian_school_assets as dalian
import wenzhou_answers as answers


class WenzhouAssetsTests(unittest.TestCase):
    def test_edition_is_not_an_exam_year_and_conflicts_are_quarantined(self):
        self.assertEqual(assets.year_evidence('【2026】复习资料')[0], None)
        self.assertEqual(assets.year_evidence('牙本质【口腔修复学】（2012复试）')[:2],
                         (2012, '复试'))
        self.assertEqual(assets.year_evidence('牙固连【儿童口腔医学】（2026）')[0], 2026)
        self.assertIsNone(assets.year_evidence('题【口腔修复学】（2015）',
                                              '题【口腔修复学】（2016）')[0])
        self.assertIsNone(assets.year_evidence('题【口腔修复学】（2030）')[0])

    def test_headers_contacts_and_private_names_never_ship(self):
        # Synthetic identity only; no real person's name goes into fixtures.
        tokens = {'测试姓名'}
        page = dict(page=4, lines=[dict(text='【2026】口腔修复学一测试姓名', h=.02),
                                  dict(text='1. 牙本质名词解释', h=.02),
                                  dict(text='电子邮件：example@example.com', h=.02),
                                  dict(text='微信：example-account', h=.02),
                                  dict(text='13812345678', h=.02),
                                  dict(text='笔记补充页', h=.02),
                                  dict(text='补充页伪识别内容', h=.02)])
        self.assertEqual(assets.page_body(page, tokens), ['1. 牙本质名词解释'])
        rotated = dict(page=148, lines=[
            dict(text='【2026】口腔黏膜病学一测试姓名', h=.4),
            dict(text='口腔黏膜病学', h=.3),
            dict(text='1. 医学正文保留', h=.4),
        ])
        self.assertEqual(assets.page_body(rotated, tokens),
                         ['口腔黏膜病学', '1. 医学正文保留'])
        for unsafe in ['测试 姓名', '/Users/private/file.pdf', 'wxid_example',
                       'contact@example.com', '13812345678']:
            with self.assertRaises(ValueError):
                assets.assert_private({'text': unsafe}, tokens)

    def test_dalian_rebuild_preserves_other_schools(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'shared').mkdir()
            (root / 'shared/source_registry.json').write_text('[]')
            target = root / 'school.json'
            other = {'id': assets.SCHOOL_ID, 'documents': [], 'name': '温州医科大学'}
            target.write_text(json.dumps({'schools': [other]}))
            dalian.build(root, target)
            payload = json.loads(target.read_text())
            self.assertEqual(payload['schools'][1], other)
            dalian.build(root, target)
            self.assertEqual(json.loads(target.read_text()), payload)

    def test_public_wenzhou_collection_is_reading_only_and_complete(self):
        payload = json.loads((SCRIPTS.parent / 'mobile/assets/school_library.json').read_text())
        school = next(s for s in payload['schools'] if s['id'] == assets.SCHOOL_ID)
        report = json.loads((SCRIPTS.parent / 'question-bank/考研/温州医科大学/整理报告.json').read_text())
        items = [q for d in school['documents'] for q in d.get('recalledItems', [])]
        self.assertEqual(len(items), report['recalledItems'])
        self.assertEqual(len({q['id'] for q in items}), len(items))
        self.assertEqual(report['yearAssignedItems'] + report['uncertainYearItems'], len(items))
        self.assertEqual(len(school['materialBundles']), 10)
        self.assertEqual(sum(d['sourceLabel'] == '人卫讲义' for d in school['documents']), 22)
        self.assertEqual(sum(d['sourceLabel'] == '真题' for d in school['documents']), 33)
        paired = [q for q in items if q.get('answer')]
        self.assertEqual(len(paired), report['pairedAnswerItems'])
        self.assertGreater(len(paired), 200)
        for q in paired:
            self.assertTrue(q['answerSourcePages'])
            self.assertTrue(q['answerEntryId'])
            self.assertIn(q['answerMatch'], ['exact_heading', 'reviewed_heading'])
            self.assertTrue(all(6 <= p <= 266 for p in q['answerSourcePages']))
        for d in school['documents']:
            lecture = d.get('materialGroup') in ('terms', 'qa')
            source = '人卫讲义' if lecture else '真题'
            self.assertTrue(d['sourceAnswersReviewed'])
            self.assertEqual(d['state'], 'source_answers' if lecture else 'verified_paper')
            self.assertEqual(d['questionIds'], [])
            self.assertFalse(d['yearVerified'])
            self.assertTrue(d['sourceVerified'])
            self.assertEqual(d['sourceVerification'], 'owner_confirmed')
            self.assertTrue(all(4 <= p <= 266 for p in d['sourcePages']))
            self.assertEqual(d['sourceFiles'], [source])
            self.assertEqual(d['sourceLabel'], source)
            if lecture:
                self.assertTrue(d['text'].startswith('来源：人卫讲义。'))
                self.assertFalse(d.get('recalledItems'))
            if d.get('recalledItems'):
                blocks = d['text'].split('\n\n')
                self.assertEqual(len(blocks), len(d['recalledItems']))
                self.assertTrue(all('\n' not in block for block in blocks))
            for q in d.get('recalledItems', []):
                if d['section'] == 'recalled':
                    self.assertEqual(d['claimedYears'], [q['year']])
                    self.assertIn(str(q['year']), q['yearEvidence'])
                else:
                    self.assertIsNone(q['year'])
        encoded = json.dumps(school, ensure_ascii=False)
        self.assertIsNone(assets.CONTACT.search(encoded))
        self.assertNotIn('/Users/', encoded)
        self.assertNotIn('xwechat_files', encoded)
        self.assertNotIn('整理制作', encoded)
        for removed in ['PDF', '原资料标注：', '【原资料答案】', '答案来源：']:
            self.assertNotIn(removed, encoded)

    def test_original_answer_extraction_preserves_cross_page_continuation(self):
        entries = answers.extract_entries([
            (6, ['一、名词解释', '1. 修复性牙本质（reparative dentin）：原资料定义',
                 '口腔内的表现如下：']),
            (7, ['原资料跨页续文。', '2. 球间牙本质：另一段完整的原文定义。']),
        ], '口腔组织病理学', '', '名词解释', 'fixture')
        self.assertEqual(len(entries), 2)
        self.assertEqual(entries[0]['sourcePages'], [6, 7])
        self.assertIn('口腔内的表现如下：', entries[0]['text'])
        self.assertIn('原资料跨页续文。', entries[0]['text'])
        self.assertNotIn('另一段', entries[0]['text'])
        item = dict(subject='口腔组织病理学', subdivision='', kind='名词解释',
                    stem='reparative dentin')
        self.assertEqual(answers.attach_answers([item], entries), 1)
        self.assertEqual(item['answer'], entries[0]['text'])
        self.assertEqual(item['answerSourcePages'], [6, 7])

    def test_similar_medical_questions_are_not_auto_matched(self):
        for question, heading in [('Le Fort II型骨折', 'Le Fort I型骨折'),
                                  ('上下切牙的区别', '上下颌尖牙的区别'),
                                  ('口腔颌面部损伤的特点', '口腔颌面部感染的特点')]:
            entry = dict(id='a', subject='口腔颌面外科学', subdivision='',
                         kind='简答与论述', heading=heading,
                         headingKeys=list(answers.heading_keys(heading, '简答与论述')),
                         text=heading + '\n原文答案', sourcePages=[165],
                         sourceDocumentId='fixture')
            item = dict(subject=entry['subject'], subdivision='',
                        kind='简答与论述', stem=question)
            self.assertEqual(answers.attach_answers([item], [entry]), 0)
            self.assertEqual(item['answer'], '')

    def test_conflicting_original_answers_remain_unpaired(self):
        common = dict(subject='口腔修复学', subdivision='', kind='名词解释',
                      heading='高嵌体', headingKeys=['高嵌体'],
                      sourcePages=[199], sourceDocumentId='fixture')
        entries = [dict(common, id='a', text='不同答案一'),
                   dict(common, id='b', text='不同答案二')]
        item = dict(subject='口腔修复学', subdivision='', kind='名词解释', stem='高嵌体')
        self.assertEqual(answers.attach_answers([item], entries), 0)
        self.assertEqual(item['answerMatch'], 'ambiguous')


if __name__ == '__main__':
    unittest.main()

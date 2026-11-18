"""Build read-only question-bank views and a quarantined source intake bench.

Does not import questions, move source files, touch accounts, or deploy anything.
Existing question IDs/data are referenced, not rewritten or duplicated.
"""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
STATES = {
    'candidate': '带答案候选（待逐题解析校验）',
    'needs_pairing': '题卷与答案待配对',
    'needs_cleanup': '带答案PDF待清洗及版面核对',
    'needs_ocr': '图片资料待OCR及核对',
    'needs_answer': '缺答案或完整性待逐题检查',
    'recalled': '回忆资料待核实/补齐答案',
    'reference': '参考资料，不直接入刷题库',
    'media_reference': '课件或多媒体，不直接入刷题库',
    'needs_extraction': '文字提取异常，待进一步检查',
}
DOC_EXTS = {'.doc', '.docx', '.rtf', '.wps', '.txt', '.pdf'}
IMAGE_WORDS = {'口内2.doc', '正畸1.doc', '正畸2（作为补充材料）.doc', '牙周病学复习题.doc'}
INDEX_NAMES = {'儿童口腔病学名词解释.doc', '口腔组织病理学名词解释.doc',
               '口腔解剖生理学名词解释.doc', '儿牙名词总结.doc', '口解名词总结.doc'}
SUBJECTS = [
    ('儿牙', '儿童口腔医学'), ('儿童口腔', '儿童口腔医学'),
    ('口组', '口腔组织病理学'), ('口病', '口腔组织病理学'), ('组织病理', '口腔组织病理学'),
    ('牙体', '牙体牙髓病学'), ('牙髓', '牙体牙髓病学'),
    ('牙周', '牙周病学'), ('黏膜', '口腔黏膜病学'), ('粘膜', '口腔黏膜病学'),
    ('口解', '口腔解剖生理学'), ('解剖生理', '口腔解剖生理学'),
    ('口外', '口腔颌面外科学'), ('颌面外科', '口腔颌面外科学'),
    ('修复', '口腔修复学'), ('口修', '口腔修复学'), ('义齿', '口腔修复学'),
    ('正畸', '口腔正畸学'), ('口内', '口腔内科学'),
]


def dump(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def chapter_number(label):
    if label.startswith('总论'):
        return (0, label)
    match = re.match(r'^\s*第?([一二三四五六七八九十百零〇两\d]+)[、章.．]', label)
    if not match:
        return (10000, label)
    text = match.group(1)
    if text.isdigit():
        return (int(text), label)
    digits = dict(zip('零一二三四五六七八九', range(10)))
    value = unit = 0
    for char in text.replace('两', '二').replace('〇', '零'):
        if char in digits:
            unit = digits[char]
        elif char in ('十', '百'):
            value += (unit or 1) * (10 if char == '十' else 100)
            unit = 0
    return (value + unit, label)


def collection_name(question):
    if question.get('collection'):
        return question['collection']
    if question['id'].startswith(('CH', 'OMFS')) or '口外终版' in question.get('reference', ''):
        return '口腔颌面外科考研资料整理'
    if '修复学 终版' in question.get('reference', ''):
        return '口腔修复学考研资料整理'
    return question.get('paperName') or '其他现有资料'


def mode_catalog(questions, mode):
    subset = [q for q in questions if mode in q['modes']]
    groups = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))
    for q in subset:
        chapter = q.get('chapterByMode', {}).get(mode, q['chapter'])
        groups[collection_name(q)][q['subject']][chapter].append(q['id'])
    collections = []
    for name in sorted(groups, key=lambda x: (x != '人卫练习题', x)):
        subjects = []
        for subject, chapters in sorted(groups[name].items()):
            rows = [{'name': chapter, 'questionIds': chapters[chapter], 'count': len(chapters[chapter])}
                    for chapter in sorted(chapters, key=chapter_number)]
            subjects.append({'name': subject, 'count': sum(x['count'] for x in rows), 'chapters': rows})
        collections.append({'name': name, 'count': sum(s['count'] for s in subjects), 'subjects': subjects})
    return {'mode': mode, 'kind': 'existing_bank_view_not_new_import',
            'count': len(subset), 'subjectCount': len({q['subject'] for q in subset}),
            'questionIds': [q['id'] for q in subset], 'collections': collections}


def infer_subject(relative):
    # Prefer the actual filename, since e.g. a periodontology file is misplaced
    # inside the mucosal-disease folder. Never force composite papers into one subject.
    name = Path(relative).name
    if any(term in name for term in ('各科', '真题', '期末考试题', '毕业考试题')):
        return '综合/待逐题细分'
    for value in (name, relative):
        for token, subject in SUBJECTS:
            if token in value:
                return subject
    return '科目待核实'


def source_record(raw, text):
    relative, ext = raw['relative_path'], raw['extension']
    name = Path(relative).name
    explicit_answers = len(re.findall(r'(?:正确答案[:：]|【答案】[:：]?)\s*[A-H]', text))
    final_exam = (('本科生期末复习题' in relative or '期末考试题' in relative
                   or '专升本' in name or '课程试卷' in text[:500]
                   or '2000级七年制' in name + text[:500])
                  and '研究生试卷修复' not in relative)
    licensing = bool(re.search('执业医师', name + text[:120]))
    if ext not in DOC_EXTS:
        state, reason = 'media_reference', '非题库文档；没有逐页审阅课件或逐帧审阅影像。'
    elif raw.get('error'):
        state, reason = 'needs_extraction', raw['error']
    elif name in IMAGE_WORDS or (ext == '.pdf' and raw.get('pages_with_50_chars', 0) == 0):
        state, reason = 'needs_ocr', '扫描或图片文字，现有文字层不可直接解析；OCR后还需核对题目与答案。'
    elif name in INDEX_NAMES:
        state, reason = 'reference', '术语/英文/页码索引，不是逐条完整定义。'
    elif name in {'口腔执业医师牙体牙髓病学练习题及答案.pdf', '口腔执业医师口腔黏膜病学练习题及答案.pdf'}:
        state, reason = 'needs_cleanup', '前轮检查已确认存在题目与集中答案，但抽取有断行/叠字，须清洗、配对和版面核对。'
    elif '/真题/' in relative:
        state, reason = 'recalled', '回忆题/考点混合资料，不视为已核验正式试卷或完整答案。'
    elif '研究生试卷修复' in relative and ('卷' in name or '答案' in name or '修复考研题' in name):
        state, reason = 'needs_pairing', '需要按卷别、题型、题号与答案文档配对；不得仅凭研究生字样断言入学考试性质。'
    elif explicit_answers >= 10:
        state, reason = 'candidate', '检测到明确答案片段，仅表示有可解析候选，不保证全文件题目完整。'
    elif name == '选择无答案.doc' and '8口组资料' in relative:
        state, reason = 'candidate', '混合资料：部分题带答案/解析，部分无答案，必须逐题筛选。'
    elif name in {'简答.doc', '名词.doc', '名词1.doc', '知识点2.doc', '知识点5.rtf', '口腔黏膜病学试题B.doc'}:
        state, reason = 'candidate', '存在原有问答/定义内容；须逐条确认题干及参考答案完整，不自动生成缺失答案。'
    elif any(term in name for term in ('讲义', '总结', '课件', '重点', '口诀', '知识点', '图谱', '整理', '歌诀')):
        state, reason = 'reference', '混合知识笔记/参考资料；其中若有完整题目，可另行筛选，不自动造题。'
    elif (raw.get('option_markers', 0) or any(term in name for term in ('题', '填空'))
          or (final_exam and any(term in text[:2000] for term in ('简答', '论述', '辅导题', '复习题', '名词解释')))):
        state, reason = 'needs_answer', '尚未确认逐题完整答案；需要检查是否有集中答案或其他配套文件。'
    else:
        state, reason = 'reference', '尚未确认成对题干与答案，暂作为参考资料。'
    # Collections, textbooks and atlases are not made into quiz sources by OCR.
    if any(term in name for term in ('图谱', '北医_临床牙周病学', '歌诀', '口诀')):
        state, reason = 'reference', '图谱/教材/记忆辅助资料，保留参考用途，不直接当习题。'
    primary_mode = '执医' if licensing else '考研'
    branch = '本科期末与课程补充' if final_exam else ('专项练习' if primary_mode == '执医' else '大连资料包')
    if '/真题/' in relative:
        branch = '历年回忆资料（待核实）'
    school_text = name + re.sub(r'\s+', '', text[:1800])
    schools = [s for s in ('北京大学', '南华大学', '山东大学', '西安交通大学', '中南大学', '中国医科大学', '大连医科大学')
               if s in school_text]
    return {
        'sourceId': 'DL-' + raw['sha256'][:20], 'relativePath': relative,
        'originalPath': raw['path'], 'sha256': raw['sha256'], 'bytes': raw['bytes'],
        'extension': ext, 'subjectHint': infer_subject(relative),
        'primaryMode': primary_mode, 'branch': branch,
        'otherModeEligibility': '待逐题核实适用性；不自动加入另一方向',
        'state': state, 'stateLabel': STATES[state], 'reason': reason,
        'allowAutoImport': False, 'reviewLevel': 'file_structure_only_not_medical_review',
        'schoolEvidence': schools, 'verifiedSchool': None, 'verifiedExamYear': None,
        'textChars': raw.get('chars', 0), 'explicitAnswerFragments': explicit_answers,
        'pdfPages': raw.get('pages'), 'pdfTextPages': raw.get('pages_with_50_chars'),
    }


def build(bank_path, audit_path, out):
    bank_bytes = bank_path.read_bytes()
    questions = json.loads(bank_bytes)['questions']
    ids = [q['id'] for q in questions]
    if len(ids) != len(set(ids)):
        raise ValueError('Existing bank contains duplicate question IDs')
    raw_records = json.loads(audit_path.read_text())
    records = []
    replay_manifest = []
    hash_groups = defaultdict(list)
    for raw in raw_records:
        text_path = Path(raw['text_file']) if raw.get('text_file') else None
        text = text_path.read_text() if text_path and text_path.exists() else raw.get('head', '')
        row = source_record(raw, text)
        if text_path and text_path.exists():
            # Preserve extracted text as a staging artifact, not an imported question.
            target = out / 'shared/source_text' / (row['sourceId'] + '.txt')
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)
            row['extractedText'] = str(target.relative_to(out))
            raw = dict(raw, text_file=str(target.resolve()))
        replay_manifest.append(raw)
        records.append(row)
        hash_groups[row['sha256']].append(row['relativePath'])
    dump(out / 'shared/source_registry.json', records)
    dump(out / 'shared/input_manifest.json', replay_manifest)
    duplicates = [paths for paths in hash_groups.values() if len(paths) > 1]
    catalogues = {}
    for mode in ('考研', '执医'):
        catalogues[mode] = mode_catalog(questions, mode)
        dump(out / mode / '现有题库目录.json', catalogues[mode])
        dump(out / mode / '新资料整理队列.json', [r for r in records if r['primaryMode'] == mode])
    summary = {
        'schemaVersion': 1, 'scope': 'local_framework_and_source_staging_only',
        'bankPath': str(bank_path.resolve()), 'bankSha256': hashlib.sha256(bank_bytes).hexdigest(),
        'uniqueExistingQuestions': len(ids),
        'sharedExistingQuestions': sum(all(m in q['modes'] for m in ('考研', '执医')) for q in questions),
        'modes': {m: {'count': c['count'], 'subjectCount': c['subjectCount']} for m, c in catalogues.items()},
        'sourceFileCount': len(records), 'sourceBytes': sum(r['bytes'] for r in records),
        'sourceStateCounts': dict(Counter(r['state'] for r in records)),
        'sourceRouteCounts': dict(Counter(r['primaryMode'] for r in records)),
        'exactDuplicateFileGroups': duplicates,
        'newQuestionsImported': 0, 'productionChanged': False,
        'gate': ['原始来源可追溯', '题干与必要图完整', '选项及共用题干完整',
                 '客观题有唯一可确认答案/主观题有原文rubric', '逐题答案配对',
                 '同题重复/冲突隔离', '科目与章节核实', '人工审核与发布授权'],
    }
    dump(out / 'bench.json', summary)
    lines = [
        'Dentstudy bench：考研 / 执医双方向题库框架', '',
        '此为本地目录与资料整理台，不是新题导入完成或医学审核通过的声明。',
        '原始文件不搬动，App题库不改动，不部署，不改变学习记录或账号。', '',
        '一、两部分框架',
        '考研：人卫练习题 → 科目 → 章节；考研专项资料 → 科目 → 章节；',
        '      大连资料包 → 回忆资料 / 本科期末与课程补充 / 专项练习 / 参考资料。',
        '执医：未标年份资料 → 现有各资料集 → 科目 → 章节；人卫练习题 → 科目 → 章节；',
        '      新资料仅把明确执业医师来源先归此方向；专升本仍为课程补充，适用性另核实。',
        '注：bench只描述分类，不改变App现有入口顺序。其他方向是否共享，不自动推定。', '',
        '二、当前数据基线',
        '独立题目：%s；两方向共用：%s（不得把两方向数量相加当作独立题数）。' % (len(ids), summary['sharedExistingQuestions']),
    ]
    for mode, c in catalogues.items():
        lines += ['%s：%s题，%s科。' % (mode, c['count'], c['subjectCount'])]
        lines += ['  %s：%s题' % (x['name'], x['count']) for x in c['collections']]
    lines += ['', '三、新资料状态（文件数，不是题数；含同文件副本）']
    lines += ['%s：%s份' % (STATES[k], v) for k, v in sorted(summary['sourceStateCounts'].items())]
    lines += ['', 'candidate仅表示文件中有可整理内容，不表示每题已通过入库门槛。',
              '科目为线索，真实章节、年份和院校须根据正文逐题核实。',
              '本科期末不冒充考研真题；外校资料不冒充大医资料；目录年级不当考试年份。',
              '原文无解析可以明示缺失；原文无答案不得自动补造。', '', '四、所有资料逐文件清单']
    for mode in ('考研', '执医'):
        lines += ['', '【%s】' % mode]
        for row in records:
            if row['primaryMode'] == mode:
                lines += ['[%s] [%s] [%s] %s' % (row['stateLabel'], row['branch'], row['subjectHint'], row['relativePath']),
                          '  ' + row['reason']]
    (out / '框架与逐文件清单.txt').write_text('\n'.join(lines) + '\n')
    return summary


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bank', type=Path, default=ROOT / 'mobile/assets/all_questions.json')
    parser.add_argument('--audit-manifest', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=ROOT / 'output/bench')
    args = parser.parse_args()
    print(json.dumps(build(args.bank, args.audit_manifest, args.output), ensure_ascii=False, indent=2))

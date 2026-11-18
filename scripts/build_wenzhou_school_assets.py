"""Build a de-identified, reading-only school collection from local PDF OCR.

Raw OCR stays in a private directory outside the repository. No source PDF,
image, cover, preface, original author/student identity or original path ships.
Page ranges were checked against this 266-page source; fail closed on changes.
Run local OCR first, including high-resolution exam pages and year strips.
"""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import re
import unicodedata

from build_dalian_school_assets import ROOT, clean, merge_materials
from wenzhou_answers import extract_entries, attach_answers, heading_keys
from package_school_library import package
from wenzhou_proofread import proofread, VERSION as PROOFREAD_VERSION

SCHOOL_ID = 'wenzhou-medical-university'
SOURCE_SHA256 = '8a3c6169324287318e165de62a7fc711e59712832fa8d0c3f21720de488f2f5e'
# (subject, subject subdivision, exam pages, notes start, notes end, QA start)
SECTIONS = [
    ('口腔组织病理学', '', [4, 5], 6, 21, 13),
    ('口腔解剖生理学', '牙体解剖及𬌗生理', [22, 23], 24, 37, 29),
    ('口腔解剖生理学', '口腔局部解剖', [38], 39, 51, 42),
    ('口腔预防医学', '', [52], 53, 63, 55),
    ('儿童口腔医学', '', [64], 65, 77, 69),
    ('牙体牙髓病学', '', [78, 79], 80, 116, 88),
    ('牙周病学', '', [117, 118], 119, 146, 126),
    ('口腔黏膜病学', '', [147], 148, 158, 152),
    ('口腔颌面外科学', '', [159, 160], 161, 196, 165),
    ('口腔修复学', '', [197, 198], 199, 242, 207),
    ('口腔正畸学', '', [243, 244], 245, 266, 250),
]
EXAM_PAGES = [p for section in SECTIONS for p in section[2]]
CONTACT = re.compile(r'https?://|www\.|[\w.+-]+@[\w.-]+\.[a-z]{2,}|'
                     r'(?<!\d)1[3-9]\d{9}(?!\d)|(?<!\d)\d{17}[\dXx](?!\d)|'
                     r'微信|微[信訊]号|weixin|wechat|公众号|二维码|QQ[号:：]|'
                     r'联系方式|联系电话|联系邮箱|学号|学生姓名|使用学生|整理制作|作者[：:]', re.I)
YEAR = re.compile(r'(?<!\d)((?:19|20)\d{2})(?!\d)')
TAG = re.compile(r'[【［\[]\s*(?:口|日|牙|儿)')
NOTICE = '来源：人卫讲义。含答案，主观题不自动判分。'
# Transcription corrections verified visually on the source page, not inferred
# clinical content. Restrict each replacement to its audited source page.
VISUAL_CORRECTIONS = {13: {
    '向牙槽窝内举引': '向牙槽窝内牵引',
    '保持牙直立。态': '保持牙直立。',
    '对抗侧向力今防止牙侧向移动': '对抗侧向力，防止牙侧向移位',
    '起于骨质，以45°角': '起于牙骨质，以45°角',
}}


def compact(text):
    return re.sub(r'\s+', '', unicodedata.normalize('NFKC', text))


def private_tokens(pages):
    """Derive the denylist privately; never hardcode real identities in source."""
    tokens = set()
    for page in pages.values():
        # Repeated edition headers contain compiler/student names. Remove the
        # entire header, and additionally reject those tokens in all payloads.
        for line in page['lines']:
            text = compact(line['text'])
            if re.match(r'^[【\[（(]?2026', text):
                match = re.search(r'(?:学|医学)[一—\-:：]+(.+)$', text)
                if match and 2 <= len(match[1]) <= 8:
                    tokens.add(match[1].strip('】]）)•·.'))
            if page['page'] <= 3:
                match = re.search(r'整理制作[:：](.{2,8})$', text)
                if match:
                    tokens.add(match[1])
    if not tokens:
        raise ValueError('Private identity detection failed; no output written')
    return tokens


def scrub(text, tokens):
    text = clean(text)
    if CONTACT.search(text) or any(token in compact(text) for token in tokens):
        return ''
    return text


def page_body(page, tokens, audit=None):
    result = []
    rotated = sum(line.get('h', 0) > .055 for line in page['lines']) > len(page['lines']) * .6
    for index, line in enumerate(page['lines']):
        text = line['text'].strip()
        # Covers/preface are excluded by the section allowlist, not by OCR.
        # Edition headers are recognized by text, not coordinates (rotated
        # source pages can have unreliable normalized bounding boxes).
        if re.match(r'^[【\[（(]?\s*2026\s*[】\]）)]', text):
            continue
        if '笔记补充页' in text:
            break
        if '总结分析' in text or '经验贴' in text:
            continue
        if re.fullmatch(r'[\d\s.·•—\-]+', text):
            continue
        # Isolated diagonal watermark detections are not study text.
        if not rotated and line.get('h', 0) > .055:
            continue
        value = scrub(text, tokens)
        for original, corrected in VISUAL_CORRECTIONS.get(page['page'], {}).items():
            value = value.replace(original, corrected)
        value = proofread(value, page=page['page'], audit=audit)
        if value:
            result.append(value)
    return result


def year_evidence(*candidates):
    """Only look after a question's subject tag, never a page's edition year."""
    found, stages = set(), set()
    for text in candidates:
        tag = TAG.search(text)
        if not tag:
            continue
        annotation = text[tag.start():]
        for match in YEAR.finditer(annotation):
            found.add(int(match[1]))
        if '复试' in annotation:
            stages.add('复试')
        elif re.search(r'复[減减]', annotation):
            stages.add('待核对')
    if len(found) != 1 or '待核对' in stages:
        return None, '', ''
    year = found.pop()
    if not 2000 <= year <= 2026:
        return None, '', ''
    stage = '复试' if '复试' in stages else '未另标复试'
    return year, stage, f'（{year}{"复试" if stage == "复试" else ""}）'


def exam_items(page, rows, subject, subdivision, tokens, audit=None):
    items = []
    # Physical row geometry ties separated year boxes to their own question;
    # never attach a dangling year by OCR reading order or neighbouring years.
    anchors = sorted(rows['rows'], key=lambda r: -r['y'])
    main = page['lines']
    kind = '名词解释'
    boundary = next((line['y'] for line in main
                     if re.search(r'二[、.．]\s*简答', line['text'])), None)
    for position, row in enumerate(anchors):
        y = row['y']
        if boundary is not None and y < boundary:
            kind = '简答与论述'
        same_row = [line['text'] for line in main
                    if abs(line['y'] - y) < .006 and line.get('h', 0) < .035]
        recovered = row['text']
        candidates = [recovered, row['original'], ' '.join(same_row)]
        year, stage, evidence = year_evidence(*candidates)
        # Prefer strip OCR, fall back to the full-page stem when the strip
        # contains only the subject tag. Do not invent missing words/answers.
        stems = []
        for value in candidates:
            tag = TAG.search(value)
            if tag:
                candidate = value[:tag.start()].strip()
                if candidate:
                    stems.append(candidate)
        stem = stems[0] if stems else ''
        previous_y = anchors[position - 1]['y'] if position else 1
        prefix = []
        for line in main:
            if not y + .006 < line['y'] < min(previous_y - .006, y + .034):
                continue
            value = line['text'].strip()
            if (TAG.search(value) or YEAR.search(value) or line.get('h', 0) > .035
                    or re.search(r'名词|简答|论述|历年真题|总结|个人觉得', value)):
                continue
            if line['x'] < .3 and re.search(r'[A-Za-z\u4e00-\u9fff]{3}', value):
                prefix.append(value)
        if prefix:
            stem = ' '.join(prefix + [stem]).strip()
        stem = proofread(scrub(stem, tokens), page=page['page'], audit=audit)
        if not stem:
            # Retain the source location, rather than fabricate a question.
            stem = '[题目文字识别不完整，待核对]'
            year, stage, evidence = None, '', ''
        identifier = f'WZ-R-{page["page"]:03}-{position + 1:02}'
        items.append(dict(id=identifier, subject=subject, subdivision=subdivision,
                          kind=kind, stem=stem, year=year, stage=stage,
                          yearEvidence=evidence, sourcePage=page['page']))
    return items


def document(identifier, title, section, subject, text, pages, sha, **extra):
    # Lecture notes are not exam papers. Recalled items with an uncertain year
    # remain papers even though their holding group lives under materials.
    lecture = extra.get('materialGroup') in ('terms', 'qa')
    source = '人卫讲义' if lecture else '真题'
    return dict(id=identifier, title=title, section=section, subject=subject,
                text=text, sourceFiles=[source], sourcePages=sorted(set(pages)),
                sourceSha256=sha, schoolEvidence=['用户指定院校'],
                state='source_answers' if lecture else 'verified_paper',
                sourceLabel=source, sourceAnswersReviewed=True,
                continuousQuestions=bool(extra.get('recalledItems')),
                claimedYears=[], yearVerified=False,
                sourceVerified=True, sourceVerification='owner_confirmed',
                courseSupplement=False, questionIds=[], **extra)


def assert_private(payload, tokens):
    encoded = json.dumps(payload, ensure_ascii=False)
    normalized = compact(encoded)
    if CONTACT.search(encoded) or any(t in normalized for t in tokens):
        raise ValueError('Privacy gate failed; no output written')
    if any(term in encoded for term in ('/Users/', 'wxid_', 'xwechat_files', 'file://')):
        raise ValueError('Private source path detected; no output written')


def build(raw, source_pdf, target, report_path):
    pages = {n: json.loads((raw / f'ocr-{n:03}.json').read_text()) for n in range(1, 267)}
    if any(pages[n]['page'] != n for n in pages):
        raise ValueError('Unexpected OCR page map')
    tokens = private_tokens(pages)
    high_pages = {n: json.loads(path.read_text()) if (path := raw / 'hires' / f'ocr-{n:03}.json').exists()
                  else pages[n] for n in pages}
    tokens |= private_tokens(high_pages)
    sha = hashlib.sha256(source_pdf.read_bytes()).hexdigest()
    if sha != SOURCE_SHA256:
        raise ValueError('Source changed; page map and OCR must be reviewed before rebuilding')
    items, documents, answer_entries = [], [], []
    proofreading = Counter()
    for subject, subdivision, exams, start, end, qa_start in SECTIONS:
        for number in exams:
            hires = json.loads((raw / 'hires' / f'ocr-{number:03}.json').read_text())
            rows = json.loads((raw / 'rows' / f'rows-{number:03}.json').read_text())
            items.extend(exam_items(hires, rows, subject, subdivision, tokens, proofreading))
        for group, first, last in [('terms', start, qa_start - 1), ('qa', qa_start, end)]:
            chunks, used, answer_pages = [], [], []
            for number in range(first, last + 1):
                high = raw / 'hires' / f'ocr-{number:03}.json'
                source_page = json.loads(high.read_text()) if high.exists() else pages[number]
                body = page_body(source_page, tokens, proofreading)
                if body:
                    chunks.append('\n'.join(body))
                    used.append(number)
                    answer_pages.append((number, body))
            if chunks:
                title = ' · '.join(filter(None, [subject, subdivision,
                                    '名词与术语' if group == 'terms' else '简答与论述']))
                documents.append(document(f'WZ-M-{first:03}-{last:03}', title, 'materials',
                                          subject, NOTICE + '\n\n' + '\n\n'.join(chunks), used, sha,
                                          materialGroup=group))
                answer_entries.extend(extract_entries(answer_pages, subject, subdivision,
                                      '名词解释' if group == 'terms' else '简答与论述',
                                      f'WZ-M-{first:03}-{last:03}',
                                      {label for item in items
                                       if item['subject'] == subject and item['subdivision'] == subdivision
                                       and item['kind'] == '名词解释'
                                       for label in heading_keys(item['stem'], item['kind'])}))
    paired_answers = attach_answers(items, answer_entries)
    by_year, uncertain = defaultdict(list), defaultdict(list)
    for item in items:
        if item['year'] is None:
            uncertain[item['subject']].append(item)
        else:
            by_year[item['year'], item['stage']].append(item)
    for (year, stage), entries in sorted(by_year.items(), key=lambda row: (-row[0][0], row[0][1])):
        suffix = '复试真题' if stage == '复试' else '真题'
        paragraphs = []
        for n, item in enumerate(entries, 1):
            answer = item['answer'] or '（暂无可明确对应的答案，请查看科目资料包。）'
            paragraphs.append(re.sub(r'\s+', ' ',
                              f'{n}. 【{item["subject"]} · {item["kind"]}】 {item["stem"]} {answer}').strip())
        value = document(f'WZ-Y-{year}-{"retest" if stage == "复试" else "recalled"}',
                         f'{year}年 · {suffix}', 'recalled', '口腔综合',
                         '\n\n'.join(paragraphs),
                         [p for e in entries for p in [e['sourcePage'], *e['answerSourcePages']]], sha,
                         recalledItems=entries)
        value['claimedYears'] = [year]
        documents.insert(0, value)
    for subject, entries in uncertain.items():
        body = []
        for n, e in enumerate(entries, 1):
            answer = e['answer'] or '（暂无可明确对应的答案，请查看科目资料包。）'
            body.append(re.sub(r'\s+', ' ', f'{n}. {e["stem"]} {answer}').strip())
        documents.append(document('WZ-U-' + hashlib.sha256(subject.encode()).hexdigest()[:10],
                                  subject + ' · 真题年份待核对', 'materials', subject,
                                  '\n\n'.join(body),
                                  [p for e in entries for p in [e['sourcePage'], *e['answerSourcePages']]], sha,
                                  materialGroup='pending', recalledItems=entries))
    documents.sort(key=lambda d: (d['section'] != 'recalled',
                                  -(max(d['claimedYears']) if d['claimedYears'] else 0), d['title']))
    documents, bundles = merge_materials(documents, prefix='WZ-PACK-')
    school = dict(id=SCHOOL_ID, name='温州医科大学', shortName='温医大', mode='考研',
                  recalledTitle='历年真题',
                  note='历年真题来源：真题；科目讲义来源：人卫讲义。按年份整理并区分复试，资料包按科目合并；'
                       '能够明确配对的答案直接附在题目后。主观题不自动判分。',
                  documents=documents, materialBundles=bundles)
    assert_private(school, tokens)
    payload = json.loads(target.read_text()) if target.exists() else dict(schemaVersion=1, schools=[])
    payload['schools'] = [s for s in payload['schools'] if s['id'] != SCHOOL_ID] + [school]
    report = dict(schemaVersion=1, sourceSha256=sha, sourcePages=266,
                  excludedFrontMatterPages=[1, 2, 3], examSourcePages=EXAM_PAGES,
                  recalledItems=len(items), yearAssignedItems=sum(len(v) for v in by_year.values()),
                  uncertainYearItems=sum(len(v) for v in uncertain.values()),
                  years=sorted({y for y, _ in by_year}),
                  perYear={str(y): sum(len(v) for (yr, _), v in by_year.items() if yr == y)
                           for y in sorted({y for y, _ in by_year})},
                  subjectBundles=len(bundles), documents=len(documents),
                  originalAnswerEntries=len(answer_entries), pairedAnswerItems=paired_answers,
                  unpairedAnswerItems=len(items) - paired_answers,
                  sourceLabels=dict(papers='真题', subjectLectures='人卫讲义',
                                    uncertainYearPapers='真题'),
                  answerReview='原资料答案由用户确认正确；仅对明确配对的答案就题展示，不生成或猜测答案',
                  proofreading=dict(version=PROOFREAD_VERSION,
                                    sourceCorrections=sum(proofreading.values()),
                                    ruleCounts=dict(sorted(proofreading.items())),
                                    policy='限定温医大OCR文本；术语上下文和原页核对修正，不改考试年份或医学答案'),
                  privacy=dict(localOCROnly=True, publicOriginalPDF=False, publicImages=False,
                               frontMatterExcluded=True, headersRemoved=True,
                               privateIdentityGatePassed=True, privatePathsExcluded=True),
                  yearPolicy='只按题目旁年份归档；更新版次不作考试年份；不确定内容进入资料包。',
                  newScoredQuestions=0, medicalReview='按已核对原资料收录答案，保留扫描符号提示及来源页码')
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + '\n')
    package(target)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--private-ocr', type=Path, required=True)
    parser.add_argument('--source-pdf', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=ROOT / 'mobile/assets/school_library.json')
    parser.add_argument('--report', type=Path, default=ROOT / 'question-bank/考研/温州医科大学/整理报告.json')
    args = parser.parse_args()
    print(json.dumps(build(args.private_ocr, args.source_pdf, args.output, args.report), ensure_ascii=False, indent=2))

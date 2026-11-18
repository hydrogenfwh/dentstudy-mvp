"""Package audited postgraduate documents for reading, not scored practice.

No source documents, existing question IDs, or production state are changed.
Only document metadata/text are included; no clinical photos, videos or slides.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import unicodedata
from package_school_library import package

ROOT = Path(__file__).resolve().parents[1]
MATERIAL_GROUPS = {
    'terms': '名词与术语', 'qa': '简答与论述', 'exercises': '选择与综合练习',
    'notes': '讲义与复习笔记', 'course': '课程与期末试卷', 'pending': '待整理资料',
}


def material_group(document):
    if not document['text']:
        return 'pending'
    if document['courseSupplement']:
        return 'course'
    if document.get('materialGroup') in MATERIAL_GROUPS:
        return document['materialGroup']
    name = ' '.join(Path(p).stem for p in document['sourceFiles'])
    if any(word in name for word in ('名词', '名解')):
        return 'terms'
    if any(word in name for word in ('简答', '问答', '论述')) or '问答题（有答案）' in document['text'][:100]:
        return 'qa'
    if any(word in name for word in ('选择', '试题', '习题', '填空', '出题')) or re.search(r'\b[A-B][1-4](?:型题|\b)', name):
        return 'exercises'
    return 'notes'


def merge_materials(ordered, prefix='DL-PACK-'):
    """Deduplicate only complete identical text with compatible provenance.

    Never collapse similar stems, contradictory answers, or isolated paragraphs.
    Every original record ID and filename remains traceable.
    """
    kept, by_text = [], {}
    for document in ordered:
        document['mergedRecordIds'] = [document['id']]
        document['mergedStates'] = [document['state']]
        signature = None
        if document['section'] == 'materials' and document['text']:
            normalized = ' '.join(document['text'].split())
            signature = (document['subject'], document['courseSupplement'], normalized)
        if signature is not None and signature in by_text:
            original = by_text[signature]
            original['mergedRecordIds'].append(document['id'])
            original['mergedStates'] = sorted(set(original['mergedStates'] + [document['state']]))
            for cautious in ('needs_answer', 'needs_pairing', 'candidate'):
                if cautious in original['mergedStates']:
                    original['state'] = cautious
                    break
            original['sourceFiles'] = list(dict.fromkeys(original['sourceFiles'] + document['sourceFiles']))
            original['schoolEvidence'] = sorted(set(original['schoolEvidence'] + document['schoolEvidence']))
            continue
        if signature is not None:
            by_text[signature] = document
        kept.append(document)
    bundles = {}
    for document in kept:
        if document['section'] != 'materials':
            continue
        subject = document['subject']
        if subject in {'科目待核实', '综合/待逐题细分'}:
            subject = '综合资料'
        bundle = bundles.setdefault(subject, {'subject': subject, 'groups': {}})
        group = material_group(document)
        bundle['groups'].setdefault(group, []).append(document['id'])
    index = {d['id']: d for d in kept}
    result = []
    for subject, bundle in sorted(bundles.items(), key=lambda row: (row[0] == '综合资料', row[0])):
        groups = [{'id': key, 'title': title, 'documentIds': bundle['groups'][key]}
                  for key, title in MATERIAL_GROUPS.items() if key in bundle['groups']]
        ids = [i for group in groups for i in group['documentIds']]
        result.append({'id': prefix + hashlib.sha256(subject.encode()).hexdigest()[:12],
                       'subject': subject, 'groups': groups,
                       'sourceDocumentCount': sum(len(index[i]['mergedRecordIds']) for i in ids)})
    return kept, result


def clean(text):
    text = text.replace('\u2028', '\n').replace('\u2029', '\n').replace('\xa0', ' ')
    text = re.sub(r'【答疑编号\d+】', '', text)
    # Legacy Word icon-font codes do not identify a reliable Unicode character.
    # Make the uncertainty visible instead of guessing a tooth/occlusion symbol.
    text = ''.join('[原文特殊符号待核对]' if unicodedata.category(c) == 'Co' else c for c in text)
    text = ''.join(c for c in text if unicodedata.category(c) != 'Cc' or c in '\n\t')
    text = text.replace('❤', '♥')
    text = re.sub(r'(?m)^\s*(?:PAGE\s+\\\* MERGEFORMAT\s*\d*|HYPERLINK\s+"[^"]*")\s*$', '', text)
    return re.sub(r'\n{4,}', '\n\n\n', text).strip()


def title_of(path):
    name = Path(path).stem
    if re.fullmatch(r'[\d.]+', name):
        return Path(path).parent.name + ' · ' + name.strip('.')
    if name in {'选择题', '选择有答案', '选择无答案', '简答', '名词', '填空'} or name.startswith(('整理', '知识点')):
        return re.sub(r'^\d+', '', Path(path).parent.name) + ' · ' + name
    return name


def build(bench, target):
    registry = json.loads((bench / 'shared/source_registry.json').read_text())
    documents = {}
    for row in registry:
        if row['primaryMode'] != '考研' or row['state'] == 'media_reference':
            continue
        key = row['sourceId']
        if key in documents:
            documents[key]['sourceFiles'].append(row['relativePath'])
            continue
        section = 'recalled' if '真题' in Path(row['relativePath']).parts[:-1] else 'materials'
        text = ''
        if row.get('extractedText'):
            text = clean((bench / row['extractedText']).read_text())
        status = row['state']
        if status == 'needs_ocr' or status == 'needs_extraction':
            text = ''
        # Some old PDFs have individually positioned/duplicated glyphs. They
        # must be re-extracted with layout verification, not shown as gibberish.
        lines = [line.strip() for line in text.splitlines() if line.strip()]
        if row['extension'] == '.pdf' and lines and sum(len(line) <= 2 for line in lines) / len(lines) > .45:
            text = ''
            status = 'needs_cleanup'
        if row['extension'] == '.pdf' and len(re.findall(r'[\u0530-\u10ff\u1200-\u1cff]', text)) > 20:
            # Detected in a legacy custom-encoded PDF: its extracted "Chinese"
            # maps to thousands of unrelated script code points. Keep the file
            # in the index, but do not publish that text as a readable document.
            text = ''
            status = 'needs_cleanup'
        years = sorted({int(y) for y in re.findall(r'(?<!\d)(?:19\d{2}|20\d{2})(?!\d)', Path(row['relativePath']).name)}, reverse=True) if section == 'recalled' else []
        if section == 'recalled' and Path(row['relativePath']).name == '20年真题.pdf':
            years = [2020]  # Display hint from the source title, never verified provenance.
        documents[key] = {
            'id': key, 'title': title_of(row['relativePath']), 'section': section,
            'subject': row['subjectHint'], 'sourceFiles': [row['relativePath']],
            'sourceSha256': row['sha256'], 'state': status,
            'schoolEvidence': row['schoolEvidence'], 'claimedYears': years,
            'yearVerified': False, 'sourceVerified': False,
            'courseSupplement': row['branch'] == '本科期末与课程补充',
            'text': text, 'questionIds': [],
        }
    ordered = sorted(documents.values(), key=lambda d: (
        d['section'] != 'recalled', -(max(d['claimedYears']) if d['claimedYears'] else 0),
        d['subject'], d['title']))
    original_material_count = sum(d['section'] == 'materials' for d in ordered)
    ordered, bundles = merge_materials(ordered)
    payload = {'schemaVersion': 1, 'schools': [{
        'id': 'dalian-medical-university', 'name': '大连医科大学',
        'shortName': '大医', 'mode': '考研',
        'note': '历年题为回忆整理；资料包含本科课程及其他院校练习，保留各自来源，不代表官方试卷。',
        'documents': ordered,
        'materialBundles': bundles,
    }]}
    target.parent.mkdir(parents=True, exist_ok=True)
    # Rebuilding one school must never erase another school's delivery.
    if target.exists():
        existing = json.loads(target.read_text())
        payload['schools'].extend(s for s in existing['schools']
                                 if s['id'] != 'dalian-medical-university')
    target.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + '\n')
    package(target)
    return {'documents': len(ordered), 'sections': dict(Counter(d['section'] for d in ordered)),
            'originalMaterialDocuments': original_material_count, 'mergedMaterialBundles': len(bundles),
            'readableDocuments': sum(bool(d['text']) for d in ordered),
            'bytes': target.stat().st_size,
            'sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
            'newScoredQuestions': 0}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bench', type=Path, default=ROOT / 'output/bench')
    parser.add_argument('--output', type=Path, default=ROOT / 'mobile/assets/school_library.json')
    args = parser.parse_args()
    print(json.dumps(build(args.bench, args.output), ensure_ascii=False, indent=2))

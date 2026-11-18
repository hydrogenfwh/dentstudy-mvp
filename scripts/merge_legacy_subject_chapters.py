"""Add reviewed catalogue placement without rewriting source chapters/content.

The 123 anatomy items cover tooth morphology, eruption, dentitions and pulp
anatomy. The 100 prosthodontic items were reviewed individually, including
generic stems whose options identify removable dentures or pre-treatment.
Source paper/collection, citation chapter, order, IDs and all answers stay intact.
"""
import argparse
from collections import Counter
import copy
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
PLACEMENT = 'reviewed_legacy_topics_v1'
ANATOMY = '一、牙体解剖'
PROSTHO = {
    2: '第二章 临床接诊',
    4: '第四章 牙列缺损的固定局部义齿修复',
    5: '第五章 牙列缺损的可摘局部义齿修复',
    6: '第六章 牙列缺失的全口义齿修复',
}
PRE_TREATMENT = {441, 443, 451, 465, 468, 471, 476, 477, 479,
                 481, 482, 483, 485, 488, 500}
ASSIGNMENTS = {f'YS1000-{n:04d}': ANATOMY for n in range(1, 124)}
for n in range(401, 501):
    chapter = 2 if n in PRE_TREATMENT else 4 if 405 <= n <= 432 else 6 if n == 456 else 5
    ASSIGNMENTS[f'YS1000-{n:04d}'] = PROSTHO[chapter]

FILES = [
    ROOT / 'mobile/assets/all_questions.json',
    ROOT / 'question-bank/执医/口腔历年医考1000真题.json',
    ROOT / 'question-bank/执医/口腔历年医考1000真题/第01章 口腔解剖生理学.json',
    ROOT / 'question-bank/执医/口腔历年医考1000真题/第04章 口腔修复学.json',
]


def without_placement(question):
    return {k: v for k, v in question.items()
            if k not in ('chapterByMode', 'chapterAssignment')}


def apply_assignments(bank):
    result = copy.deepcopy(bank)
    for q in result['questions']:
        target = ASSIGNMENTS.get(q['id'])
        if target is None:
            continue
        expected = '口腔解剖生理学' if target == ANATOMY else '口腔修复学'
        if q['subject'] != expected or q['chapter'] != expected or q['modes'] != ['执医']:
            raise ValueError(f'Legacy source scope changed: {q["id"]}')
        previous = q.get('chapterByMode', {}).get('执医')
        if previous is not None and previous != target:
            raise ValueError(f'Conflicting chapter placement: {q["id"]}')
        if q.get('chapterAssignment') not in (None, PLACEMENT):
            raise ValueError(f'Conflicting assignment method: {q["id"]}')
        q['chapterByMode'] = {**q.get('chapterByMode', {}), '执医': target}
        q['chapterAssignment'] = PLACEMENT
    for before, after in zip(bank['questions'], result['questions']):
        if before['id'] in ASSIGNMENTS:
            assert without_placement(before) == without_placement(after)
        else:
            assert before == after
    return result


def main(check=False):
    prepared = []
    for path, expected in zip(FILES, [223, 223, 123, 100]):
        original = json.loads(path.read_text())
        selected = [q for q in original['questions'] if q['id'] in ASSIGNMENTS]
        if len(selected) != expected:
            raise ValueError(f'Unexpected source count in {path.name}')
        updated = apply_assignments(original)
        prepared.append((path, original, updated))
    if check:
        if any(before != after for _, before, after in prepared):
            raise ValueError('Catalogue placement not applied consistently')
        print('All 223 catalogue assignments are consistent in runtime and source JSON')
        return
    backup = ROOT / 'question-bank/backups/subject-chapter-merge-20261024'
    for path, before, after in prepared:
        if before != after:
            backup.mkdir(parents=True, exist_ok=True)
            destination = backup / path.name
            if not destination.exists():
                shutil.copy2(path, destination)
            path.write_text(json.dumps(after, ensure_ascii=False, indent=2) + '\n')
    counts = Counter(ASSIGNMENTS.values())
    report = dict(questions=223, anatomyQuestions=123, prosthodonticQuestions=100,
                  chapterCounts=dict(counts),
                  assignmentField='chapterByMode.执医',
                  unchanged='题目ID、题干、选项、答案、解析、来源、原资料章节、试卷/资料入口、学习方向和顺序均不变',
                  assignments=ASSIGNMENTS)
    (ROOT / 'question-bank/执医/既有题章节合并报告.json').write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: v for k, v in report.items() if k != 'assignments'}, ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    main(parser.parse_args().check)

"""Import user-provided oral histopathology exercise .doc files.

This importer shares the strict legacy-Word parser used for oral surgery:
each question must have a matching answer and explanation, and source-system
answer-ticket identifiers are removed before a question is written.
"""

from __future__ import annotations

import argparse
import copy
import json
import re
from collections import defaultdict
from pathlib import Path

from import_omfs_exercises import LICENSE, MODE, WARNING, _chapter_number, parse_document


ROOT = Path(__file__).resolve().parents[1]
SUBJECT = "口腔组织病理学"
COLLECTION = "口组病练习题"
SOURCE = "口组病练习题"
EXPECTED_CHAPTERS = 17

# The older 177-question archive contains no chapter metadata.  Its first
# forty questions cover cysts and tumours, so those entries are deliberately
# declared rather than guessed from their original sequence.  The remainder is
# matched against identical user-provided stems below.
LEGACY_CHAPTER_OVERRIDES = {
    **{number: 16 for number in (124, 126, 128, 131, 132, 133, 134, 137, 138,
                                  140, 141, 142, 146, 147, 148, 149, 150, 152,
                                  153, 155, 156, 157, 158, 159, 160, 161, 162,
                                  163)},
    **{number: 15 for number in (125, 127, 136, 139, 145, 151, 154)},
    **{number: 17 for number in (129, 130, 135, 143, 144)},
    **{number: 1 for number in (173, 197, 203, 219, 224, 241, 260, 298)},
    **{number: 6 for number in (190, 265, 279, 291)},
    **{number: 7 for number in (248,)},
    **{number: 14 for number in (177, 237, 272, 278, 294, 297)},
}


def _stem_key(value: str) -> str:
    return "".join(re.findall(r"[\u4e00-\u9fffA-Za-z0-9]", value)).lower()


def _legacy_number(question_id: str) -> int | None:
    match = re.fullmatch(r"YS1000-(\d{4})", question_id)
    return int(match.group(1)) if match else None


def build(source_dir: Path) -> dict:
    paths = sorted(source_dir.glob("*.doc"))
    if len(paths) != EXPECTED_CHAPTERS:
        raise ValueError(
            f"应提供 {EXPECTED_CHAPTERS} 个 .doc 文件，实际找到 {len(paths)} 个"
        )
    parsed = [parse_document(path) for path in paths]
    parsed.sort(key=lambda value: value[0])
    indexes = [item[0] for item in parsed]
    expected = list(range(1, EXPECTED_CHAPTERS + 1))
    if indexes != expected:
        raise ValueError(f"章节序号必须为 1–{EXPECTED_CHAPTERS}，实际为 {indexes}")

    questions: list[dict] = []
    for chapter_index, chapter, raw_questions in parsed:
        paper_id = f"oral-histo-exercise-{chapter_index:02d}"
        paper_name = f"{COLLECTION} · {chapter}"
        for local_order, raw in enumerate(raw_questions, 1):
            group = raw.get("groupId")
            suffix = (
                f"{raw['groupId'].split('-')[-1]}-{local_order:03d}"
                if group
                else f"{local_order:03d}"
            )
            question = {
                "id": f"ORAL-HISTO-EX-{chapter_index:02d}-{suffix}",
                "subject": SUBJECT,
                "chapter": chapter,
                "type": raw["type"],
                "stem": raw["stem"],
                "options": raw["options"],
                "answer": raw["answer"],
                "rubric": None,
                "explanation": raw["explanation"],
                "warning": WARNING,
                "reference": f"{SOURCE} · {chapter}",
                "citation": {
                    "verified": False,
                    "publisher": None,
                    "title": SOURCE,
                    "edition": None,
                    "chapter": chapter,
                    "page": None,
                },
                "tags": ["执医", SUBJECT, COLLECTION],
                "topics": raw["topics"],
                "modes": [MODE],
                "school": None,
                "year": None,
                "paperId": paper_id,
                "paperName": paper_name,
                "collection": COLLECTION,
                "durationMinutes": 90,
                "order": local_order,
                "points": 1,
                "isDemo": False,
                "reviewStatus": "draft",
                "sourceType": "mock",
                "examProvenance": {
                    "yearVerified": False,
                    "sourceVerified": False,
                },
                "license": LICENSE,
            }
            if group:
                question["groupId"] = (
                    f"oral-histo-ex-{chapter_index:02d}-"
                    f"{raw['type'].lower()}-{raw['groupId']}"
                )
                question["sharedStem"] = raw["sharedStem"]
            questions.append(question)

    return {
        "version": 1,
        "name": "执医 · 口组病练习题",
        "isDemo": False,
        "sourceDocument": "用户提供的 17 份口组病练习题 .doc 文件",
        "sourceNote": "十七章口腔组织病理学练习题；题目、答案及解析从用户提供资料逐项提取。",
        "questions": questions,
    }


def merge_into_app(bank: dict, app_bank: Path, backup: Path) -> dict:
    """Append the new bank and chapter-classify the unchanged older archive."""
    app = json.loads(app_bank.read_text(encoding="utf-8"))
    if not isinstance(app.get("questions"), list):
        raise ValueError(f"{app_bank}: 缺少 questions 数组")
    questions = copy.deepcopy(app["questions"])
    incoming_ids = {question["id"] for question in bank["questions"]}
    collision = sorted({question.get("id") for question in questions} & incoming_ids)
    if collision:
        raise ValueError(f"App 已含本次导入题目，拒绝覆盖：{collision[:5]}")
    if backup.exists():
        raise FileExistsError(f"备份已存在，拒绝覆盖：{backup}")

    chapter_by_index = {
        _chapter_number(question["chapter"]): question["chapter"]
        for question in bank["questions"]
    }
    source_chapters: dict[str, set[int]] = defaultdict(set)
    for question in bank["questions"]:
        source_chapters[_stem_key(question["stem"])].add(
            _chapter_number(question["chapter"])
        )

    migrated = 0
    for question in questions:
        if question.get("paperId") != "zhiyi-1000-02":
            continue
        number = _legacy_number(question.get("id", ""))
        if number is None:
            raise ValueError(f"旧口组病题号格式异常：{question.get('id')}")
        chapter_index = LEGACY_CHAPTER_OVERRIDES.get(number)
        if chapter_index is None:
            matches = source_chapters.get(_stem_key(question["stem"]), set())
            if len(matches) != 1:
                raise ValueError(
                    f"旧口组病题无法唯一归章：{question.get('id')}，匹配章节 {sorted(matches)}"
                )
            chapter_index = next(iter(matches))
        chapter = chapter_by_index[chapter_index]
        # Deliberately retain paperId, paperName, collection and provenance:
        # this changes only the practice chapter, not the material source.
        question.update({"chapter": chapter, "sourceChapter": chapter})
        migrated += 1

    if migrated != 177:
        raise ValueError(f"应归入章节的既有口组病题应为 177 道，实际为 {migrated} 道")
    backup.parent.mkdir(parents=True, exist_ok=True)
    backup.write_text(
        json.dumps(app, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    app["questions"] = [*questions, *bank["questions"]]
    app_bank.write_text(
        json.dumps(app, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return {
        "newQuestions": len(bank["questions"]),
        "totalQuestions": len(app["questions"]),
        "migratedExistingArchiveQuestions": migrated,
        "backup": str(backup),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_dir", type=Path, help="包含 17 个 .doc 文件的目录")
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT / "question-bank" / "执医" / f"{COLLECTION}.json",
    )
    parser.add_argument(
        "--app-bank",
        type=Path,
        help="同时合并到 App 题库；会先创建一次性备份",
    )
    parser.add_argument(
        "--backup",
        type=Path,
        default=ROOT
        / "question-bank"
        / "backups"
        / "all_questions-before-oral-histo-exercises.json",
        help="--app-bank 时使用的备份路径（已存在则拒绝覆盖）",
    )
    args = parser.parse_args()
    bank = build(args.source_dir)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(bank, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"已生成 {args.output}：{len(bank['questions'])} 道题，17 个章节")
    if args.app_bank:
        summary = merge_into_app(bank, args.app_bank, args.backup)
        print("已合并 App 题库：" + json.dumps(summary, ensure_ascii=False))


if __name__ == "__main__":
    main()

"""Import user-provided oral-maxillofacial surgery exercise .doc files.

The legacy Word files contain question sections followed by an answer section.
This converter deliberately keeps the source outside the repository: pass the
directory containing the fourteen ``.doc`` files at run time.  It uses macOS
``textutil`` when available (and ``antiword`` as a fallback), removes only the
source-system answer-ticket identifiers, and fails closed when a question does
not have a matching answer and explanation.
"""

from __future__ import annotations

import argparse
import copy
import json
import re
import shutil
import subprocess
from collections import defaultdict
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parents[1]
SUBJECT = "口腔颌面外科学"
MODE = "执医"
COLLECTION = "口外练习题"
SOURCE = "口外练习题"
WARNING = "题目及解析整理自用户提供的口外练习题；请结合最新版教材、课程与专业教师意见核对。"
LICENSE = "用户提供学习资料；仅供学习使用，公开传播前须核实著作权授权与医学审核。"
ANSWER_MARKER = "答案部分"

# The existing 100 oral-surgery questions from the earlier unverified archive
# have no chapter metadata.  These ranges were classified from their actual
# stems, not from their original question order alone.  They are deliberately
# declared here so the reassignment remains reviewable and repeatable.
LEGACY_ARCHIVE_CHAPTERS = (
    (301, 320, 8), (321, 340, 2), (341, 342, 7), (343, 358, 1),
    (359, 359, 8), (360, 361, 7), (362, 362, 1), (363, 365, 7),
    (366, 367, 1), (368, 371, 7), (372, 373, 1), (374, 375, 7),
    (376, 377, 1), (378, 378, 7), (379, 379, 1), (380, 380, 7),
    (381, 382, 1), (383, 385, 7), (386, 386, 1), (387, 390, 7),
    (391, 391, 1), (392, 392, 7), (393, 394, 1), (395, 398, 7),
    (399, 400, 1),
)

# The existing Jin Yingjie 100-question mock paper is ordered by its source
# chapters.  Keep its source/paper metadata intact while exposing each item in
# the same chapter it belongs to for subject practice.
JYJ_CHAPTERS = (
    (1, 6, 1), (7, 8, 8), (9, 9, 6), (10, 10, 8),
    (11, 15, 2), (16, 20, 3), (21, 22, 4), (23, 30, 5),
    (31, 40, 6), (41, 51, 7), (52, 56, 8), (57, 60, 9),
    (61, 65, 10), (66, 70, 11), (71, 78, 12), (79, 79, 13),
    (80, 80, 14), (81, 85, 2), (86, 90, 3), (91, 94, 8),
    (95, 96, 10), (97, 98, 11), (99, 100, 1),
)

CHINESE_NUMBERS = {
    "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7,
    "八": 8, "九": 9, "十": 10, "十一": 11, "十二": 12, "十三": 13,
    "十四": 14, "十五": 15, "十六": 16, "十七": 17,
}
SECTION_RE = re.compile(r"(?m)^\s*([一二三四五六七八九十]+)、\s*(A1|A2|A3/A4|B)\s*$")
NUMBER_RE = re.compile(r"(?m)^\s*(\d+)、\s*(.*)$")
SUB_RE = re.compile(r"(?m)^\s*<(\d+)>\s*、?\s*(.*)$")
OPTION_RE = re.compile(r"^\s*([A-E])[、.．:：]\s*(.*)$")
ANSWER_RE = re.compile(r"【正确答案】\s*([A-E])")
EXPLANATION_RE = re.compile(
    r"【答案解析】\s*(.*?)(?=【(?:该题针对|答疑编号|正确答案|答案解析)|\Z)", re.S
)
TICKET_RE = re.compile(r"【答疑编号\d+】\s*")
KNOWLEDGE_RE = re.compile(r"【该题针对[“\"]?(.*?)[”\"]?知识点进行考核】")


def _clean(value: str) -> str:
    value = TICKET_RE.sub("", value)
    value = value.replace("\u2028", "\n").replace("\xa0", " ").replace("\ufeff", "")
    value = re.sub(r"[ \t]+", " ", value)
    value = re.sub(r" *\n *", "\n", value)
    value = re.sub(r"\n{3,}", "\n\n", value)
    return value.strip()


def _doc_text(path: Path) -> str:
    if shutil.which("textutil"):
        command = ["textutil", "-convert", "txt", "-stdout", str(path)]
    elif shutil.which("antiword"):
        command = ["antiword", str(path)]
    else:
        raise RuntimeError("需要 macOS textutil 或 antiword 才能读取旧版 .doc 文件")
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    if result.returncode != 0 or not result.stdout.strip():
        raise RuntimeError(f"无法读取 {path.name}: {result.stderr.strip() or '无文本输出'}")
    return _clean(result.stdout)


def _split_sections(text: str) -> dict[str, str]:
    sections: dict[str, str] = {}
    matches = list(SECTION_RE.finditer(text))
    for index, match in enumerate(matches):
        raw_type = match.group(2)
        question_type = "A3" if raw_type == "A3/A4" else raw_type
        if question_type in sections:
            raise ValueError(f"题型 {question_type} 在同一部分重复出现")
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        sections[question_type] = text[match.end():end].strip()
    return sections


def _split_numbered(text: str, *, sub: bool = False) -> list[tuple[int, str]]:
    matcher = SUB_RE if sub else NUMBER_RE
    matches = list(matcher.finditer(text))
    values: list[tuple[int, str]] = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        values.append((int(match.group(1)), _clean(match.group(2) + "\n" + text[match.end():end])))
    return values


def _parse_simple_questions(text: str) -> dict[tuple[int, int], dict]:
    result: dict[tuple[int, int], dict] = {}
    for number, block in _split_numbered(text):
        lines = block.splitlines()
        stem: list[str] = []
        options: dict[str, list[str]] = {}
        current: list[str] | None = stem
        for line in lines:
            option = OPTION_RE.match(line)
            if option:
                current = options.setdefault(option.group(1), [])
                current.append(option.group(2))
            elif current is not None:
                current.append(line)
        if set(options) != set("ABCDE"):
            raise ValueError(f"第 {number} 题选项不完整：{sorted(options)}")
        result[(number, 0)] = {
            "stem": _clean("\n".join(stem)),
            "options": {key: _clean("\n".join(value)) for key, value in options.items()},
        }
    return result


def _parse_group_questions(text: str, question_type: str) -> dict[tuple[int, int], dict]:
    result: dict[tuple[int, int], dict] = {}
    for group, block in _split_numbered(text):
        items = _split_numbered(block, sub=True)
        if not items:
            raise ValueError(f"共用题组 {group} 没有子题")
        first = re.search(r"(?m)^\s*<\d+>", block)
        assert first is not None
        header = block[:first.start()].strip()
        if question_type == "B":
            lines = header.splitlines()
            options: dict[str, list[str]] = {}
            shared: list[str] = []
            current: list[str] | None = None
            after_options = False
            for line in lines:
                option = OPTION_RE.match(line)
                if option:
                    current = options.setdefault(option.group(1), [])
                    current.append(option.group(2))
                elif len(options) == 5:
                    after_options = True
                    shared.append(line)
                elif current is not None:
                    current.append(line)
            if set(options) != set("ABCDE"):
                raise ValueError(f"B 型题组 {group} 选项不完整：{sorted(options)}")
            shared_stem = _clean("\n".join(shared))
            if not shared_stem:
                shared_stem = "请为下列题目选择最合适的答案。"
            common_options = {key: _clean("\n".join(value)) for key, value in options.items()}
        else:
            shared_stem = _clean(header)
            common_options = None
            if not shared_stem:
                raise ValueError(f"A3/A4 题组 {group} 缺少共用题干")
        for sub_number, item in items:
            if question_type == "B":
                stem = _clean(re.sub(r"(?m)^\s*A B C D E\s*$", "", item))
                options = common_options
            else:
                parsed = _parse_simple_questions(f"1、{item}")[(1, 0)]
                stem, options = parsed["stem"], parsed["options"]
            if not stem:
                raise ValueError(f"题组 {group} 第 {sub_number} 小题缺少题干")
            result[(group, sub_number)] = {
                "stem": stem,
                "options": options,
                "groupId": f"group-{group:03d}",
                "sharedStem": shared_stem,
            }
    return result


def _explanation(block: str) -> tuple[str, list[str]]:
    answer = ANSWER_RE.search(block)
    if not answer:
        raise ValueError("答案区缺少正确答案")
    parts = [_clean(value) for value in EXPLANATION_RE.findall(block)]
    parts = [value for value in parts if value]
    if not parts:
        raise ValueError("答案区缺少答案解析")
    topics = [_clean(value) for value in KNOWLEDGE_RE.findall(block)]
    return answer.group(1), topics


def _parse_answers(text: str, question_type: str) -> dict[tuple[int, int], tuple[str, str, list[str]]]:
    values: dict[tuple[int, int], tuple[str, str, list[str]]] = {}
    grouped = question_type in {"A3", "B"}
    for number, block in _split_numbered(text):
        if grouped:
            answer_items = _split_numbered(block, sub=True)
            if not answer_items:
                raise ValueError(f"答案区题组 {number} 没有子题")
        else:
            answer_items = [(0, block)]
        for sub_number, item in answer_items:
            answer, topics = _explanation(item)
            explanations = [_clean(value) for value in EXPLANATION_RE.findall(item)]
            key = (number, sub_number)
            if key in values:
                raise ValueError(f"答案区重复：{key}")
            values[key] = (answer, "\n\n".join(explanations), topics)
    return values


def _chapter_number(title: str) -> int:
    match = re.match(r"\s*([一二三四五六七八九十]+)、", title)
    if not match or match.group(1) not in CHINESE_NUMBERS:
        raise ValueError(f"无法从章节标题读取序号：{title!r}")
    return CHINESE_NUMBERS[match.group(1)]


def parse_document(path: Path) -> tuple[int, str, list[dict]]:
    text = _doc_text(path)
    if ANSWER_MARKER not in text:
        raise ValueError(f"{path.name}: 找不到答案部分")
    question_text, answer_text = text.split(ANSWER_MARKER, 1)
    chapter_match = re.match(r"\s*(.+?)\s*\n", question_text)
    if not chapter_match:
        raise ValueError(f"{path.name}: 找不到章节标题")
    chapter = _clean(chapter_match.group(1))
    index = _chapter_number(chapter)
    question_sections = _split_sections(question_text)
    answer_sections = _split_sections(answer_text)
    if set(question_sections) != set(answer_sections):
        raise ValueError(
            f"{path.name}: 题目/答案题型不一致：{sorted(question_sections)} != {sorted(answer_sections)}"
        )
    questions: list[dict] = []
    for question_type, section in question_sections.items():
        parsed = (
            _parse_group_questions(section, question_type)
            if question_type in {"A3", "B"}
            else _parse_simple_questions(section)
        )
        answers = _parse_answers(answer_sections[question_type], question_type)
        if set(parsed) != set(answers):
            only_questions = sorted(set(parsed) - set(answers))[:10]
            only_answers = sorted(set(answers) - set(parsed))[:10]
            raise ValueError(
                f"{path.name} {question_type}: 题目/答案编号不一致；"
                f"仅题目 {only_questions}，仅答案 {only_answers}"
            )
        for key, item in parsed.items():
            answer, explanation, topics = answers[key]
            if answer not in item["options"]:
                raise ValueError(f"{path.name} {question_type} {key}: 答案不在选项内")
            item.update({
                "type": question_type,
                "answer": answer,
                "explanation": explanation,
                "topics": topics,
            })
            questions.append(item)
    return index, chapter, questions


def build(source_dir: Path) -> dict:
    paths = sorted(source_dir.glob("*.doc"))
    if len(paths) != 14:
        raise ValueError(f"应提供 14 个 .doc 文件，实际找到 {len(paths)} 个")
    parsed = [parse_document(path) for path in paths]
    parsed.sort(key=lambda value: value[0])
    indexes = [item[0] for item in parsed]
    if indexes != list(range(1, 15)):
        raise ValueError(f"章节序号必须为 1–14，实际为 {indexes}")
    questions: list[dict] = []
    for chapter_index, chapter, raw_questions in parsed:
        paper_id = f"omfs-exercise-{chapter_index:02d}"
        paper_name = f"{COLLECTION} · {chapter}"
        for local_order, raw in enumerate(raw_questions, 1):
            group = raw.get("groupId")
            suffix = (
                f"{raw['groupId'].split('-')[-1]}-{local_order:03d}"
                if group else f"{local_order:03d}"
            )
            question = {
                "id": f"OMFS-EX-{chapter_index:02d}-{suffix}",
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
                "tags": ["执医", "口腔颌面外科学", "口外练习题"],
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
                "examProvenance": {"yearVerified": False, "sourceVerified": False},
                "license": LICENSE,
            }
            if group:
                question["groupId"] = (
                    f"omfs-ex-{chapter_index:02d}-{raw['type'].lower()}-{raw['groupId']}"
                )
                question["sharedStem"] = raw["sharedStem"]
            questions.append(question)
    return {
        "version": 1,
        "name": "执医 · 口外练习题",
        "isDemo": False,
        "sourceDocument": "用户提供的 14 份口外练习题 .doc 文件",
        "sourceNote": "十四章口腔颌面外科学练习题；题目、答案及解析从用户提供资料逐项提取。",
        "questions": questions,
    }


def _legacy_archive_chapter(question_id: str) -> int | None:
    match = re.fullmatch(r"YS1000-(\d{4})", question_id)
    if not match:
        return None
    number = int(match.group(1))
    for start, end, chapter in LEGACY_ARCHIVE_CHAPTERS:
        if start <= number <= end:
            return chapter
    return None


def _jyj_chapter(question_id: str) -> int | None:
    match = re.fullmatch(r"JYJ100-(\d{4})", question_id)
    if not match:
        return None
    number = int(match.group(1))
    for start, end, chapter in JYJ_CHAPTERS:
        if start <= number <= end:
            return chapter
    return None


def merge_into_app(bank: dict, app_bank: Path, backup: Path) -> dict:
    """Add the new source bank and place earlier oral-surgery archives by chapter."""
    app = json.loads(app_bank.read_text(encoding="utf-8"))
    if not isinstance(app.get("questions"), list):
        raise ValueError(f"{app_bank}: 缺少 questions 数组")
    questions = copy.deepcopy(app["questions"])
    ids = {q.get("id") for q in questions}
    incoming_ids = {q["id"] for q in bank["questions"]}
    collision = sorted(ids & incoming_ids)
    if collision:
        raise ValueError(f"App 已含本次导入题目，拒绝覆盖：{collision[:5]}")
    if backup.exists():
        raise FileExistsError(f"备份已存在，拒绝覆盖：{backup}")

    chapter_by_index = {
        _chapter_number(q["chapter"]): q["chapter"] for q in bank["questions"]
    }
    migrated_archive = 0
    renamed_jyj = 0
    for question in questions:
        target = (
            _legacy_archive_chapter(question.get("id", ""))
            if question.get("paperId") == "zhiyi-1000-03" else None
        )
        if target is not None:
            chapter = chapter_by_index[target]
            question.update({
                "chapter": chapter,
                "paperId": f"omfs-exercise-{target:02d}",
                "paperName": f"{COLLECTION} · {chapter}",
                "collection": COLLECTION,
                "sourceChapter": chapter,
            })
            migrated_archive += 1
        elif question.get("paperId") == "jyj-100":
            chapter_index = _jyj_chapter(question.get("id", ""))
            if chapter_index is None:
                raise ValueError(f"金英杰口外题缺少章节映射：{question.get('id')}")
            # Keep this separate 100-question mock set and its source category,
            # while also placing every question in its subject chapter.
            question.update({
                "chapter": chapter_by_index[chapter_index],
                "sourceChapter": chapter_by_index[chapter_index],
                "paperId": "jyj-omfs-100",
                "paperName": "金英杰口外模拟题",
                "collection": "金英杰口外模拟题",
            })
            renamed_jyj += 1
    if migrated_archive != 100:
        raise ValueError(f"应归入章节的既有口外题应为 100 道，实际为 {migrated_archive} 道")
    if renamed_jyj != 100:
        raise ValueError(f"应改名的金英杰口外模拟题应为 100 道，实际为 {renamed_jyj} 道")

    backup.parent.mkdir(parents=True, exist_ok=True)
    backup.write_text(json.dumps(app, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    app["questions"] = [*questions, *bank["questions"]]
    app_bank.write_text(json.dumps(app, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return {
        "newQuestions": len(bank["questions"]),
        "totalQuestions": len(app["questions"]),
        "migratedExistingArchiveQuestions": migrated_archive,
        "renamedJyjQuestions": renamed_jyj,
        "backup": str(backup),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_dir", type=Path, help="包含 14 个 .doc 文件的目录")
    parser.add_argument(
        "--output", type=Path,
        default=ROOT / "question-bank" / "执医" / f"{COLLECTION}.json",
    )
    parser.add_argument(
        "--app-bank", type=Path,
        help="同时合并到 App 题库；会先创建一次性备份",
    )
    parser.add_argument(
        "--backup", type=Path,
        default=ROOT / "question-bank" / "backups" / "all_questions-before-omfs-exercises.json",
        help="--app-bank 时使用的备份路径（已存在则拒绝覆盖）",
    )
    args = parser.parse_args()
    bank = build(args.source_dir)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(bank, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"已生成 {args.output}：{len(bank['questions'])} 道题，14 个章节")
    if args.app_bank:
        summary = merge_into_app(bank, args.app_bank, args.backup)
        print("已合并 App 题库：" + json.dumps(summary, ensure_ascii=False))


if __name__ == "__main__":
    main()

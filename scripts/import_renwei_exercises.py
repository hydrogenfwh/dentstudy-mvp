"""Reproducibly import the user's two Word collections as 人卫练习题.

Never infer an answer or explanation. Parse source answer keys, preserve shared
stems/options, deduplicate identical content, and retain rejected records in an
audit report so malformed source items cannot silently enter practice.
"""
from __future__ import annotations

import argparse
from collections import Counter
import copy
import hashlib
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET
import zipfile
from renwei_chapters import classify, chapters_by_mode

ROOT = Path(__file__).resolve().parents[1]
COLLECTION = "人卫练习题"
MISSING_EXPLANATION = "原资料未提供解析。"
NUMBER = re.compile(r"(?m)^[ \t]*(\d+)[.．、][ \t]*(.*)$")
OPTION = re.compile(r"^[ \t]*([A-H])[.．、:：][ \t]*(.*)$")
ANSWER = re.compile(r"正确答案[ \t]*[:：][ \t]*([^\n]*)")
GROUP = re.compile(r"[（(]\s*(\d+)\s*[-—–～~至]\s*(\d+)\s*题共用([^）)]+)[）)]")
DOCX_GROUP = re.compile(r"[（(]\s*(\d+)\s*[-—–～~至]\s*(\d+)\s*(?:[）)]\s*共用(备选答案|题干)|共用(备选答案|题干)[）)])")
SECTION = re.compile(r"(?m)^口腔[^\n(（]{1,30}[（(]([AB][1-4])型题(\d*)[）)][^\n]*")
NOISE = re.compile(r"(?m)^.*(?:显示答案\s+收藏本题|星级评定\s+错误反馈).*$")
IMAGE = re.compile(r"⟦RWIMG:([^⟧]+)⟧")
IMAGE_DIR = ROOT / "mobile/assets/question_images/renwei"


def clean(text: str) -> str:
    text = text.replace("\u2028", "\n").replace("\u2029", "\n").replace("\xa0", " ")
    text = re.sub(r"【答疑编号\d+】", "", text)
    text = NOISE.sub("", text)
    return text.strip()


def normalized(text: str) -> str:
    return re.sub(r"\s+", "", text).replace("．", ".").replace("，", ",")


def read_document(path: Path) -> str:
    if path.suffix.lower() == ".docx":
        namespaces = {
            "w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
            "a": "http://schemas.openxmlformats.org/drawingml/2006/main",
            "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
            "v": "urn:schemas-microsoft-com:vml",
        }
        with zipfile.ZipFile(path) as archive:
            document = ET.fromstring(archive.read("word/document.xml"))
            rels = ET.fromstring(archive.read("word/_rels/document.xml.rels"))
            targets = {rel.attrib["Id"]: rel.attrib.get("Target", "") for rel in rels}
            lines = []
            for paragraph in document.iter("{" + namespaces["w"] + "}p"):
                values = []
                for node in paragraph.iter():
                    if node.tag == "{" + namespaces["w"] + "}t":
                        values.append(node.text or "")
                    elif node.tag == "{" + namespaces["w"] + "}tab":
                        values.append("\t")
                    elif node.tag == "{" + namespaces["w"] + "}br":
                        values.append("\n")
                    elif node.tag in {"{" + namespaces["a"] + "}blip", "{" + namespaces["v"] + "}imagedata"}:
                        rid = node.attrib.get("{" + namespaces["r"] + "}embed") or node.attrib.get("{" + namespaces["r"] + "}id")
                        target = targets.get(rid, "")
                        if not target or "media/" not in target:
                            continue
                        data = archive.read("word/" + target)
                        name = hashlib.sha256(data).hexdigest()[:24] + Path(target).suffix.lower()
                        IMAGE_DIR.mkdir(parents=True, exist_ok=True)
                        (IMAGE_DIR / name).write_bytes(data)
                        values.append(f"⟦RWIMG:assets/question_images/renwei/{name}⟧")
                lines.append("".join(values))
            return clean("\n".join(lines))
    return clean(subprocess.check_output(
        ["textutil", "-convert", "txt", "-stdout", str(path)], text=True
    ))


def options_and_stem(text: str) -> tuple[str, dict[str, str]]:
    stem: list[str] = []
    options: dict[str, list[str]] = {}
    current = stem
    for line in text.splitlines():
        line = line.strip()
        match = OPTION.match(line)
        if not match:
            # A few source labels omit punctuation, e.g. C口腔内存在异种金属.
            loose = re.match(r"^([B-H])(?=[\u4e00-\u9fff])(.+)$", line)
            if not loose:
                loose = re.match(r"^([F-H])(?=[A-Za-z])(.+)$", line)
            if loose and chr(ord(loose[1]) - 1) in options:
                match = loose
        if match:
            key, value = match.groups()
            if key in options:
                # Some source items repeat A．A ... E．E after full options.
                if value == key or not value:
                    current = []
                    continue
                raise ValueError(f"选项 {key} 重复")
            current = options.setdefault(key, [])
            current.append(value)
        else:
            current.append(line)
    return clean("\n".join(stem)), {
        key: clean("\n".join(lines)) for key, lines in options.items()
    }


def validated(item: dict) -> dict:
    if not item["stem"].strip():
        raise ValueError("缺少题干")
    opts = item["options"]
    if len(opts) < 2 or any(not value.strip() for value in opts.values()):
        raise ValueError("选项缺失或为空")
    if list(opts) != list("ABCDEFGH"[:len(opts)]):
        raise ValueError(f"选项序号不连续：{list(opts)}")
    answer = item["answer"]
    if not answer or len(set(answer)) != len(answer) or any(a not in opts for a in answer):
        raise ValueError(f"答案 {answer!r} 不属于选项 {list(opts)}")
    if re.search(r"正确答案\s*[:：]", item["stem"]):
        raise ValueError("答案标记混入题干")
    return item


def parse_unit(content: str, answer_text: str, section_type: str,
               explanation: str = "") -> list[dict]:
    content = clean(content)
    content = re.sub(r"(?m)^[一二三四五六七八九十]+、[AB][1-4]型题[:：]?\s*$", "", content)
    group_match = GROUP.search(content)
    common = ""
    if group_match:
        content = content[group_match.end():].strip()
    matches = list(NUMBER.finditer(content))
    if not matches:
        raise ValueError("找不到题号")
    prefix = content[:matches[0].start()].strip()
    common_options: dict[str, str] = {}
    if prefix:
        common, common_options = options_and_stem(prefix)
    if section_type in {"A3", "A4"} and not common:
        raise ValueError("原文题组缺少共用题干")
    mapped_answers = {
        int(number): value
        for number, value in re.findall(r"(\d+)[.．、]\s*([A-H]+)", answer_text)
    }
    if not mapped_answers:
        answer = re.match(r"([A-H]+)", answer_text)
        if not answer or len(matches) != 1:
            raise ValueError(f"答案和题号无法对应：{answer_text}")
        mapped_answers[int(matches[0].group(1))] = answer.group(1)
    numbers = [int(match.group(1)) for match in matches]
    if len(set(numbers)) != len(numbers) or set(mapped_answers) != set(numbers):
        raise ValueError(f"题号 {numbers} 与答案题号 {list(mapped_answers)} 不一致")
    if group_match and (numbers[0] != int(group_match[1]) or numbers[-1] != int(group_match[2])):
        raise ValueError(f"题组范围 {group_match[0]} 与子题范围 {numbers} 不一致")

    result: list[dict] = []
    for i, match in enumerate(matches):
        end = matches[i + 1].start() if i + 1 < len(matches) else len(content)
        stem, options = options_and_stem(match.group(2) + "\n" + content[match.end():end])
        number = int(match.group(1))
        question_type = "B" if section_type == "B1" else section_type
        if not options:
            options = common_options
            if not options:
                raise ValueError(f"第 {number} 题没有选项")
        answer = mapped_answers[number]
        if len(answer) > 1:
            question_type = "多选题"
        item = {
            "stem": stem, "options": options, "answer": "".join(sorted(answer)),
            "type": question_type, "sharedStem": common, "explanation": explanation,
            "sourceNumber": number,
        }
        if question_type == "B" and not common:
            item["sharedStem"] = "共用备选答案"
        result.append(validated(item))
    return result


def parse_document(path: Path, relative: str) -> tuple[list[dict], list[dict], int]:
    text = read_document(path)
    sections = list(SECTION.finditer(text))
    records, rejected = [], []
    expected = 0
    if sections:
        units = [
            (match.group(1), match.group(0).splitlines()[0],
             text[match.end():sections[i + 1].start() if i + 1 < len(sections) else len(text)])
            for i, match in enumerate(sections)
        ]
    else:
        units = [("A1", path.stem, text)]
    for kind, section, source in units:
        answers = list(ANSWER.finditer(source))
        docx_groups = []
        if not sections:
            for group in DOCX_GROUP.finditer(source):
                following = NUMBER.search(source, group.end())
                if following:
                    docx_groups.append((
                        int(group[1]), int(group[2]),
                        "B1" if (group[3] or group[4]) == "备选答案" else "A3",
                        source[group.end():following.start()].strip(),
                    ))
        start = 0
        for answer_index, answer in enumerate(answers):
            content = source[start:answer.start()]
            explanation = ""
            if not sections:
                # DOCX files have one answer per item and optional explanations.
                # A numbered line inside an explanation is not a new question:
                # the next item's number is always the next source number.
                number = answer_index + 1
                candidates = [m for m in NUMBER.finditer(content) if int(m.group(1)) == number]
                if candidates:
                    content = content[candidates[-1].start():]
                for first, last, group_kind, prefix in docx_groups:
                    if first <= number <= last:
                        content = prefix + "\n" + content
                        kind = group_kind
                        break
                else:
                    kind = "A2" if re.match(r"(?:患者|男性|女性|男[，,]|女[，,]|患儿)", content.split(".", 1)[-1].lstrip()) else "A1"
                next_end = answers[answer_index + 1].start() if answer_index + 1 < len(answers) else len(source)
                tail = source[answer.end():next_end]
                next_questions = [m for m in NUMBER.finditer(tail) if int(m.group(1)) == number + 1]
                if next_questions:
                    tail = tail[:next_questions[0].start()]
                next_group = DOCX_GROUP.search(tail)
                if next_group:
                    tail = tail[:next_group.start()]
                exp = re.search(r"(?:答案)?解析\s*[:：]\s*(.*)", tail, re.S)
                if exp:
                    explanation = clean(exp.group(1))
            start = answer.end()
            answer_value = re.sub(r"学生答案[:：].*", "", answer.group(1)).strip()
            numbered_answers = re.findall(r"\d+[.．、]\s*[A-H]+", answer_value)
            expected += len(numbered_answers) if numbered_answers else 1
            try:
                items = parse_unit(content, answer_value, kind, explanation)
                for item in items:
                    item.update({"sourceFile": relative, "sourceSection": section})
                    records.append(item)
            except ValueError as error:
                rejected.append({
                    "sourceFile": relative, "sourceSection": section,
                    "answer": answer_value, "reason": str(error), "content": clean(content),
                    "questionCount": len(numbered_answers) if numbered_answers else 1,
                })
    return records, rejected, expected


def source_subject(relative: str) -> str:
    if relative.startswith("口腔一类/"):
        return re.sub(r"\.\d+页$", "", Path(relative).stem)
    subject = relative.split("/")[1]
    return {"口组病": "口腔组织病理学", "牙合学": "𬌗学"}.get(subject, subject)


def content_key(item: dict) -> str:
    return json.dumps(
        [normalized(item["stem"]), normalized(item.get("sharedStem", "")),
         [(k, normalized(v)) for k, v in item["options"].items()]],
        ensure_ascii=False, separators=(",", ":"),
    )


def build(source_dir: Path) -> tuple[dict, dict]:
    records, rejected, files = [], [], []
    for path in sorted(source_dir.rglob("*")):
        if path.suffix.lower() not in {".doc", ".docx"} or path.name.startswith("~$"):
            continue
        relative = str(path.relative_to(source_dir))
        parsed, errors, expected = parse_document(path, relative)
        accepted = 0
        for item in parsed:
            item["subject"] = source_subject(relative)
            # These documents refer to figures but contain no embedded media.
            # Without the original illustration they cannot be answered fairly.
            image_text = item["stem"] + item.get("sharedStem", "")
            if re.search(r"此图|下图|如图|见图|该图|上图|图示|图中所示", image_text) and not IMAGE.search(image_text):
                errors.append({
                    "sourceFile": relative, "sourceSection": item["sourceSection"],
                    "sourceNumber": item["sourceNumber"], "answer": item["answer"],
                    "reason": "原文引用图示，但文件未包含对应图片",
                    "content": image_text, "questionCount": 1,
                })
                continue
            records.append(item)
            accepted += 1
        rejected.extend(errors)
        files.append({"file": relative,
                      "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                      "sourceQuestions": expected,
                      "parsed": accepted, "rejected": sum(e["questionCount"] for e in errors)})
    deduplicated: dict[str, dict] = {}
    duplicates = 0
    for item in records:
        key = content_key(item)
        origin = {k: item[k] for k in ("sourceFile", "sourceSection", "sourceNumber")}
        if key in deduplicated:
            previous = deduplicated[key]
            if previous["answer"] != item["answer"]:
                rejected.append({
                    **origin, "reason": "相同题干和选项的答案冲突",
                    "answer": item["answer"], "otherAnswer": previous["answer"],
                    "content": item["stem"], "questionCount": 1,
                })
                previous["answerConflict"] = True
            else:
                duplicates += 1
                previous["origins"].append(origin)
                if not previous["explanation"] and item["explanation"]:
                    previous["explanation"] = item["explanation"]
            continue
        deduplicated[key] = {**item, "origins": [origin]}
    questions = []
    for key, item in deduplicated.items():
        if item.get("answerConflict"):
            continue
        identifier = hashlib.sha256((key + item["answer"]).encode()).hexdigest()[:20]
        question = {
            "id": f"RW-{identifier}", "subject": item["subject"],
            "chapter": "综合练习", "type": item["type"], "stem": item["stem"],
            "options": item["options"], "answer": item["answer"], "rubric": None,
            "explanation": item["explanation"] or MISSING_EXPLANATION,
            "explanationStatus": "source" if item["explanation"] else "missing",
            "warning": "题目与答案保留原资料记录。",
            "reference": COLLECTION, "citation": {
                "title": COLLECTION, "publisher": None, "edition": None,
                "chapter": None, "page": None, "verified": False,
            },
            "tags": [COLLECTION, item["subject"]], "topics": [],
            "modes": ["执医", "考研"], "school": None, "year": None,
            "paperId": "renwei-exercises", "paperName": COLLECTION,
            "collection": COLLECTION, "durationMinutes": 90,
            "order": len(questions) + 1, "points": 1, "isDemo": False,
            "reviewStatus": "draft", "sourceType": "user_material",
            "license": "用户提供学习资料",
            "sourceRecords": item["origins"],
        }
        if item["sharedStem"]:
            question["sharedStem"] = item["sharedStem"]
        for field, image_field in (("stem", "stemImages"), ("sharedStem", "sharedStemImages"),
                                   ("explanation", "explanationImages")):
            value = question.get(field, "")
            images = IMAGE.findall(value)
            if images:
                question[image_field] = images
                question[field] = IMAGE.sub("", value).strip() or (
                    "请根据图示选择正确答案。" if field == "stem" else "见图"
                )
        option_images = {}
        for option, value in question["options"].items():
            images = IMAGE.findall(value)
            if images:
                option_images[option] = images
                question["options"][option] = IMAGE.sub("", value).strip() or "见图"
        if option_images:
            question["optionImages"] = option_images
        original_subject = question["subject"]
        question["subject"], question["chapter"] = classify(question)
        question["sourceSubject"] = original_subject
        question["chapterByMode"] = chapters_by_mode(question)
        question["chapterAssignment"] = "topic_rules"
        question["citation"]["chapter"] = question["chapter"]
        if item["type"] in {"A3", "A4", "B"}:
            group_key = json.dumps([item["sourceFile"], item["sourceSection"],
                                   item["sharedStem"], item["options"] if item["type"] == "B" else None],
                                  ensure_ascii=False)
            question["groupId"] = "rw-group-" + hashlib.sha256(group_key.encode()).hexdigest()[:20]
        questions.append(question)
    bank = {"version": 1, "name": COLLECTION, "isDemo": False, "questions": questions}
    report = {
        "files": files, "sourceQuestions": sum(f["sourceQuestions"] for f in files),
        "parsedQuestions": len(records), "exactDuplicates": duplicates,
        "importedQuestions": len(questions), "rejected": rejected,
        "subjects": dict(Counter(q["subject"] for q in questions)),
        "types": dict(Counter(q["type"] for q in questions)),
        "withExplanation": sum(q["explanationStatus"] == "source" for q in questions),
        "chapterCounts": {
            mode: {
                subject: len({q["chapterByMode"][mode] for q in questions if q["subject"] == subject})
                for subject in sorted({q["subject"] for q in questions})
            } for mode in ["执医", "考研"]
        },
    }
    return bank, report


def merge_into_app(bank: dict, target: Path, backup: Path) -> None:
    app = json.loads(target.read_text(encoding="utf-8"))
    if any(q.get("collection") == COLLECTION for q in app["questions"]):
        raise ValueError("App 已含人卫练习题，拒绝重复合并")
    if backup.exists():
        raise FileExistsError(f"备份已存在，拒绝覆盖：{backup}")
    existing_ids = {q["id"] for q in app["questions"]}
    if existing_ids & {q["id"] for q in bank["questions"]}:
        raise ValueError("题目 ID 与既有题库冲突")
    backup.parent.mkdir(parents=True, exist_ok=True)
    backup.write_bytes(target.read_bytes())
    merged = copy.deepcopy(app)
    merged["questions"].extend(bank["questions"])
    target.write_text(json.dumps(merged, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_dir", type=Path)
    parser.add_argument("--output", type=Path, default=ROOT / "question-bank/人卫练习题.json")
    parser.add_argument("--report", type=Path, default=ROOT / "question-bank/人卫练习题导入报告.json")
    parser.add_argument("--app-bank", type=Path)
    parser.add_argument("--backup", type=Path, default=ROOT / "question-bank/backups/all_questions-before-renwei.json")
    args = parser.parse_args()
    bank, report = build(args.source_dir)
    for path, value in [(args.output, bank), (args.report, report)]:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in report.items() if k not in {"files", "rejected"}}, ensure_ascii=False))
    print(f"拒绝记录 {len(report['rejected'])}，详见 {args.report}")
    if args.app_bank:
        merge_into_app(bank, args.app_bank, args.backup)
        print(f"已合并到 {args.app_bank}")


if __name__ == "__main__":
    main()

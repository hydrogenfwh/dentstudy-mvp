import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from import_renwei_exercises import parse_unit
from renwei_chapters import classify, chapters_by_mode
from merge_legacy_subject_chapters import ASSIGNMENTS, without_placement
from bank import validate
from server import validate_event


class RenweiImportTests(unittest.TestCase):
    def test_grouped_source_answers_keep_options_and_clinical_stem(self):
        questions = parse_unit(
            "（1-2题共用题干）\n仅用于软件测试的共同病史。\n"
            "1．第一个问题\nA．甲\nB．乙\n"
            "2．第二个问题\nA．丙\nB．丁",
            "1．A；2．B", "A3",
        )
        self.assertEqual([q["answer"] for q in questions], ["A", "B"])
        self.assertEqual(questions[1]["options"], {"A": "丙", "B": "丁"})
        self.assertEqual(questions[0]["sharedStem"], "仅用于软件测试的共同病史。")
        with self.assertRaises(ValueError):
            parse_unit("（1-2题共用题干）\n1．问题\nA．甲\nB．乙", "1．A", "A3")

    def test_shared_option_answers_support_letters_beyond_e(self):
        questions = parse_unit(
            "A、甲\nB、乙\nC、丙\nD、丁\nE、戊\nF.己\nG庚\n"
            "66.第一个问题\n67.第二个问题", "66．F；67．G", "B1",
        )
        self.assertEqual([q["answer"] for q in questions], ["F", "G"])
        self.assertEqual(questions[0]["options"]["G"], "庚")

    def test_track_chapters_reuse_existing_catalogues(self):
        q = {"subject": "口腔颌面外科学", "stem": "牙种植术中种植体的骨结合",
             "options": {"A": "甲", "B": "乙"}}
        subject, chapter = classify(q)
        mapped = chapters_by_mode({**q, "subject": subject, "chapter": chapter})
        self.assertEqual(mapped["执医"], "四、牙种植术")
        self.assertEqual(mapped["考研"], "第五章 口腔种植外科")

    def test_runtime_import_is_accounted_and_old_records_are_unchanged(self):
        bank = json.loads((ROOT / "mobile/assets/all_questions.json").read_text())
        source = json.loads((ROOT / "question-bank/人卫练习题.json").read_text())
        report = json.loads((ROOT / "question-bank/人卫练习题导入报告.json").read_text())
        self.assertEqual(validate(bank), [])
        self.assertEqual(len(source["questions"]), 14021)
        # The source bank is committed, whereas its local pre-import backup is
        # intentionally not.  Verify the same invariant by matching every
        # source item to the shipped bank by stable ID.  Reviewed catalogue
        # placement may add view-only metadata to selected legacy items.
        shipped_by_id = {q["id"]: q for q in bank["questions"]}
        self.assertEqual(
            [without_placement(shipped_by_id[q["id"]])
             if q["id"] in ASSIGNMENTS else shipped_by_id[q["id"]]
             for q in source["questions"]],
            source["questions"],
        )
        self.assertEqual(
            report["sourceQuestions"],
            report["importedQuestions"] + report["exactDuplicates"] +
            sum(item["questionCount"] for item in report["rejected"]),
        )
        self.assertTrue(all(q["modes"] == ["执医", "考研"] for q in source["questions"]))
        self.assertTrue(all("答疑编号" not in q["stem"] + q["explanation"] for q in source["questions"]))
        for q in source["questions"]:
            if q["explanationStatus"] == "missing":
                self.assertEqual(q["explanation"], "原资料未提供解析。")

    def test_multiselect_events_validate_the_entire_combination(self):
        q = {"id": "test", "type": "多选题", "answer": "AC",
             "options": {"A": "甲", "B": "乙", "C": "丙"}}
        event = {
            "id": "renwei_test_event_123", "questionId": "test",
            "at": "2020-01-01T00:00:00Z", "kind": "review",
            "value": {"answer": "AC", "grade": "mastered"},
        }
        validate_event(event, {"test": q})
        for value in ["CA", "AA", "D", "", ["A", "C"]]:
            event["value"]["answer"] = value
            with self.assertRaises(ValueError):
                validate_event(event, {"test": q})


if __name__ == "__main__":
    unittest.main()

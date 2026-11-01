import json
import re
import unittest
from pathlib import Path
from convert_content import convert

class ReviewedPromptsTests(unittest.TestCase):
    def test_exact_source_occurrences_and_no_answer_leak(self):
        segments, _ = convert(Path("docs/srt/7_Koğuştaki_Mucize.srt").read_text(encoding="utf-8-sig"))
        manifest = json.loads(Path("App/Resources/reviewed-manifest.json").read_text())
        bank = {}
        for name in manifest["files"]:
            part = json.loads(Path("App/Resources", name + ".json").read_text())["segments"]
            self.assertFalse(set(bank).intersection(part))
            bank.update(part)
        self.assertEqual(set(bank), {str(i) for i in range(2, manifest["reviewedThrough"] + 1)})
        total = 0
        for segment in segments[1:manifest["reviewedThrough"]]:
            rows = bank[str(segment["number"])]
            self.assertEqual([r[0] for r in rows], [w["text"] for w in segment["words"]])
            for answer, prompt in rows:
                self.assertTrue(prompt.strip())
                self.assertIsNone(re.search(r"[A-Za-zÇĞİÖŞÜçğıöşü]", prompt))
                self.assertNotIn(answer.casefold(), prompt.casefold())
                total += 1
        self.assertEqual(total, manifest["expectedSourceOccurrences"])

    def test_reviewed_phrases_align_and_do_not_leak(self):
        segments, _ = convert(Path("docs/srt/7_Koğuştaki_Mucize.srt").read_text(encoding="utf-8-sig"))
        by_id = {s["id"]: s for s in segments}
        manifest = json.loads(Path("App/Resources/reviewed-phrases-manifest.json").read_text())
        self.assertEqual(len(set(manifest["files"])), len(manifest["files"]))
        questions = []
        for name in manifest["files"]:
            questions.extend(json.loads(Path("App/Resources", name + ".json").read_text()))
        self.assertEqual(len(questions), manifest["expectedQuestions"])
        self.assertEqual(len({q["id"] for q in questions}), len(questions))
        for q in questions:
            self.assertEqual(q["kind"], "phrase")
            self.assertTrue(q["id"].startswith(q["segmentID"] + ":p"))
            self.assertTrue(q["id"].endswith(":choice"))
            self.assertIsNone(re.search(r"[A-Za-zÇĞİÖŞÜçğıöşü]", q["prompt"]))
            source = " ".join(by_id[q["segmentID"]]["turkish"].split())
            self.assertIn(q["answer"], source)
            self.assertEqual(len(q["choices"]), 4)
            self.assertEqual(q["choices"].count(q["answer"]), 1)

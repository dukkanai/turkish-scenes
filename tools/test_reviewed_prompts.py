import json
import re
import unittest
from pathlib import Path
from convert_content import convert

class ReviewedPromptsTests(unittest.TestCase):
    def test_exact_source_occurrences_and_no_answer_leak(self):
        segments, _ = convert(Path("docs/srt/7_Koğuştaki_Mucize.srt").read_text(encoding="utf-8-sig"))
        bank = json.loads(Path("App/Resources/reviewed-prompts.json").read_text())["segments"]
        self.assertEqual(set(bank), {str(i) for i in range(2, 21)})
        total = 0
        for segment in segments[1:20]:
            rows = bank[str(segment["number"])]
            self.assertEqual([r[0] for r in rows], [w["text"] for w in segment["words"]])
            for answer, prompt in rows:
                self.assertTrue(prompt.strip())
                self.assertIsNone(re.search(r"[A-Za-zÇĞİÖŞÜçğıöşü]", prompt))
                self.assertNotIn(answer.casefold(), prompt.casefold())
                total += 1
        self.assertEqual(total, 114)

import json
from pathlib import Path
import re
import unicodedata
import unittest

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "App/AudioResources"

def normalize(value):
    return " ".join(unicodedata.normalize("NFC", value).translate(str.maketrans({"I":"ı", "İ":"i"})).lower().split()).strip(".!?,;:")

class CurriculumChecks(unittest.TestCase):
    def test_counts_identity_and_fields(self):
        words = json.loads((RESOURCES / "audio-words-a.json").read_text()) + json.loads((RESOURCES / "audio-words-b.json").read_text())
        phrases = json.loads((RESOURCES / "audio-phrases.json").read_text())
        grammar = json.loads((RESOURCES / "audio-grammar.json").read_text())
        self.assertGreaterEqual(len([w for w in words if len(w["turkish"].split()) == 1]), 1200)
        self.assertGreaterEqual(len(phrases), 250)
        self.assertGreaterEqual(len(grammar), 20)
        self.assertEqual(len(words) % 5, 0)
        self.assertEqual(len(phrases) % 5, 0)
        all_ids = [w["id"] for w in words + phrases + grammar]
        self.assertEqual(len(set(all_ids)), len(all_ids))
        for data, kind in [(words, "word"), (phrases, "phrase")]:
            terms = [normalize(w["turkish"]) for w in data]
            self.assertEqual(len(terms), len(set(terms)))
            for w in data:
                self.assertEqual(w["kind"], kind)
                for field in ["category", "turkish", "arabic", "exampleTurkish", "exampleArabic"]:
                    self.assertTrue(w[field].strip(), (w["id"], field))
                    self.assertLessEqual(len(w[field]), 2000)
                self.assertTrue(w["acceptedArabic"])
                self.assertTrue(all(isinstance(a, str) and a.strip() for a in w["acceptedArabic"]))
                self.assertRegex(w["arabic"], r"[\u0600-\u06ff]")
                self.assertRegex(w["exampleArabic"], r"[\u0600-\u06ff]")
        for g in grammar:
            self.assertIn(g["expectedTurkish"], g["acceptedAnswers"])
            for field in ["titleArabic", "explanationArabic", "questionArabic", "correctionArabic", "exampleTurkish", "exampleArabic"]:
                self.assertTrue(g[field].strip())
        print(f"Validated {len(words)} lexical entries ({sum(len(w['turkish'].split()) == 1 for w in words)} single words), {len(phrases)} phrases and {len(grammar)} grammar lessons")

    def test_security_contract(self):
        key = (ROOT / "App/PersonalAPIKey.swift").read_text()
        tutor = (ROOT / "App/RealtimeTutor.swift").read_text()
        io = (ROOT / "App/RealtimeAudioIO.swift").read_text()
        self.assertIn("kSecAttrAccessibleWhenUnlockedThisDeviceOnly", key)
        self.assertIn("kSecAttrSynchronizable as String: false", key)
        self.assertIn("URLSessionConfiguration.ephemeral", tutor)
        self.assertIn("completionHandler(nil)", tutor)
        self.assertIn("maximumMessageSize = 1_000_000", tutor)
        self.assertIn('RealtimeFailure.service(event["error"]', tutor)
        self.assertIn('RealtimeFailure.service(details?["error"]', tutor)
        self.assertIn('RealtimeFailure.transport(httpStatus:', tutor)
        self.assertIn('AudioTutorProtocol.sessionConfiguration', tutor)
        self.assertNotIn('"model": AudioTutorProtocol.model', tutor)
        failure = (ROOT / "App/RealtimeFailure.swift").read_text()
        self.assertNotIn('["message"]', failure)
        self.assertNotIn("localizedDescription", failure)
        self.assertIn("generation", io)
        self.assertNotIn("UserDefaults", key)
        for source in (ROOT / "App").glob("*.swift"):
            text = source.read_text()
            self.assertIsNone(re.search(r"sk-(?:proj-)?[A-Za-z0-9_-]{20,}", text))
            self.assertNotIn("print(key)", text)
        self.assertNotIn("YouTube", (ROOT / "App/TurkishScenesApp.swift").read_text())

if __name__ == "__main__":
    unittest.main()

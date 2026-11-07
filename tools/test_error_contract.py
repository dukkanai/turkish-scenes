"""Source contracts complement, but do not replace, compiled Swift/runtime checks."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]

class ErrorContractChecks(unittest.TestCase):
    def test_fallible_boundaries_do_not_silently_drop_errors(self):
        for filename in ["RealtimeTutor.swift", "RealtimeAudioIO.swift", "AudioTutorProtocol.swift", "AudioLearningView.swift"]:
            source = (ROOT / "App" / filename).read_text()
            self.assertNotIn("try?", source, filename)
            self.assertNotIn("try!", source, filename)
        tutor = (ROOT / "App/RealtimeTutor.swift").read_text()
        self.assertIn("io.onFailure =", tutor)
        self.assertIn("store.$persistenceFailure", tutor)
        self.assertIn("guard store.canUseProgress", tutor)
        self.assertIn("sendBudget.reserve", tutor)
        self.assertIn("sendBudget.release", tutor)
        self.assertIn("didCloseWith closeCode", tutor)
        self.assertIn("didCompleteWithError", tutor)
        self.assertIn("self.generation == token", tutor)

    def test_diagnostics_have_no_arbitrary_payload_fields_or_remote_logger(self):
        diagnostics = (ROOT / "App/RealtimeDiagnostics.swift").read_text()
        for forbidden in ["localizedDescription", '["message"]', '["reason"]', "URLSession", "print(", "Logger(", "UserDefaults", "Data(contentsOf:"]:
            self.assertNotIn(forbidden, diagnostics)
        self.assertIn("let code: RealtimeDiagnosticCode", diagnostics)
        self.assertIn("capacity = 24", diagnostics)
        self.assertIn("entries.removeFirst", diagnostics)
        for path in (ROOT / "App").glob("*.swift"):
            self.assertNotIn("localizedDescription", path.read_text(), path.name)

    def test_json_preflight_prevents_objc_invalid_object_exception(self):
        codec = (ROOT / "App/RealtimeMessageCodec.swift").read_text()
        self.assertLess(codec.index("JSONSerialization.isValidJSONObject"), codec.index("JSONSerialization.data"))
        self.assertIn("maximumMessageBytes = 1_000_000", codec)
        self.assertIn("data.count % 2 == 0", codec)

if __name__ == "__main__":
    unittest.main()

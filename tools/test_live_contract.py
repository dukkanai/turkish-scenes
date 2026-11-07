"""Static security/lifecycle contracts; Swift replay and device tests are separate."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
class LiveContractChecks(unittest.TestCase):
    def test_actual_live_contract_and_ui(self):
        tutor = (ROOT / 'App/LiveTutor.swift').read_text()
        protocol = (ROOT / 'App/LiveTutorProtocol.swift').read_text()
        ui = (ROOT / 'App/AudioLearningView.swift').read_text()
        self.assertIn('StateObject(wrappedValue: LiveTutor(store: store))', ui)
        self.assertIn('gpt-live-1', protocol)
        self.assertIn('gpt-6-luna', protocol)
        self.assertIn('wss://api.openai.com/v1/live/sessions', protocol)
        self.assertIn('"store": false', protocol)
        self.assertIn('"session.start"', protocol)
        self.assertIn('"response.item.create"', protocol)
        self.assertIn('"session.input_audio.append"', tutor)
        self.assertIn('"session.output_audio.delta"', tutor)
        self.assertIn('"response.output_item.done"', tutor)
        self.assertIn('"response.completed"', tutor)
        self.assertNotIn('"conversation.item.create"', tutor)
        self.assertNotIn('"response.cancel"', tutor)
        self.assertIn('تُحاسب مدة الصوت وتوكنات الخلفية منفصلتين', ui)
        self.assertIn('الكتم', ui)

    def test_runtime_key_is_confined_and_errors_are_visible(self):
        tutor = (ROOT / 'App/LiveTutor.swift').read_text()
        for token in ['completionHandler(nil)', 'URLSessionConfiguration.ephemeral',
                      'config.urlCredentialStorage = nil', 'sendBudget.reserve', 'sendBudget.release',
                      'guard store.canUseProgress', 'store.$persistenceFailure', 'io.onFailure',
                      'RealtimeMessageCodec.encode', 'RealtimeMessageCodec.event', 'generation == token']:
            self.assertIn(token, tutor)
        for forbidden in ['try?', 'try!', 'localizedDescription', 'print(', 'Logger(', 'UserDefaults', 'http://']:
            self.assertNotIn(forbidden, tutor)
        self.assertEqual(tutor.count('PersonalAPIKey.read()'), 1)

    def test_shutdown_and_usage_are_not_realtime_token_only(self):
        tutor = (ROOT / 'App/LiveTutor.swift').read_text()
        close = tutor.split('func stop(', 1)[1].split('private func finishStop', 1)[0]
        self.assertLess(close.index('io.stop()'), close.index('"session.close"'))
        self.assertIn('guard started, let socket', close)
        self.assertNotIn('guard state == .connected', close)
        self.assertIn('sendGeneration = UUID()', close)
        self.assertIn('5_000_000_000', close)
        self.assertIn('started && !voiceUsage.finalized', tutor)
        self.assertIn('"session.closed"', tutor)
        self.assertIn('voiceUsage.record(event, final: true)', tutor)
        self.assertIn('pendingMute?.id == id', tutor)
        self.assertIn('turns.permits(pending.lease', tutor)
        self.assertIn('guard mutationUsed else', tutor)

if __name__ == '__main__':
    unittest.main()

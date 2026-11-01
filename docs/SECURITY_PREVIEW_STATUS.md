# Internal preview readiness

This is an incomplete development preview, not a final release.
The practice bank currently contains eight manually authored vocabulary questions for the first segment. The full 1666-segment educational source is preserved, but all segments still require editorial review.

## Implemented safeguards

- No app backend, account system, advertising SDK or runtime AI service.
- Learning progress is saved locally, atomically, with a previous-file backup and iOS file protection.
- Unreadable saved progress is preserved rather than silently overwritten.
- The embedded YouTube player uses an ephemeral web data store.
- Player identifiers and time ranges are validated before interpolation.
- Navigation policy rejects non-HTTPS URLs, credentials in URLs, nonstandard ports, deceptive hostnames and unrelated main-frame navigation.
- No native JavaScript message bridge is exposed.
- Signing material is supplied only through a protected GitHub environment, never through source code or build artifacts.
- The signing script uses an ephemeral keychain and removes temporary signing files on exit.
- No public App Store release is configured or authorized by this preview procedure.

## Verification status

Core grading/persistence, converter and simulator UI checks passed on earlier commits. Later security changes must pass CI on their exact commit before relying on those results.
New executable negative tests cover JavaScript/file/HTTP URL attempts, deceptive hosts, userinfo, invalid ports, malformed video identifiers and invalid time ranges.

NOT RUN:
- Real-device VoiceOver usability and focus behavior.
- Real-device video playback, segment timing and interruption behavior.
- Full educational-content editorial acceptance.
- Comprehensive penetration testing.
- Signed archive validation, Apple processing and tester installation.

The absence of findings in focused checks is not proof of complete security.
No TestFlight upload has occurred. Any early internal preview must be clearly labeled incomplete and must not be represented as a finished application.

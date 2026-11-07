# Error boundaries and safe diagnostics

The app catches actual Swift throwing boundaries and handles asynchronous callback failures. Wrapping a non-throwing function in `do/catch` cannot catch Swift traps, out-of-memory termination or Objective-C exceptions. Validation and guards prevent invalid input at those boundaries; this work does not claim to catch every possible crash.

## Covered paths

- Keychain read/save/delete: explicit failure UI, separate format and storage failures, no false “no saved key” after a read failure. Key material stays in Keychain and is not included in diagnostics.
- Curriculum/progress decode and writes: existing atomic writes and backup preservation retained. A disk write failure now stops an active paid session immediately. Corrupt/unavailable progress blocks a new session until recovery/reopen.
- Outbound JSON and lesson/tool serialization: throwing codec, valid-object preflight and 1 MB limit. No silent empty-object fallback.
- Inbound events, audio and tool arguments: size/type/PCM validation, explicit rejection, no mutation from malformed or stale tool calls.
- Connection: setup deadline, WebSocket open/close and URLSession completion errors, fixed offline/timeout/DNS/TLS/lost-connection categories. No raw error descriptions or close reasons are exposed; no automatic reconnection or certificate bypass.
- Send queue: bounded audio bytes and total queued message count. Asynchronous send/receive errors stop recording and invalidate all stale-generation callbacks.
- Audio: throwing setup/playback, converter return status plus NSError handling, allocation and sample-data failure callbacks, explicit teardown-failure reporting. Empty conversion output when awaiting more samples remains normal.
- Lifecycle: stop on background, audio interruption, disconnected output device and audio-service lost/reset. A repeated stop does not erase the first actionable failure.
- UI: expandable, bounded 24-entry memory-only code timeline. No log upload, persisted transcript, API key, raw request, URL, header or arbitrary server message in diagnostics.

Pure learning rules return explicit acceptance/rejection rather than throw for expected invalid input. Expected cancellation exits tasks without presenting it as a network failure. Unknown event names remain forward compatible, while malformed known event payloads fail closed.

## Verification

`ci/check_audio.sh` runs data/security contracts, compiled Swift progress/protocol/diagnostic/codec/queue tests, and existing playback/usage checks. The macOS CI builds simulator and optimized archive and runs UI smoke tests. Paid OpenAI calls, real microphone/network interruption recovery, Keychain device failures and VoiceOver remain separate real-device acceptance checks; no paid API was used for this work.

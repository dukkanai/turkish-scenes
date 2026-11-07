# GPT-Live personal iPhone integration

## Implemented transport

The learning UI now selects `LiveTutor`, with `gpt-live-1` on the distinct primary WebSocket `wss://api.openai.com/v1/live/sessions`. It sends `session.start` first and waits for `session.started` before capturing audio or sending application commands. Model selection is in session configuration, not a Realtime query parameter. Mono PCM16 at 24 kHz continues through the hardened native audio engine.

This is the existing personal **bring-your-own-key** architecture: the owner enters their own key into iPhone Keychain, and the installed app uses it only with `api.openai.com`. There is no embedded project key, external proxy, shared secret, or new credential. Redirects and URL credential/cookie/cache storage are disabled. This architecture is not an OpenAI endorsement of keeping shared project keys in mobile apps. Official documentation recommends a trusted server and WebRTC for production applications. A shared-key deployment would require a separately authorized trusted backend and access controls.

No API key was read, created, copied or transmitted by the development/test process. No paid OpenAI session was created. Account access to either model is unverified.

## Voice and evaluation

GPT-Live manages full-duplex speech. `gpt-6-luna` is the separate managed Responses backend used to evaluate answers and request the existing three tools. No external tool server, hosted search or arbitrary tool execution is enabled. Only the app can save progress or propose a word for explicit review. The backend is configured for sequential tools and a 700-output-token response limit.

The client handles nested `response.event` envelopes, records response IDs from `response.created`, and associates `response.output_item.done` with the outer delegation ID. It does not expect a response ID in the output-item event or function calls in the empty lifecycle `response.output` array. Only completed responses can mutate progress. Duplicate calls, stale prompts, missing fresh timed user speech, incomplete responses and malformed input fail closed. UI quiz/repeat actions and mute acknowledgments invalidate pending evaluation evidence. Input IDs/timestamps are tracked even during mute. After invalidation, evaluation requires a new output boundary and a conservative 500 ms gap before a fresh utterance, rather than treating a continued old fragment as a new answer. Ambiguous or late transcript evidence can reject a legitimate answer; real-device testing is still required to tune that conservatively.

Live has no Realtime committed-input or audio-done event. We preserve caption fragments and timing, use native playback queues, and do not fabricate completion or truncation acknowledgments. A repeat request clears locally queued sound and appends a Live instruction; speech already in transit may continue briefly. Full-duplex interruptions, greeting behavior, Arabic/Turkish pronunciation and grading require on-device evaluation.

## Cost, stopping and privacy

Voice duration and backend tokens are tracked independently. Duration updates are cumulative, never summed. Backend response tokens are deduplicated, including failed/stale responses. The consent dialog discloses separate backend billing, ongoing voice billing during silence/mute, account/model requirements and that the timer is not a monetary cap. Current prices remain linked rather than represented as a guaranteed invoice. The official WebRTC guide documents a 15-second billed initialization; no assumption is made that WebSocket invoices are identical without an account test.

The owner chooses 3, 5 or 10 minutes and explicitly approves every start. Backgrounding, dismissal, audio interruption, storage failure, network failure and deadline stop microphone capture and playback. A connected stop sends `session.close`, waits at most five seconds for `session.closed`, then releases transport. An absent terminal usage event is visibly marked unconfirmed. There is no automatic reconnect. A pending stop blocks a new session.

Local mute blocks microphone submission immediately; unmute waits for the matching server acknowledgment. A missing acknowledgment stops the session. Muting does not close the session or stop its cost. `store: false` avoids opt-in Live recording/fork storage; this does not change OpenAI's applicable service data-retention policies. Transcripts, temporary request correlation and enum-only diagnostics remain in memory, never in progress files or logs.

## Verification boundaries

Added Python source/security contracts and compiled Swift protocol/replay checks cover Live payload shape, no Realtime endpoint substitution, tool-result shape, nested-response correlation without `response_id`, duplicate events, failed/malformed tool items, stale prompt/speech rejection, boolean/nonfinite duration rejection and cumulative usage. Existing curriculum, storage, key, error handling and delivery tests remain.

The code revision `d7baf81ab74d94e1685f4d55b9c70601d518bc86` passed all 20 Python checks, compiled Swift suites including Live protocol/replay, simulator build, Arabic/icon verification, optimized unsigned Release archive and iPhone UI smoke in [CI run 42368164871](https://github.com/dukkanai/turkish-scenes/actions/runs/42368164871). The TestFlight workflow reruns its checks on the release commit before signing and uploading. Paid model connectivity, actual microphone/network playback and real-device VoiceOver have **not** been verified. Upload or Apple's processing success is not proof of those checks.

## Official sources reviewed 2026-11-07

- https://developers.openai.com/api/docs/guides/voice-websockets?api=live
- https://developers.openai.com/api/reference/resources/live/primary-websocket
- https://developers.openai.com/api/docs/guides/live-delegation
- https://developers.openai.com/api/docs/guides/live-conversations
- https://developers.openai.com/api/docs/guides/voice-webrtc?api=live
- https://developers.openai.com/api/reference/resources/responses/streaming-events

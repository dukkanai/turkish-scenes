import Foundation
import Combine
import AVFoundation

private final class LiveNetworkPolicy: NSObject, URLSessionWebSocketDelegate {
    enum Event { case opened, closed, failed(Error, Int?) }
    private let onEvent: (Event) -> Void
    init(onEvent: @escaping (Event) -> Void) { self.onEvent = onEvent }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // Never redirect a personal Authorization header.
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol selectedProtocol: String?) {
        onEvent(.opened)
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) { onEvent(.closed) }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { onEvent(.failed(error, (task.response as? HTTPURLResponse)?.statusCode)) }
    }
}

/// Personal BYOK client. A shared production key must instead stay on a trusted
/// backend. No embedded key, proxy, reconnect, or credential logging is used here.
@MainActor final class LiveTutor: ObservableObject {
    enum State { case stopped, connecting, connected, closing }
    @Published private(set) var state: State = .stopped
    @Published private(set) var status = "الجلسة متوقفة"
    @Published private(set) var transcript = ""
    @Published private(set) var muted = false
    @Published private(set) var mutePending = false
    @Published var proposedWord: AudioCard?
    @Published private(set) var totalTokens = 0
    @Published private(set) var voiceUsage = LiveSessionUsage()
    @Published private(set) var diagnostics = RealtimeDiagnostics()
    private let store: AudioProgressStore
    private let io = RealtimeAudioIO()
    private var usage = RealtimeUsage()
    private var turns = LiveTurnLedger()
    private var network: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var receiver: Task<Void, Never>?
    private var sender: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var handshake: Task<Void, Never>?
    private var closeDeadline: Task<Void, Never>?
    private var muteDeadline: Task<Void, Never>?
    private var generation = UUID()
    private var sendGeneration = UUID()
    private var sendBudget = RealtimeSendBudget()
    private var progressObserver: AnyCancellable?
    private var started = false
    private var teardownFailed = false
    private var closingMessage = ""
    private var pendingMute: (id: String, value: Bool)?
    private struct Binding { let lease: LiveTurnLedger.Lease? }
    private var delegations: [String: Binding] = [:]
    private var responses = LiveResponseRegistry()
    private var handledCalls: Set<String> = []

    init(store: AudioProgressStore) {
        self.store = store
        io.onFailure = { [weak self] _ in
            guard let self, self.state == .connected else { return }
            self.fail(.audioConversion, "تعذر تحويل صوت الميكروفون. توقفت الجلسة؛ حاول بدءها مجددًا.")
        }
        progressObserver = store.$persistenceFailure.dropFirst().sink { [weak self] failed in
            guard failed, let self, self.state == .connected || self.state == .connecting else { return }
            self.fail(.progressWrite, "لم يُحفظ التغيير. أوقفنا الميكروفون والجلسة، وبقي التقدم السابق محفوظًا.")
        }
        io.onPCM = { [weak self] data in
            guard let self, self.state == .connected, !self.muted, !self.mutePending else { return }
            self.send(["type": "session.input_audio.append", "audio": data.base64EncodedString()], audioBytes: data.count)
        }
    }

    func start(minutes: Int) async {
        guard state == .stopped, let session = store.progress.session, session.phase != .complete,
              (1...10).contains(minutes) else { return }
        guard store.canUseProgress else {
            fail(.progressUnavailable, "تعذر الوصول إلى تقدم التعلم أو حفظه. لم نبدأ اتصالًا مدفوعًا."); return
        }
        state = .connecting; status = "طلب إذن الميكروفون والاتصال بـ GPT-Live"; transcript = ""
        diagnostics = RealtimeDiagnostics(); diagnostics.record(.starting)
        usage = RealtimeUsage(); totalTokens = 0; voiceUsage = LiveSessionUsage(); turns = LiveTurnLedger()
        delegations = [:]; responses = LiveResponseRegistry(); handledCalls = []
        muted = false; mutePending = false; pendingMute = nil; started = false; teardownFailed = false
        let token = UUID(); generation = token; sendGeneration = UUID()
        let permitted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard !Task.isCancelled, generation == token, state == .connecting else { return }
        guard permitted else { fail(.permissionDenied, "الميكروفون غير مسموح. يمكنك السماح به من إعدادات iPhone."); return }
        do {
            guard let key = try PersonalAPIKey.read(), !key.isEmpty else {
                fail(.missingKey, "أدخل مفتاح OpenAI الشخصي في الإعدادات أولًا."); return
            }
            // Encode before creating any paid session. Only the app reads its
            // owner's key at runtime; tests never need or contact an account.
            let start = try LiveTutorProtocol.start(progress: store.progress, cards: store.allCards)
            _ = try RealtimeMessageCodec.encode(start)
            let config = URLSessionConfiguration.ephemeral
            config.urlCache = nil; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
            config.timeoutIntervalForRequest = 20
            config.timeoutIntervalForResource = TimeInterval(minutes * 60 + 30)
            let delegate = LiveNetworkPolicy { [weak self] event in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token, self.state != .stopped else { return }
                    switch event {
                    case .opened: self.diagnostics.record(.socketOpened)
                    case .closed:
                        self.diagnostics.record(.socketClosed)
                        self.finishStop(self.state == .closing ? self.closingMessage : "انقطع اتصال GPT-Live. لم نعد الاتصال تلقائيًا.")
                    case .failed(let error, let code):
                        self.diagnostics.record(RealtimeDiagnostics.networkCode(error))
                        self.finishStop(self.state == .closing ? self.closingMessage : RealtimeFailure.transport(httpStatus: code, networkCode: RealtimeDiagnostics.networkCode(error)))
                    }
                }
            }
            let network = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            self.network = network
            var request = URLRequest(url: LiveTutorProtocol.endpoint)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let task = network.webSocketTask(with: request)
            task.maximumMessageSize = 1_000_000
            socket = task; task.resume()
            receiver = Task { [weak self] in
                do {
                    while !Task.isCancelled {
                        let message = try await task.receive()
                        guard let self, self.generation == token else { return }
                        let data: Data
                        switch message {
                        case .string(let text): data = Data(text.utf8)
                        case .data(let bytes): data = bytes
                        @unknown default: throw RealtimeMessageCodec.Failure.invalidEvent
                        }
                        do { try self.handle(RealtimeMessageCodec.event(data)) }
                        catch { self.fail(.incomingJSON, "وصلت بيانات غير صالحة من الخدمة. أوقفنا الجلسة دون تغيير تقدمك غير المؤكد.") }
                    }
                } catch {
                    guard let self, self.generation == token, !Task.isCancelled else { return }
                    self.diagnostics.record(RealtimeDiagnostics.networkCode(error))
                    self.finishStop(self.state == .closing ? self.closingMessage : RealtimeFailure.transport(httpStatus: (task.response as? HTTPURLResponse)?.statusCode, networkCode: RealtimeDiagnostics.networkCode(error)))
                }
            }
            send(start) // First message; never wait for Realtime's session.created.
            handshake = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 20_000_000_000) } catch { return }
                guard let self, self.generation == token, self.state == .connecting else { return }
                self.fail(.setupTimeout, "انتهت مهلة الاتصال. تحقق من الإنترنت والمفتاح وإتاحة GPT-Live في حسابك.")
            }
            deadline = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: UInt64(minutes) * 60_000_000_000) } catch { return }
                guard let self, self.generation == token else { return }
                self.stop("انتهت المدة التي اخترتها. يمكنك بدء جلسة جديدة بعد مراجعة التكلفة.")
            }
        } catch is PersonalAPIKey.KeyError {
            fail(.keychainReadFailed, "تعذر قراءة المفتاح المحفوظ. لم يُعرض المفتاح أو يُسجّل.")
        } catch {
            fail(.outgoingJSON, "تعذر تجهيز بيانات جلسة GPT-Live. لم نبدأ جلسة أو نسجل المفتاح.")
        }
    }

    /// Stop capture/playback immediately, then briefly drain final usage. Never
    /// keep the microphone running while waiting for session.closed.
    func stop(_ message: String = "توقفت الجلسة والميكروفون. التقدم المسجل محفوظ.") {
        guard state != .closing, state != .stopped else { return }
        guard started, let socket else { finishStop(message); return }
        state = .closing; closingMessage = message; status = "توقف الميكروفون. جارٍ إغلاق الجلسة وتأكيد الاستخدام."
        muted = true; mutePending = false; pendingMute = nil; turns.invalidate()
        if io.stop() != nil { teardownFailed = true; diagnostics.record(.audioTeardown) }
        deadline?.cancel(); handshake?.cancel(); muteDeadline?.cancel()
        sendGeneration = UUID() // Invalidate every queued audio/control send.
        let previous = sender, token = generation
        sender = Task { [weak self] in
            await previous?.value
            guard let self, self.generation == token, self.state == .closing else { return }
            do { try await socket.send(.string(RealtimeMessageCodec.encode(["type": "session.close", "event_id": UUID().uuidString]))) }
            catch {
                guard self.generation == token else { return }
                self.diagnostics.record(RealtimeDiagnostics.networkCode(error)); self.finishStop(message)
            }
        }
        closeDeadline = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            guard let self, self.generation == token, self.state == .closing else { return }
            self.finishStop(message)
        }
    }

    private func finishStop(_ message: String) {
        let uncertain = started && !voiceUsage.finalized
        generation = UUID(); sendGeneration = UUID(); state = .stopped
        receiver?.cancel(); sender?.cancel(); deadline?.cancel(); handshake?.cancel(); closeDeadline?.cancel(); muteDeadline?.cancel()
        receiver = nil; sender = nil; deadline = nil; handshake = nil; closeDeadline = nil; muteDeadline = nil
        if io.stop() != nil { teardownFailed = true; diagnostics.record(.audioTeardown) }
        socket?.cancel(with: .normalClosure, reason: nil); socket = nil
        network?.invalidateAndCancel(); network = nil
        sendBudget = RealtimeSendBudget(); muted = false; mutePending = false; pendingMute = nil
        responses = LiveResponseRegistry(); delegations = [:]; turns.invalidate(); started = false
        diagnostics.record(.stopped)
        status = message + (uncertain ? " لم تؤكد الخدمة الاستخدام النهائي؛ راجع حساب OpenAI." : "")
            + (teardownFailed ? " أوقفنا محرك الصوت، لكن النظام لم يؤكد تحرير جلسة الصوت. الرمز: audioTeardown" : "")
    }

    func toggleMute() {
        guard state == .connected, !mutePending else { return }
        setMute(!muted)
    }
    private func setMute(_ value: Bool) {
        guard state == .connected else { return }
        let id = UUID().uuidString, token = generation
        pendingMute = (id, value); mutePending = true
        if value { muted = true }
        turns.invalidate()
        status = value ? "الميكروفون مكتوم محليًا. جارٍ تأكيد الكتم من الخدمة." : "جارٍ تأكيد تشغيل الميكروفون."
        send(["type": value ? "session.input_audio.mute" : "session.input_audio.unmute", "event_id": id])
        muteDeadline?.cancel()
        muteDeadline = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            guard let self, self.generation == token, self.pendingMute?.id == id else { return }
            self.fail(.setupTimeout, "لم تؤكد الخدمة تغيير حالة الميكروفون. أوقفنا الجلسة.")
        }
    }

    func beginQuiz() {
        guard state == .connected, !mutePending else { return }
        _ = io.interrupt(); turns.invalidate()
        guard store.change({ $0.beginQuiz() }), state == .connected else { return }
        status = "بدأ الاختبار. طلبنا السؤال الحالي؛ قد تنتهي بقية الصوت السابق أولًا."
        refresh(repeatCurrent: true)
    }
    func repeatQuestion() {
        guard state == .connected, !mutePending else { return }
        _ = io.interrupt(); turns.invalidate()
        status = "طلبنا إعادة السؤال أو الشرح؛ قد يُسمع جزء قصير من الصوت السابق."
        refresh(repeatCurrent: true)
    }
    private func refresh(repeatCurrent: Bool = false) {
        do {
            send(try LiveTutorProtocol.update(progress: store.progress, cards: store.allCards))
            send(LiveTutorProtocol.context(progress: store.progress, repeatCurrent: repeatCurrent))
        } catch { fail(.outgoingJSON, "تعذر تجهيز حالة الدرس. أوقفنا الجلسة لحماية تقدمك.") }
    }
    private func fail(_ code: RealtimeDiagnosticCode, _ message: String) {
        diagnostics.record(code)
        if state == .stopped { status = message } else { stop(message) }
    }
    private func send(_ object: [String: Any], audioBytes: Int = 0) {
        guard state == .connecting || state == .connected, let socket else { return }
        let message: String
        do { message = try RealtimeMessageCodec.encode(object) }
        catch { fail(.outgoingJSON, "تعذر تجهيز رسالة للخدمة. أوقفنا الجلسة."); return }
        guard sendBudget.reserve(audioBytes: audioBytes) else {
            fail(.sendBackpressure, "الشبكة بطيئة للصوت المباشر. توقفت الجلسة دون إعادة اتصال تلقائي."); return
        }
        let previous = sender, token = generation, sendToken = sendGeneration
        sender = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled, let self, self.generation == token, self.sendGeneration == sendToken else { return }
            do {
                try await socket.send(.string(message))
                guard self.generation == token, self.sendGeneration == sendToken else { return }
                self.sendBudget.release(audioBytes: audioBytes)
            } catch {
                guard self.generation == token else { return }
                self.diagnostics.record(RealtimeDiagnostics.networkCode(error))
                self.finishStop("تعذر إرسال الصوت أو أوامر الجلسة. توقف الاتصال وبقي التقدم المسجل محفوظًا.")
            }
        }
    }

    private func handle(_ event: [String: Any]) throws {
        guard let type = event["type"] as? String else { throw RealtimeMessageCodec.Failure.invalidEvent }
        if type == "session.usage.updated" { voiceUsage.record(event); return }
        if type == "session.closed" {
            voiceUsage.record(event, final: true)
            finishStop(state == .closing ? closingMessage : "أنهت خدمة GPT-Live الجلسة. تقدمك المسجل محفوظ.")
            return
        }
        if type == "response.event", state == .closing {
            if let nested = event["event"] as? [String: Any], let response = nested["response"] as? [String: Any],
               ["response.completed", "response.failed", "response.incomplete", "response.cancelled"].contains(nested["type"] as? String ?? "") {
                usage.record(response); totalTokens = usage.totalTokens
            }
            return
        }
        guard state != .closing, state != .stopped else { return }
        switch type {
        case "session.started":
            guard state == .connecting, !started,
                  let session = event["session"] as? [String: Any], session["model"] as? String == LiveTutorProtocol.model else {
                throw RealtimeMessageCodec.Failure.invalidEvent
            }
            started = true
            do { try io.start() }
            catch { fail(.audioSetup, "تعذر تشغيل الصوت. أوقف المكالمات الأخرى ثم حاول مجددًا."); return }
            state = .connected; handshake?.cancel(); diagnostics.record(.sessionReady)
            status = "GPT-Live متصل. الميكروفون يعمل"
            send(LiveTutorProtocol.append("session.commentary.append", content: LiveTutorProtocol.greeting))
        case "session.input_transcript.delta":
            try turns.input(event, muted: muted || mutePending)
        case "session.output_transcript.delta":
            transcript = String((transcript + (try turns.output(event))).suffix(4000))
        case "session.output_audio.delta":
            guard state == .connected else { return }
            do { try io.play(RealtimeMessageCodec.audio(event["delta"]), itemID: "live-stream") }
            catch { fail(.audioPlayback, "تعذر تشغيل الصوت المستلم. توقفت الجلسة لحماية استقرار الصوت.") }
        case "session.input_audio.muted", "session.input_audio.unmuted":
            guard let pending = pendingMute, event["client_event_id"] as? String == pending.id,
                  (type == "session.input_audio.muted") == pending.value else { return }
            muted = pending.value; pendingMute = nil; mutePending = false; muteDeadline?.cancel()
            turns.invalidate()
            if !muted { refresh(repeatCurrent: true) }
            guard state == .connected else { return }
            status = muted ? "الميكروفون مكتوم. تبقى تكلفة الجلسة مستمرة." : "أستمع لإجابتك"
        case "session.delegation.created":
            guard let delegation = event["delegation"] as? [String: Any], delegation["target"] as? String == "responses",
                  let id = delegation["id"] as? String, !id.isEmpty, id.count <= 512,
                  delegations.count < 120 else { throw RealtimeMessageCodec.Failure.invalidEvent }
            guard delegations[id] == nil else { return }
            delegations[id] = Binding(lease: muted || mutePending ? nil : turns.lease(promptID: store.progress.session?.promptID))
        case "response.event": try handleResponse(event)
        case "error":
            diagnostics.record(.serviceRejected)
            stop(RealtimeFailure.service(event["error"] as? [String: Any], duringSetup: state == .connecting))
        default: break // Forward-compatible acknowledgments; no invented Realtime events.
        }
    }

    private func handleResponse(_ envelope: [String: Any]) throws {
        guard state == .connected else { return }
        guard let event = envelope["event"] as? [String: Any], let type = event["type"] as? String, !type.isEmpty else {
            throw RealtimeMessageCodec.Failure.invalidEvent
        }
        let delegation = envelope["delegation_id"] as? String
        switch type {
        case "response.created":
            guard let response = event["response"] as? [String: Any] else { throw RealtimeMessageCodec.Failure.invalidEvent }
            try responses.created(response, delegationID: delegation, lease: delegation.flatMap { delegations[$0]?.lease })
        case "response.output_item.done":
            try responses.itemDone(event, delegationID: delegation)
        case "response.completed", "response.failed", "response.incomplete", "response.cancelled":
            guard let response = event["response"] as? [String: Any] else {
                throw RealtimeMessageCodec.Failure.invalidEvent
            }
            usage.record(response); totalTokens = usage.totalTokens // Even stale/failed work costs tokens.
            guard let pending = try responses.finish(response, delegationID: delegation) else { return }
            guard type == "response.completed", response["status"] as? String == "completed" else {
                fail(.responseFailed, "لم يكتمل تقييم الخلفية. لم نعتمد نتيجة غير مكتملة، وأوقفنا الجلسة."); return
            }
            // Live response.output is deliberately empty. Use the completed
            // output_item events collected above, never response.done/output.
            guard !pending.calls.isEmpty else { return }
            var mutationUsed = false
            for call in pending.calls {
                guard let id = call["call_id"] as? String, !handledCalls.contains(id) else { continue }
                handledCalls.insert(id)
                let permitted = !mutationUsed && !muted && !mutePending && turns.permits(pending.lease, promptID: store.progress.session?.promptID)
                let accepted = permitted && handleTool(call)
                guard state == .connected else { return }
                if accepted { mutationUsed = true; turns.invalidate() }
                send(try LiveTutorProtocol.toolResult(callID: id, accepted: accepted, progress: store.progress, cards: store.allCards))
            }
            guard mutationUsed else {
                fail(.toolRejected, "لم يرتبط التقييم بإجابة جديدة للسؤال الحالي. بقي التقدم محفوظًا وأوقفنا الجلسة دون إعادة محاولة مدفوعة."); return
            }
            refresh()
            send(["type": "response.create", "event_id": UUID().uuidString]) // Continue backend, not voice playback.
        case "error": fail(.responseFailed, "تعذر إكمال التقييم في الخلفية. توقفت الجلسة دون اعتماد نتيجة جديدة.")
        default: break
        }
    }

    private func handleTool(_ call: [String: Any]) -> Bool {
        guard let name = call["name"] as? String else { return false }
        let arguments: [String: Any]
        do { arguments = try RealtimeMessageCodec.arguments(call["arguments"]) }
        catch { diagnostics.record(.invalidTool); return false }
        switch name {
        case "begin_quiz":
            guard store.change({ $0.beginQuiz() }) else { return false }
        case "record_answer":
            guard let prompt = arguments["prompt_id"] as? String, let card = arguments["card_id"] as? String,
                  let heard = arguments["heard_answer"] as? String, heard.count <= 1000,
                  let value = arguments["verdict"] as? String, let verdict = AudioVerdict(rawValue: value),
                  verdict == .unclear || !heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            guard store.change({ $0.record(promptID: prompt, cardID: card, verdict: verdict) }) else { return false }
            status = verdict == .correct ? "إجابة صحيحة مسجلة" : verdict == .incorrect ? "سنعيد هذا العنصر للمراجعة" : "الإجابة غير واضحة، لا تُحتسب"
        case "propose_word":
            guard proposedWord == nil,
                  let turkish = arguments["turkish"] as? String, (1...100).contains(turkish.count),
                  let arabic = arguments["arabic"] as? String, (1...300).contains(arabic.count),
                  let example = arguments["example_turkish"] as? String, (1...500).contains(example.count),
                  let translation = arguments["example_arabic"] as? String, (1...500).contains(translation.count) else { return false }
            proposedWord = AudioCard(id: "personal-\(UUID().uuidString)", kind: .personal, category: "أضفتها بصوتي", turkish: turkish,
                                    arabic: arabic, acceptedArabic: [arabic], exampleTurkish: example, exampleArabic: translation)
            setMute(true)
        default: return false
        }
        return true
    }
}

import Foundation
import Combine
import AVFoundation

private final class RealtimeNetworkPolicy: NSObject, URLSessionWebSocketDelegate {
    enum Event { case opened, closed, failed(Error, Int?) }
    private let onEvent: (Event) -> Void
    init(onEvent: @escaping (Event) -> Void) { self.onEvent = onEvent }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // Never forward the user's Authorization header to another URL.
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocolName: String?) {
        onEvent(.opened)
    }
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        onEvent(.closed) // Do not display arbitrary close reasons or protocol text.
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { onEvent(.failed(error, (task.response as? HTTPURLResponse)?.statusCode)) }
    }
}

@MainActor final class RealtimeTutor: ObservableObject {
    enum State { case stopped, connecting, connected }
    @Published private(set) var state: State = .stopped
    @Published private(set) var status = "الجلسة متوقفة"
    @Published private(set) var transcript = ""
    @Published private(set) var muted = false
    @Published var proposedWord: AudioCard?
    @Published private(set) var totalTokens = 0
    private var usage = RealtimeUsage()
    private let store: AudioProgressStore
    private let io = RealtimeAudioIO()
    private var network: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var receiver: Task<Void, Never>?
    private var sender: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var handshake: Task<Void, Never>?
    private var generation = UUID()
    @Published private(set) var diagnostics = RealtimeDiagnostics()
    private var sendBudget = RealtimeSendBudget()
    private var progressObserver: AnyCancellable?
    private var userTurnAvailable = false
    private var committedPromptID: String?
    private var responsePrompts: [String: String] = [:]
    private var handledCalls: Set<String> = []
    private var responseActive = false
    private var activeResponseID: String?
    private var interruptedResponses: Set<String> = []
    private var interruptedItems: Set<String> = []
    init(store: AudioProgressStore) {
        self.store = store
        io.onFailure = { [weak self] _ in
            guard let self, self.state != .stopped else { return }
            self.fail(.audioConversion, "تعذر تحويل صوت الميكروفون. توقفت الجلسة؛ حاول بدءها مجددًا.")
        }
        progressObserver = store.$persistenceFailure.dropFirst().sink { [weak self] failed in
            guard failed, let self, self.state != .stopped else { return }
            self.fail(.progressWrite, "لم يُحفظ التغيير. توقفت الجلسة المدفوعة والميكروفون، وبقي التقدم السابق محفوظًا.")
        }
        io.onPCM = { [weak self] data in
            guard let self, self.state == .connected, !self.muted else { return }
            self.send(["type": "input_audio_buffer.append", "audio": data.base64EncodedString()], audioBytes: data.count)
        }
    }
    func start(minutes: Int) async {
        guard state == .stopped, let session = store.progress.session, session.phase != .complete else { return }
        guard (1...10).contains(minutes) else { return }
        guard store.canUseProgress else {
            fail(.progressUnavailable, "تعذر الوصول إلى تقدم التعلم أو حفظه. لم نبدأ اتصالًا مدفوعًا؛ أعد فتح التطبيق بعد معالجة مشكلة التخزين.")
            return
        }
        diagnostics = RealtimeDiagnostics(); diagnostics.record(.starting)
        state = .connecting; status = "طلب إذن الميكروفون والاتصال"; transcript = ""; totalTokens = 0
        usage = RealtimeUsage()
        let token = UUID(); generation = token
        let permitted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard generation == token, state == .connecting else { return }
        guard !Task.isCancelled else { stop(); return }
        guard permitted else { fail(.permissionDenied, "الميكروفون غير مسموح. يمكنك السماح به من إعدادات iPhone."); return }
        do {
            guard let key = try PersonalAPIKey.read(), !key.isEmpty else {
                fail(.missingKey, "أدخل مفتاح OpenAI الشخصي في الإعدادات أولًا."); return
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil; configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = TimeInterval(minutes * 60 + 30)
            let policy = RealtimeNetworkPolicy { [weak self] event in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token, self.state != .stopped else { return }
                    switch event {
                    case .opened: self.diagnostics.record(.socketOpened)
                    case .closed: self.fail(.socketClosed, "أغلق الخادم الاتصال. توقف الميكروفون؛ يمكنك بدء جلسة جديدة بعد مراجعة السبب والتكلفة.")
                    case .failed(let error, let httpStatus): self.transportFailed(error, httpStatus: httpStatus)
                    }
                }
            }
            network = URLSession(configuration: configuration, delegate: policy, delegateQueue: nil)
            var request = URLRequest(url: AudioTutorProtocol.endpoint)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            guard let task = network?.webSocketTask(with: request) else { throw URLError(.unknown) }
            task.maximumMessageSize = 1_000_000
            socket = task; task.resume()
            handledCalls = []; interruptedItems = []; interruptedResponses = []; activeResponseID = nil; userTurnAvailable = false; muted = false
            receiver = Task { [weak self] in
                do {
                    while !Task.isCancelled {
                        let message = try await task.receive()
                        guard let self, self.generation == token else { return }
                        let data: Data
                        switch message {
                        case .string(let value): data = Data(value.utf8)
                        case .data(let value): data = value
                        @unknown default:
                            self.fail(.invalidEvent, "وصل نوع رسالة غير مدعوم. توقفت الجلسة دون تغيير التقدم."); return
                        }
                        do { try self.handle(RealtimeMessageCodec.event(data)) }
                        catch {
                            let code: RealtimeDiagnosticCode
                            switch error as? RealtimeMessageCodec.Failure {
                            case .encoding: code = .outgoingJSON
                            case .invalidAudio: code = .invalidAudio
                            case .invalidTool: code = .invalidTool
                            case .invalidEvent: code = .invalidEvent
                            default: code = .incomingJSON
                            }
                            self.fail(code, "تعذرت معالجة رسالة الجلسة. توقفت الجلسة دون إرسال بيانات ناقصة أو تغيير التقدم بسبب الرسالة.")
                            return
                        }
                    }
                } catch {
                    guard let self, self.generation == token, !Task.isCancelled else { return }
                    self.transportFailed(error, httpStatus: (task.response as? HTTPURLResponse)?.statusCode)
                }
            }
            handshake = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 20_000_000_000) } catch { return }
                guard !Task.isCancelled, let self, self.generation == token, self.state == .connecting else { return }
                self.fail(.setupTimeout, "انتهت مهلة الاتصال. تحقّق من الإنترنت والمفتاح وإتاحة النموذج في حسابك.")
            }
            deadline = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: UInt64(minutes) * 60_000_000_000) } catch { return }
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.stop("انتهت المدة التي اخترتها. يمكنك بدء جلسة جديدة بعد مراجعة التكلفة.")
            }
        } catch { fail(.keychainReadFailed, "تعذر الوصول إلى المفتاح المحفوظ أو بدء الاتصال. لم يُعرض المفتاح أو يُسجّل.") }
    }
    func stop(_ message: String = "توقفت الجلسة والميكروفون. التقدم المسجل محفوظ.") {
        if state != .stopped { status = message; diagnostics.record(.stopped) }
        generation = UUID(); state = .stopped
        receiver?.cancel(); sender?.cancel(); deadline?.cancel(); handshake?.cancel()
        receiver = nil; sender = nil; deadline = nil; handshake = nil
        if io.stop() != nil {
            diagnostics.record(.audioTeardown)
            status += "\nتوقف التسجيل والتشغيل، لكن تعذر تحرير جلسة الصوت للنظام."
        }
        socket?.cancel(with: .normalClosure, reason: nil); socket = nil
        network?.invalidateAndCancel(); network = nil
        userTurnAvailable = false; committedPromptID = nil; responsePrompts = [:]
        responseActive = false; sendBudget = RealtimeSendBudget(); muted = false
    }
    private func fail(_ code: RealtimeDiagnosticCode, _ message: String) {
        diagnostics.record(code)
        status = message + "\nرمز التشخيص: " + code.rawValue
        stop(status)
    }
    private func transportFailed(_ error: Error, httpStatus: Int?) {
        let code = RealtimeDiagnostics.networkCode(error)
        fail(code, RealtimeFailure.transport(httpStatus: httpStatus, networkCode: code))
    }
    func toggleMute() {
        guard state == .connected else { return }
        muted.toggle()
        if muted {
            userTurnAvailable = false; committedPromptID = nil; responsePrompts = [:]
            send(["type": "input_audio_buffer.clear"])
        }
        guard state == .connected else { return }
        status = muted ? "الميكروفون مكتوم" : "أستمع لإجابتك"
    }
    func beginQuiz() {
        guard state == .connected else { return }
        interruptPlayback()
        if responseActive { send(["type": "response.cancel"]); responseActive = false }
        guard state == .connected, store.change({ $0.beginQuiz() }) else { return }
        userTurnAvailable = false; committedPromptID = nil; responsePrompts = [:]
        send(["type": "input_audio_buffer.clear"])
        speakCurrentState()
    }
    func repeatQuestion() {
        guard state == .connected else { return }
        interruptPlayback()
        if responseActive { send(["type": "response.cancel"]); responseActive = false }
        userTurnAvailable = false; committedPromptID = nil; responsePrompts = [:]
        send(["type": "input_audio_buffer.clear"])
        speakCurrentState()
    }
    private func send(_ object: [String: Any], audioBytes: Int = 0) {
        // Calls already queued when stop invalidates the generation are expected.
        guard state != .stopped else { return }
        guard let socket else { fail(.networkOther, "لا يوجد اتصال نشط لإرسال الطلب."); return }
        let message: String
        do { message = try RealtimeMessageCodec.encode(object) }
        catch { fail(.outgoingJSON, "تعذر تجهيز رسالة الاتصال. توقفت الجلسة دون إرسال بيانات ناقصة."); return }
        guard sendBudget.reserve(audioBytes: audioBytes) else {
            fail(.sendBackpressure, "الشبكة بطيئة للصوت المباشر. توقفت الجلسة دون إعادة اتصال تلقائي."); return
        }
        let previous = sender, token = generation
        sender = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled, let self, self.generation == token else { return }
            do {
                try await socket.send(.string(message))
                guard self.generation == token else { return }
                self.sendBudget.release(audioBytes: audioBytes)
            } catch {
                guard self.generation == token, !Task.isCancelled else { return }
                self.transportFailed(error, httpStatus: (socket.response as? HTTPURLResponse)?.statusCode)
            }
        }
    }
    private func speakCurrentState() {
        guard state != .stopped else { return }
        do {
            let instructions = try AudioTutorProtocol.instructions(progress: store.progress, cards: store.allCards)
            send(["type": "session.update", "session": ["type": "realtime", "instructions": instructions]])
            send(["type": "response.create"])
        } catch { fail(.outgoingJSON, "تعذر تجهيز محتوى الدرس. توقفت الجلسة دون إرسال حالة ناقصة.") }
    }
    private func interruptPlayback() {
        if let responseID = activeResponseID { interruptedResponses.insert(responseID) }
        for (item, milliseconds) in io.interrupt() {
            interruptedItems.insert(item)
            send(["type": "conversation.item.truncate", "item_id": item, "content_index": 0, "audio_end_ms": milliseconds])
        }
    }
    private func handle(_ event: [String: Any]) throws {
        guard state != .stopped else { return }
        guard let type = event["type"] as? String else { throw RealtimeMessageCodec.Failure.invalidEvent }
        switch type {
        case "session.created":
            send(try AudioTutorProtocol.sessionUpdate(progress: store.progress, cards: store.allCards))
        case "session.updated":
            if state == .connecting {
                do {
                    try io.start(); state = .connected; handshake?.cancel(); diagnostics.record(.sessionReady); status = "الجلسة متصلة. الميكروفون يعمل"
                    send(["type": "response.create"])
                } catch { fail(.audioSetup, "تعذر تشغيل الصوت. أوقف المكالمات الأخرى ثم حاول مجددًا.") }
            }
        case "input_audio_buffer.speech_started": interruptPlayback()
        case "input_audio_buffer.committed":
            if !muted { committedPromptID = store.progress.session?.promptID }
        case "response.created":
            responseActive = true
            guard let response = event["response"] as? [String: Any], let responseID = response["id"] as? String, !responseID.isEmpty else { throw RealtimeMessageCodec.Failure.invalidEvent }
            activeResponseID = responseID
            if let response = event["response"] as? [String: Any],
               let id = response["id"] as? String, let prompt = committedPromptID {
                responsePrompts[id] = prompt
            }
            committedPromptID = nil
        case "response.output_audio.delta":
            guard !interruptedResponses.contains(event["response_id"] as? String ?? "") else { return }
            guard let item = event["item_id"] as? String, !item.isEmpty else { throw RealtimeMessageCodec.Failure.invalidEvent }
            guard !interruptedItems.contains(item) else { return }
            do { try io.play(RealtimeMessageCodec.audio(event["delta"]), itemID: item) }
            catch { fail(error is RealtimeMessageCodec.Failure ? .invalidAudio : .audioPlayback,
                         "تعذر تشغيل الصوت المستلم. توقفت الجلسة لحماية استقرار الصوت.") }
        case "response.output_audio_transcript.done":
            guard !interruptedResponses.contains(event["response_id"] as? String ?? "") else { return }
            guard let text = event["transcript"] as? String else { throw RealtimeMessageCodec.Failure.invalidEvent }
            transcript = String(text.prefix(4000))
        case "response.done":
            guard let response = event["response"] as? [String: Any], let identifier = response["id"] as? String, !identifier.isEmpty else { throw RealtimeMessageCodec.Failure.invalidEvent }
            let responseID = response["id"] as? String ?? ""
            if responseID == activeResponseID { responseActive = false }
            // Usage belongs to the response even when its audio/tools were cancelled.
            // Account before dropping interrupted output, without accepting its tools.
            usage.record(response)
            totalTokens = usage.totalTokens
            if interruptedResponses.contains(responseID) {
                responsePrompts.removeValue(forKey: responseID)
                return
            }
            let responsePrompt = responsePrompts.removeValue(forKey: responseID)
            userTurnAvailable = responsePrompt != nil && responsePrompt == store.progress.session?.promptID
            defer { userTurnAvailable = false }
            switch RealtimeResponseDisposition.classify(response) {
            case .stopSession(let message):
                diagnostics.record(.responseFailed)
                stop(message); return
            case .keepSession(let message):
                // response.done is generation completion, not playback completion.
                // Let queued audio finish, preserve mute/deadline and wait for the user.
                if let message { status = message; diagnostics.record(.responseInterrupted) }
                return
            case .processCompleted:
                break
            }
            guard let output = response["output"] as? [[String: Any]] else { throw RealtimeMessageCodec.Failure.invalidEvent }
            let calls = output.filter { $0["type"] as? String == "function_call" }
            var mutationUsed = false
            for call in calls {
                guard let callID = call["call_id"] as? String, !callID.isEmpty else { throw RealtimeMessageCodec.Failure.invalidTool }
                guard !handledCalls.contains(callID) else { continue }
                handledCalls.insert(callID)
                let accepted = !mutationUsed && handleTool(call)
                guard state != .stopped else { return } // A failed disk write stops paid work immediately.
                mutationUsed = mutationUsed || accepted
                let result: [String: Any] = ["accepted": accepted,
                    "state": try AudioTutorProtocol.instructions(progress: store.progress, cards: store.allCards)]
                let output = try RealtimeMessageCodec.encode(result)
                send(["type": "conversation.item.create", "item": ["type": "function_call_output", "call_id": callID, "output": output]])
            }
            if !calls.isEmpty {
                // Refresh the authoritative instructions before the next question.
                // Never allow repeated rejected calls to generate a paid response loop.
                if mutationUsed { speakCurrentState() }
                else { fail(.toolRejected, "لم يُقبل التقييم أو الطلب لأنه لم يرتبط بإجابة جديدة للسؤال الحالي. بقي التقدم السابق محفوظًا؛ يمكنك بدء الجلسة مجددًا.") }
            }
        case "error":
            let code = (event["error"] as? [String: Any])?["code"] as? String
            if code == "response_cancel_not_active" { return }
            diagnostics.record(.serviceRejected)
            stop(RealtimeFailure.service(event["error"] as? [String: Any], duringSetup: state == .connecting))
        default: break
        }
    }
    private func handleTool(_ call: [String: Any]) -> Bool {
        guard userTurnAvailable, let name = call["name"] as? String else { return false }
        let arguments: [String: Any]
        do { arguments = try RealtimeMessageCodec.arguments(call["arguments"]) }
        catch { diagnostics.record(.invalidTool); return false }
        switch name {
        case "begin_quiz":
            guard store.change({ $0.beginQuiz() }) else { return false }
        case "record_answer":
            guard let prompt = arguments["prompt_id"] as? String, let cardID = arguments["card_id"] as? String,
                  let heard = arguments["heard_answer"] as? String, heard.count <= 1000,
                  let value = arguments["verdict"] as? String, let verdict = AudioVerdict(rawValue: value),
                  verdict == .unclear || !heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            guard store.change({ $0.record(promptID: prompt, cardID: cardID, verdict: verdict) }) else { return false }
            status = verdict == .correct ? "إجابة صحيحة مسجلة" : (verdict == .incorrect ? "سنعيد هذه الكلمة أو القاعدة للمراجعة" : "الإجابة غير واضحة، لا تُحتسب")
        case "propose_word":
            guard proposedWord == nil,
                  let turkish = arguments["turkish"] as? String, (1...100).contains(turkish.count),
                  let arabic = arguments["arabic"] as? String, (1...300).contains(arabic.count),
                  let example = arguments["example_turkish"] as? String, (1...500).contains(example.count),
                  let translation = arguments["example_arabic"] as? String, (1...500).contains(translation.count) else { return false }
            proposedWord = AudioCard(id: "personal-\(UUID().uuidString)", kind: .personal, category: "أضفتها بصوتي",
                                     turkish: turkish, arabic: arabic, acceptedArabic: [arabic],
                                     exampleTurkish: example, exampleArabic: translation)
            muted = true; send(["type": "input_audio_buffer.clear"])
            guard state == .connected else { return false }
            status = "اقتراح كلمة جاهز للمراجعة. الميكروفون مكتوم حتى تعيد تشغيله."
        default: return false
        }
        userTurnAvailable = false
        return true
    }
}

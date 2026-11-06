import Foundation
import Combine
import AVFoundation

private final class RealtimeNetworkPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // Never forward the user's Authorization header to another URL.
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
    private let store: AudioProgressStore
    private let io = RealtimeAudioIO()
    private var network: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var receiver: Task<Void, Never>?
    private var sender: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var handshake: Task<Void, Never>?
    private var generation = UUID()
    private var queuedBytes = 0
    private var userTurnAvailable = false
    private var committedPromptID: String?
    private var responsePrompts: [String: String] = [:]
    private var handledCalls: Set<String> = []
    private var responseActive = false
    private var interruptedItems: Set<String> = []
    init(store: AudioProgressStore) {
        self.store = store
        io.onPCM = { [weak self] data in
            guard let self, self.state == .connected, !self.muted else { return }
            self.send(["type": "input_audio_buffer.append", "audio": data.base64EncodedString()], audioBytes: data.count)
        }
    }
    func start(minutes: Int) async {
        guard state == .stopped, let session = store.progress.session, session.phase != .complete else { return }
        guard (1...10).contains(minutes) else { return }
        state = .connecting; status = "طلب إذن الميكروفون والاتصال"; transcript = ""; totalTokens = 0
        let token = UUID(); generation = token
        let permitted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard generation == token, state == .connecting else { return }
        guard permitted else { stop("الميكروفون غير مسموح. يمكنك السماح به من إعدادات iPhone."); return }
        do {
            guard let key = try PersonalAPIKey.read(), !key.isEmpty else {
                stop("أدخل مفتاح OpenAI الشخصي في الإعدادات أولًا."); return
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil; configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = TimeInterval(minutes * 60 + 30)
            network = URLSession(configuration: configuration, delegate: RealtimeNetworkPolicy(), delegateQueue: nil)
            var request = URLRequest(url: AudioTutorProtocol.endpoint)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            guard let task = network?.webSocketTask(with: request) else { throw URLError(.unknown) }
            task.maximumMessageSize = 1_000_000
            socket = task; task.resume()
            handledCalls = []; interruptedItems = []; userTurnAvailable = false; muted = false
            receiver = Task { [weak self] in
                do {
                    while !Task.isCancelled {
                        let message = try await task.receive()
                        guard let self, self.generation == token else { return }
                        let data: Data
                        switch message {
                        case .string(let value): data = Data(value.utf8)
                        case .data(let value): data = value
                        @unknown default: continue
                        }
                        guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        self.handle(event)
                    }
                } catch {
                    guard let self, self.generation == token, !Task.isCancelled else { return }
                    self.stop("انقطع الاتصال. حُفظ التقدم السابق. اضغط البدء لإعادة الاتصال؛ لا نعيد الاتصال تلقائيًا.")
                }
            }
            handshake = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled, let self, self.generation == token, self.state == .connecting else { return }
                self.stop("انتهت مهلة الاتصال. تحقّق من الإنترنت والمفتاح وإتاحة النموذج في حسابك.")
            }
            deadline = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(minutes) * 60_000_000_000)
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.stop("انتهت المدة التي اخترتها. يمكنك بدء جلسة جديدة بعد مراجعة التكلفة.")
            }
        } catch { stop("تعذر الوصول إلى المفتاح المحفوظ أو بدء الاتصال. لم يُعرض المفتاح أو يُسجّل.") }
    }
    func stop(_ message: String = "توقفت الجلسة والميكروفون. التقدم المسجل محفوظ.") {
        generation = UUID(); state = .stopped; status = message
        receiver?.cancel(); sender?.cancel(); deadline?.cancel(); handshake?.cancel()
        receiver = nil; sender = nil; deadline = nil; handshake = nil
        io.stop(); socket?.cancel(with: .normalClosure, reason: nil); socket = nil
        network?.invalidateAndCancel(); network = nil
        userTurnAvailable = false; committedPromptID = nil; responsePrompts = [:]
        responseActive = false; queuedBytes = 0; muted = false
    }
    func toggleMute() {
        guard state == .connected else { return }
        muted.toggle()
        if muted {
            userTurnAvailable = false; committedPromptID = nil; responsePrompts = [:]
            send(["type": "input_audio_buffer.clear"])
        }
        status = muted ? "الميكروفون مكتوم" : "أستمع لإجابتك"
    }
    func beginQuiz() {
        guard state == .connected else { return }
        interruptPlayback()
        if responseActive { send(["type": "response.cancel"]); responseActive = false }
        guard store.change({ $0.beginQuiz() }) else { return }
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
        guard let socket, let data = try? JSONSerialization.data(withJSONObject: object),
              let message = String(data: data, encoding: .utf8) else { return }
        queuedBytes += audioBytes
        guard queuedBytes <= 24000 * 2 * 3 else { stop("الشبكة بطيئة للصوت المباشر. توقفت الجلسة دون إعادة اتصال تلقائي."); return }
        let previous = sender, token = generation
        sender = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled, let self, self.generation == token else { return }
            do {
                try await socket.send(.string(message))
                guard self.generation == token else { return }
                self.queuedBytes -= audioBytes
            } catch {
                guard self.generation == token else { return }
                self.stop("تعذر إرسال الصوت. توقف الاتصال وبقي تقدمك محفوظًا.")
            }
        }
    }
    private func sessionConfiguration() -> [String: Any] {
        ["type": "realtime", "model": AudioTutorProtocol.model,
         "instructions": AudioTutorProtocol.instructions(progress: store.progress, cards: store.allCards),
         "output_modalities": ["audio"], "max_output_tokens": 700,
         "audio": [
            "input": ["format": ["type": "audio/pcm", "rate": 24000],
                      "noise_reduction": ["type": "near_field"],
                      "turn_detection": ["type": "server_vad", "threshold": 0.6, "prefix_padding_ms": 300,
                                         "silence_duration_ms": 900, "create_response": true, "interrupt_response": true]],
            "output": ["format": ["type": "audio/pcm", "rate": 24000], "voice": "marin"]
         ], "tools": AudioTutorProtocol.tools, "tool_choice": "auto"]
    }
    private func speakCurrentState() {
        send(["type": "session.update", "session": ["type": "realtime",
              "instructions": AudioTutorProtocol.instructions(progress: store.progress, cards: store.allCards)]])
        send(["type": "response.create"])
    }
    private func interruptPlayback() {
        if let (item, milliseconds) = io.interrupt() {
            interruptedItems.insert(item)
            send(["type": "conversation.item.truncate", "item_id": item, "content_index": 0, "audio_end_ms": milliseconds])
        }
    }
    private func handle(_ event: [String: Any]) {
        guard let type = event["type"] as? String else { return }
        switch type {
        case "session.created": send(["type": "session.update", "session": sessionConfiguration()])
        case "session.updated":
            if state == .connecting {
                do {
                    try io.start(); state = .connected; handshake?.cancel(); status = "الجلسة متصلة. الميكروفون يعمل"
                    send(["type": "response.create"])
                } catch { stop("تعذر تشغيل الصوت. أوقف المكالمات الأخرى ثم حاول مجددًا.") }
            }
        case "input_audio_buffer.speech_started": interruptPlayback()
        case "input_audio_buffer.committed":
            if !muted { committedPromptID = store.progress.session?.promptID }
        case "response.created":
            responseActive = true
            if let response = event["response"] as? [String: Any],
               let id = response["id"] as? String, let prompt = committedPromptID {
                responsePrompts[id] = prompt
            }
            committedPromptID = nil
        case "response.output_audio.delta":
            guard let item = event["item_id"] as? String, !interruptedItems.contains(item),
                  let encoded = event["delta"] as? String, let data = Data(base64Encoded: encoded) else { return }
            do { try io.play(data, itemID: item) }
            catch { stop("تعذر تشغيل الصوت المستلم. توقفت الجلسة لحماية استقرار الصوت.") }
        case "response.output_audio_transcript.done":
            if let text = event["transcript"] as? String { transcript = String(text.prefix(4000)) }
        case "response.done":
            responseActive = false
            guard let response = event["response"] as? [String: Any] else { return }
            let responseID = response["id"] as? String ?? ""
            let responsePrompt = responsePrompts.removeValue(forKey: responseID)
            userTurnAvailable = responsePrompt != nil && responsePrompt == store.progress.session?.promptID
            defer { userTurnAvailable = false }
            if let usage = response["usage"] as? [String: Any], let count = usage["total_tokens"] as? Int, count >= 0 { totalTokens += count }
            if response["status"] as? String == "failed" { stop("فشل رد خدمة الصوت. راجع صلاحية المفتاح ورصيد حساب OpenAI."); return }
            guard response["status"] as? String == "completed" else { return }
            let calls = (response["output"] as? [[String: Any]] ?? []).filter { $0["type"] as? String == "function_call" }
            var mutationUsed = false
            for call in calls {
                guard let callID = call["call_id"] as? String, !handledCalls.contains(callID) else { continue }
                handledCalls.insert(callID)
                let accepted = !mutationUsed && handleTool(call)
                mutationUsed = mutationUsed || accepted
                let result: [String: Any] = ["accepted": accepted,
                    "state": AudioTutorProtocol.instructions(progress: store.progress, cards: store.allCards)]
                let output = (try? JSONSerialization.data(withJSONObject: result)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                send(["type": "conversation.item.create", "item": ["type": "function_call_output", "call_id": callID, "output": output]])
            }
            if !calls.isEmpty {
                // Refresh the authoritative instructions before the next question.
                // Never allow repeated rejected calls to generate a paid response loop.
                if mutationUsed { speakCurrentState() }
                else { stop("لم يُقبل التقييم أو الطلب لأنه لم يرتبط بإجابة جديدة للسؤال الحالي. بقي التقدم السابق محفوظًا؛ يمكنك بدء الجلسة مجددًا.") }
            }
        case "error":
            let code = (event["error"] as? [String: Any])?["code"] as? String
            if code == "response_cancel_not_active" { return }
            stop("رفضت خدمة الصوت الطلب. تحقّق من المفتاح والرصيد وإتاحة GPT-Realtime-2.1. لم يُكشف المفتاح.")
        default: break
        }
    }
    private func handleTool(_ call: [String: Any]) -> Bool {
        guard userTurnAvailable, let name = call["name"] as? String,
              let raw = call["arguments"] as? String, raw.utf8.count <= 8000,
              let arguments = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] else { return false }
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
            status = "اقتراح كلمة جاهز للمراجعة. الميكروفون مكتوم حتى تعيد تشغيله."
        default: return false
        }
        userTurnAvailable = false
        return true
    }
}

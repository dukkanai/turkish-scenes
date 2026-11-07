import Foundation

/// GPT-Live has its own session/event contract. It is not a Realtime model alias.
enum LiveTutorProtocol {
    static let model = "gpt-live-1"
    static let backendModel = "gpt-6-luna"
    static let endpoint = URL(string: "wss://api.openai.com/v1/live/sessions")!
    static let greeting = "ابدأ الآن بالعربية. عرّف نفسك باختصار كمعلم صوتي بالذكاء الاصطناعي، ثم اتبع مرحلة الدرس الحالية. اشرح عنصرًا واحدًا أو اسأل السؤال الحالي، ثم انتظر إجابة المتعلم."

    static func start(progress: AudioLearningProgress, cards: [AudioCard]) throws -> [String: Any] {
        let context = try AudioTutorProtocol.instructions(progress: progress, cards: cards)
        return ["type": "session.start", "event_id": UUID().uuidString, "session": [
            "model": model, "store": false,
            "instructions": """
            \(context)
            أنت واجهة المحادثة الصوتية. تنفيذ begin_quiz وrecord_answer وpropose_word يتم عبر الخلفية فقط. فوّض إلى الخلفية بعد إجابة المتعلم عن سؤال الاختبار، أو طلب بدء الاختبار، أو طلب إضافة كلمة. لا تدّع تسجيل تقدم حتى تؤكد الخلفية قبول التطبيق. لا تعلن تقييمًا نهائيًا قبل نتيجة الخلفية. لا تفوض لمجرد الصمت أو الشرح أو تكرار السؤال، ولا تستخدم تفويضًا قديمًا لتقييم سؤال جديد. انتظر المتعلم بين عناصر الشرح. توقف عن الكلام عندما يبدأ المتعلم الحديث.
            """,
            "audio": ["format": ["type": "audio/pcm", "rate": 24000], "output": ["voice": "marin"]],
            "input": [["type": "message", "role": "developer", "content": [["type": "input_text", "text": greeting]]]],
            "delegation": ["type": "responses", "responses": try backend(progress: progress, cards: cards)]
        ]]
    }

    static func backend(progress: AudioLearningProgress, cards: [AudioCard]) throws -> [String: Any] {
        ["model": backendModel, "instructions": try AudioTutorProtocol.instructions(progress: progress, cards: cards) + "\nأنت الخلفية المنطقية لا الصوت. استخدم الأدوات لتغيير التقدم، ثم أعد نتيجة قصيرة للمعلم. لا تخترع إجابة صوتية. بعد نتيجة الأداة لا تستدع أداة تغيير أخرى لنفس الإجابة. إذا رُفض الطلب أخبر المعلم أن التقدم لم يتغير.",
         "tools": AudioTutorProtocol.tools, "tool_choice": "auto", "parallel_tool_calls": false,
         "max_output_tokens": 700]
    }

    static func update(progress: AudioLearningProgress, cards: [AudioCard]) throws -> [String: Any] {
        // Initial Live instructions are immutable. Only update the Responses backend here.
        ["type": "session.update", "event_id": UUID().uuidString,
         "session": ["delegation": ["type": "responses", "responses": try backend(progress: progress, cards: cards)]]]
    }

    static func context(progress: AudioLearningProgress, repeatCurrent: Bool = false) -> [String: Any] {
        let session = progress.session
        // IDs and phase only: bounded below the 500-token append limit. The lesson
        // contents already exist in the initial context, not repeated in this event.
        let prompt = String((session?.promptID ?? "").prefix(80))
        let card = String((session?.currentID ?? "").prefix(80))
        let text = "حالة التطبيق المعتمدة الآن: phase=\(session?.phase.rawValue ?? "none")، prompt_id=\(prompt)، current_id=\(card). تجاهل السؤال السابق. \(repeatCurrent ? "أعد السؤال الحالي أو شرح عنصر واحد دون كشف إجابة الاختبار، ثم انتظر." : "اتبع المرحلة والعنصر الحاليين، ولا تقيّم قبل إجابة جديدة.")"
        return append("session.instructions.append", content: text)
    }

    static func append(_ type: String, content: String) -> [String: Any] {
        ["type": type, "event_id": UUID().uuidString, "delegation_id": NSNull(), "content": content]
    }

    static func toolResult(callID: String, accepted: Bool, progress: AudioLearningProgress, cards: [AudioCard]) throws -> [String: Any] {
        let output = try RealtimeMessageCodec.encode(["accepted": accepted,
            "state": try AudioTutorProtocol.instructions(progress: progress, cards: cards)])
        return ["type": "response.item.create", "event_id": UUID().uuidString,
                "item": ["type": "function_call_output", "call_id": callID, "output": output]]
    }
}

import Foundation

@main struct RealtimeResponseChecks {
    static func main() throws {
        func event(_ status: String, reason: Any? = nil) -> [String: Any] {
            var details: [String: Any] = ["type": status]
            if let reason { details["reason"] = reason }
            return ["id": "response-test", "status": status, "status_details": details,
                    "usage": ["total_tokens": 700],
                    "output": [["type": "function_call", "name": "record_answer", "arguments": "{}"]]]
        }
        let completed = RealtimeResponseDisposition.classify(event("completed"))
        assert(completed == .processCompleted)
        for reason in ["max_output_tokens", "content_filter"] {
            let wire = try JSONSerialization.data(withJSONObject: ["type": "response.done", "response": event("incomplete", reason: reason)])
            let decoded = try JSONSerialization.jsonObject(with: wire) as! [String: Any]
            let result = RealtimeResponseDisposition.classify(decoded["response"] as! [String: Any])
            guard case .keepSession(let message) = result else { fatalError("Incomplete response must not close the session or execute its tools") }
            assert(message?.contains(reason) == true)
            assert(message?.contains("الجلسة ما زالت متصلة") == true)
            assert(message?.contains("لم نحتسب تقييمًا ناقصًا") == true)
            assert(message?.contains("لم نطلب ردًا جديدًا تلقائيًا") == true)
        }
        let unknown = RealtimeResponseDisposition.classify(event("incomplete"))
        guard case .keepSession(let message) = unknown else { fatalError("Missing reason must not become a fatal transport failure") }
        assert(message?.contains("لم يصل سبب معروف") == true)
        for reason in ["turn_detected", "client_cancelled", "max_output_tokens"] {
            assert(RealtimeResponseDisposition.classify(event("cancelled", reason: reason)) == .keepSession(message: nil))
        }
        for status in ["in_progress", "unknown", ""] {
            assert(RealtimeResponseDisposition.classify(event(status)) == .keepSession(message: nil))
        }
        for reason in [NSNull(), 700, ["max_output_tokens"], "private@example.test", "sk-" + String(repeating: "x", count: 40), String(repeating: "x", count: 100_000)] as [Any] {
            assert(RealtimeResponseDisposition.classify(event("incomplete", reason: reason)) == unknown)
        }
        let missingDetails: [String: Any] = ["status": "incomplete", "status_details": NSNull(), "message": "private text"]
        assert(RealtimeResponseDisposition.classify(missingDetails) == unknown)
        let failure: [String: Any] = ["status": "failed", "status_details": ["error": ["code": "insufficient_quota", "message": "private text"]]]
        guard case .stopSession(let failureMessage) = RealtimeResponseDisposition.classify(failure) else { fatalError("Real service failures retain the fail-closed policy") }
        assert(failureMessage.contains("حصة استخدام API") && !failureMessage.contains("private text"))
        // Independent consecutive turns: an incomplete/cancelled response must not
        // poison the next completed response or authorize its own partial tool call.
        let sequence = [event("incomplete", reason: "max_output_tokens"), event("cancelled", reason: "turn_detected"), event("completed")]
        let outcomes = sequence.map(RealtimeResponseDisposition.classify)
        assert(outcomes.filter { $0 == .processCompleted }.count == 1)
        print("PASS: incomplete/cancelled responses keep the session, completed-only tools, safe reasons and later turns")
    }
}

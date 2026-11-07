import Foundation

@main struct RealtimeUsageChecks {
    static func main() throws {
        func response(_ id: String, _ status: String, _ tokens: String) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: Data("""
            {"id":"\(id)","status":"\(status)","usage":{"total_tokens":\(tokens)}}
            """.utf8)) as! [String: Any]
        }
        var usage = RealtimeUsage()
        let completed = try response("completed", "completed", "100")
        usage.record(completed)
        assert(usage.totalTokens == 100)
        // A response interrupted before response.done still incurred reported usage.
        let interrupted = try response("interrupted", "cancelled", "40")
        usage.record(interrupted)
        assert(usage.totalTokens == 140)
        usage.record(interrupted)
        usage.record(completed)
        assert(usage.totalTokens == 140, "Duplicate response IDs must not double count")
        usage.record(try response("failed", "failed", "8"))
        usage.record(try response("incomplete", "incomplete", "12"))
        assert(usage.totalTokens == 160, "Count reported usage independently of completion status")
        usage.record(["id": "pending", "status": "cancelled", "usage": NSNull()])
        usage.record(try response("negative", "completed", "-1"))
        usage.record(try response("string", "completed", "\"50\""))
        usage.record(try response("bool", "completed", "true"))
        usage.record(try response("fraction", "completed", "1.5"))
        usage.record(try response("", "completed", "30"))
        assert(usage.totalTokens == 160, "Malformed or absent usage is not a token count")
        usage.record(try response("pending", "cancelled", "5"))
        assert(usage.totalTokens == 165, "Missing usage must not prevent a later valid report")
        usage.record(["id": "overflow", "usage": ["total_tokens": Int.max]])
        assert(usage.totalTokens == 165, "Unexpected counts must not overflow and crash")
        usage = RealtimeUsage()
        usage.record(interrupted)
        assert(usage.totalTokens == 40, "A new session resets totals and response deduplication")
        print("PASS: interrupted, cancelled, failed, duplicate, malformed and reset response usage")
    }
}

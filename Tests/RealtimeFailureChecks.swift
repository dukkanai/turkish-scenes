import Foundation

@main struct RealtimeFailureChecks {
    static func main() {
        let invalid: [String: Any] = ["code": "unknown_parameter", "type": "invalid_request_error",
                                     "param": "session.model", "message": "Do not display this server message"]
        let diagnostic = RealtimeFailure.service(invalid, duringSetup: true)
        assert(diagnostic.contains("unknown_parameter") && diagnostic.contains("session.model"))
        assert(diagnostic.contains("invalid_request_error") && diagnostic.contains("تهيئة الجلسة"))
        assert(diagnostic.contains("لا يثبت وجود مشكلة في المفتاح أو الرصيد"))
        assert(!diagnostic.contains("Do not display"))
        let quota = RealtimeFailure.service(["code": "insufficient_quota"], duringSetup: false)
        assert(quota.contains("حصة استخدام API") && quota.contains("المحادثة الصوتية"))
        let rate = RealtimeFailure.service(["code": "rate_limit_exceeded"], duringSetup: false)
        assert(rate.contains("حد الاستخدام المؤقت") && !rate.contains("فوترة"))
        let badKey = RealtimeFailure.service(["code": "invalid_api_key"], duringSetup: true)
        assert(badKey.contains("مصادقة المفتاح") && badKey.contains("لا ترسله لأحد"))
        let unknown = RealtimeFailure.service(nil, duringSetup: true)
        assert(unknown.contains("لا تتوفر تفاصيل آمنة كافية") && unknown.contains("غير معروف"))
        let nulls = RealtimeFailure.service(["code": NSNull(), "type": 1, "param": ["session.model"]], duringSetup: false)
        assert(nulls.contains("غير معروف") && !nulls.contains("session.model"))
        // Even plausible-looking unknown codes/parameters are not echoed. Syntax
        // checks alone would allow an API key, transcript, or account ID to leak.
        for value in ["fake_private_credential", "sk-" + String(repeating: "x", count: 40),
                      "Authorization: Bearer private", "session.instructions.private_text",
                      "private@example.test", "secret\nunknown_parameter", String(repeating: "x", count: 100_000)] {
            let result = RealtimeFailure.service(["code": value, "type": value, "param": value,
                                                 "message": value, "event_id": value], duringSetup: false)
            assert(!result.contains(value))
            assert(result == RealtimeFailure.service(nil, duringSetup: false))
        }
        for status in [401, 403, 404, 429, 500, 502, 503, 504] {
            assert(RealtimeFailure.transport(httpStatus: status).contains("HTTP \(status)"))
        }
        let throttled = RealtimeFailure.transport(httpStatus: 429)
        assert(throttled.contains("لا يمكن الجزم"))
        for status in [nil, 101, 200, 400, 999] as [Int?] {
            assert(RealtimeFailure.transport(httpStatus: status).contains("دون رمز خطأ خدمة محدد"))
        }
        print("PASS: actionable error categories, stage, parameter, HTTP statuses and secret-safe diagnostics")
    }
}

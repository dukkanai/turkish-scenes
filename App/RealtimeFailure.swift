import Foundation

/// Only fixed, reviewed diagnostic values reach the UI. Never display the raw
/// service message, request, URL, headers, event IDs, or arbitrary server text.
enum RealtimeFailure {
    private static let codes: Set<String> = [
        "invalid_api_key", "insufficient_quota", "rate_limit_exceeded", "model_not_found",
        "permission_denied", "invalid_request_error", "unknown_parameter", "unsupported_parameter",
        "invalid_value", "unsupported_value", "invalid_type", "missing_required_parameter",
        "invalid_event", "invalid_json", "invalid_function_parameters", "invalid_tool_schema",
        "session_expired", "server_error", "internal_error", "content_filter",
        "conversation_already_has_active_response", "input_audio_buffer_commit_empty",
        "conversation_item_truncate_audio_end_mismatch", "response_cancel_not_active"
    ]
    private static let types: Set<String> = [
        "invalid_request_error", "authentication_error", "permission_error", "not_found_error",
        "rate_limit_error", "server_error", "insufficient_quota"
    ]
    private static let parameters: Set<String> = [
        "model", "session", "session.type", "session.model", "session.instructions",
        "session.output_modalities", "session.max_output_tokens", "session.audio",
        "session.audio.input", "session.audio.input.format", "session.audio.input.format.type",
        "session.audio.input.format.rate", "session.audio.input.noise_reduction",
        "session.audio.input.noise_reduction.type", "session.audio.input.turn_detection",
        "session.audio.input.turn_detection.type", "session.audio.input.turn_detection.threshold",
        "session.audio.input.turn_detection.prefix_padding_ms",
        "session.audio.input.turn_detection.silence_duration_ms",
        "session.audio.input.turn_detection.create_response",
        "session.audio.input.turn_detection.interrupt_response",
        "session.audio.output", "session.audio.output.format", "session.audio.output.format.type",
        "session.audio.output.format.rate", "session.audio.output.voice",
        "session.tools", "session.tool_choice", "response", "response.id", "response_id",
        "item", "item_id", "content_index", "audio_end_ms", "audio", "type"
    ]

    private static func known(_ value: Any?, in allowed: Set<String>) -> String? {
        guard let value = value as? String, allowed.contains(value) else { return nil }
        return value
    }

    static func service(_ error: [String: Any]?, duringSetup: Bool) -> String {
        let code = known(error?["code"], in: codes)
        let type = known(error?["type"], in: types)
        let parameter = known(error?["param"], in: parameters)
        let explanation: String
        switch code {
        case "invalid_api_key":
            explanation = "رفض OpenAI مصادقة المفتاح. راجعه داخل إعدادات التطبيق ولا ترسله لأحد."
        case "insufficient_quota":
            explanation = "أبلغ OpenAI أن حصة استخدام API غير كافية. راجع فوترة API وحدود المشروع."
        case "rate_limit_exceeded":
            explanation = "أبلغ OpenAI ببلوغ حد الاستخدام المؤقت. انتظر قبل بدء جلسة أخرى."
        case "model_not_found", "permission_denied":
            explanation = "رفض OpenAI الوصول المطلوب. راجع إتاحة النموذج وصلاحيات مشروع API."
        case "session_expired":
            explanation = "أبلغ OpenAI بانتهاء الجلسة. يمكنك بدء جلسة جديدة بعد مراجعة التكلفة."
        default:
            if type == "invalid_request_error" {
                explanation = "رفض OpenAI صيغة طلب أرسله التطبيق. هذا لا يثبت وجود مشكلة في المفتاح أو الرصيد."
            } else if type == "server_error" || code == "server_error" || code == "internal_error" {
                explanation = "أبلغ OpenAI بخلل في الخدمة. توقفت الجلسة دون إعادة اتصال تلقائي."
            } else {
                explanation = "رفض OpenAI الطلب. لا تتوفر تفاصيل آمنة كافية لتحديد السبب."
            }
        }
        let phase = duringSetup ? "تهيئة الجلسة" : "المحادثة الصوتية"
        var details = ["المرحلة: \(phase)", "الرمز: \(code ?? "غير معروف")"]
        if let type { details.append("النوع: \(type)") }
        if let parameter { details.append("الحقل: \(parameter)") }
        return explanation + "\n" + details.joined(separator: "، ") + "\nتوقف الميكروفون. لم يُعرض المفتاح أو يُسجّل."
    }

    static func transport(httpStatus: Int?, networkCode: RealtimeDiagnosticCode = .networkOther) -> String {
        switch httpStatus {
        case 401: return "رفض OpenAI مصادقة الاتصال (HTTP 401). راجع المفتاح داخل التطبيق ولا ترسله لأحد."
        case 403: return "رفض OpenAI صلاحية الاتصال (HTTP 403). راجع صلاحيات مشروع API وإتاحة الخدمة."
        case 404: return "لم يجد OpenAI المورد المطلوب (HTTP 404). يلزم التحقق من النموذج والعنوان والصلاحيات."
        case 429: return "رفض OpenAI الاتصال بحد استخدام (HTTP 429). قد يكون حدًا مؤقتًا أو حصة API؛ لا يمكن الجزم من هذا الرمز وحده."
        case 500, 502, 503, 504: return "تعذر الاتصال بخدمة OpenAI بسبب خطأ خادم (HTTP \(httpStatus!)). حاول لاحقًا."
        default:
            let reason: String
            switch networkCode {
            case .networkOffline: reason = "الجهاز غير متصل بالإنترنت."
            case .networkTimeout: reason = "انتهت مهلة طلب الشبكة."
            case .networkDNS: reason = "تعذر العثور على عنوان خدمة الاتصال."
            case .networkTLS: reason = "تعذر التحقق من أمان الاتصال. لم نتجاوز فحص الشهادة."
            case .networkLost: reason = "فُقد اتصال الشبكة أو تعذر الوصول إلى الخادم."
            default: reason = "انقطع الاتصال دون رمز خطأ خدمة محدد."
            }
            return reason + " حُفظ التقدم السابق. اضغط البدء لإعادة الاتصال؛ لا نعيد الاتصال تلقائيًا."
        }
    }
}

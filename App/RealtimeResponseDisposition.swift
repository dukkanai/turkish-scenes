import Foundation

/// Ending one response does not end the WebSocket session or drain audio playback.
/// Only completed responses may advance learning through tools.
enum RealtimeResponseDisposition: Equatable {
    case processCompleted
    case keepSession(message: String?)
    case stopSession(message: String)

    static func classify(_ response: [String: Any]) -> Self {
        switch response["status"] as? String {
        case "completed": return .processCompleted
        case "failed":
            let details = response["status_details"] as? [String: Any]
            return .stopSession(message: RealtimeFailure.service(details?["error"] as? [String: Any], duringSetup: false))
        case "incomplete":
            let details = response["status_details"] as? [String: Any]
            let explanation: String
            // Never echo arbitrary server text, IDs, tool arguments or error messages.
            switch details?["reason"] as? String {
            case "max_output_tokens":
                explanation = "بلغ الرد حد طوله (max_output_tokens). يمكنك طلب شرح أقصر أو إعادة السؤال."
            case "content_filter":
                explanation = "أوقف مرشح المحتوى هذا الرد (content_filter). يمكنك طرح سؤال تعليمي آخر."
            default:
                explanation = "لم يكتمل هذا الرد، ولم يصل سبب معروف. يمكنك طلب شرح أقصر أو إعادة السؤال."
            }
            return .keepSession(message: explanation + "\nالجلسة ما زالت متصلة. لم نحتسب تقييمًا ناقصًا ولم نطلب ردًا جديدًا تلقائيًا.")
        default:
            // Cancelled responses (turn_detected/client_cancelled), malformed or
            // future statuses never execute tools or request another paid response.
            return .keepSession(message: nil)
        }
    }
}

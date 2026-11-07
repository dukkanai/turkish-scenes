import Foundation
import CoreFoundation

/// Session-local API-reported token counts, not a currency or invoice estimate.
struct RealtimeUsage {
    private(set) var totalTokens = 0
    private var countedResponses: Set<String> = []

    mutating func record(_ response: [String: Any]) {
        guard let id = response["id"] as? String, !id.isEmpty,
              !countedResponses.contains(id),
              let usage = response["usage"] as? [String: Any],
              let number = usage["total_tokens"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              let count = usage["total_tokens"] as? Int, count >= 0 else { return }
        let (sum, overflow) = totalTokens.addingReportingOverflow(count)
        guard !overflow else { return }
        countedResponses.insert(id)
        totalTokens = sum
    }
}

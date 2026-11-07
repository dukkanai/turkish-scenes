import Foundation
import CoreFoundation

/// In-memory counters only. Live duration snapshots are cumulative, not additive.
struct LiveSessionUsage {
    private(set) var seconds: Double = 0
    private(set) var finalized = false
    mutating func record(_ event: [String: Any], final: Bool = false) {
        guard let usage = event["usage"] as? [String: Any], let number = usage["seconds"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return }
        let value = number.doubleValue
        guard value.isFinite, (0...86_400).contains(value) else { return }
        seconds = max(seconds, value)
        if final { finalized = true }
    }
}

/// Live has no committed-input/response turn boundary. Require fresh timed input
/// and bind a backend response to the prompt that existed when it started.
/// Missing/delayed evidence fails closed rather than awarding progress.
struct LiveTurnLedger {
    struct Lease { let promptID: String; let revision: Int; let inputSerial: Int }
    private var revision = 0
    private var inputSerial = 0
    private var consumedSerial = 0
    private var inputEnd = 0
    private var outputEnd = 0
    private var boundary = 0
    private var seenInput: Set<String> = []
    private var awaitingQuestion = true
    private var needsFreshUtterance = true

    mutating func input(_ event: [String: Any], muted: Bool) throws {
        guard let text = event["delta"] as? String, text.utf8.count <= 16_000,
              let start = Self.time(event["start_ms"]), let end = Self.time(event["end_ms"]), end >= start else {
            throw RealtimeMessageCodec.Failure.invalidEvent
        }
        // Observe even muted/discarded fragments so they cannot be replayed
        // after unmute or mistaken for the next prompt's answer.
        guard let id = event["event_id"] as? String, !id.isEmpty, id.count <= 512 else {
            throw RealtimeMessageCodec.Failure.invalidEvent
        }
        guard !seenInput.contains(id) else { return }
        guard seenInput.count < 10_000 else { throw RealtimeMessageCodec.Failure.invalidEvent }
        seenInput.insert(id)
        let previousEnd = inputEnd
        inputEnd = max(inputEnd, end)
        guard !muted, !awaitingQuestion, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              start >= boundary, end > boundary, end > previousEnd else { return }
        // Live has no turn-ended event. A fresh question and a conservative
        // gap distinguish a new utterance from delayed fragments of the old one.
        // Missing evidence rejects progress; transcript timing is not speech VAD.
        if needsFreshUtterance, previousEnd > 0, start < previousEnd + 500 { return }
        needsFreshUtterance = false
        inputSerial += 1
    }
    mutating func output(_ event: [String: Any]) throws -> String {
        guard let text = event["delta"] as? String, text.utf8.count <= 16_000,
              let start = Self.time(event["start_ms"]), let end = Self.time(event["end_ms"]), end >= start else {
            throw RealtimeMessageCodec.Failure.invalidEvent
        }
        outputEnd = max(outputEnd, end)
        if needsFreshUtterance, start >= boundary, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            awaitingQuestion = false
            boundary = max(boundary, end)
        }
        return text // Preserve fragment spacing and repeated words exactly.
    }
    func lease(promptID: String?) -> Lease? {
        guard let promptID, inputSerial > consumedSerial else { return nil }
        return Lease(promptID: promptID, revision: revision, inputSerial: inputSerial)
    }
    func permits(_ lease: Lease?, promptID: String?) -> Bool {
        guard let lease else { return false }
        return lease.promptID == promptID && lease.revision == revision && lease.inputSerial > consumedSerial
    }
    mutating func invalidate() {
        revision += 1; consumedSerial = inputSerial; boundary = max(inputEnd, outputEnd)
        awaitingQuestion = true; needsFreshUtterance = true
    }
    private static func time(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let time = value as? Int, (0...86_400_000).contains(time) else { return nil }
        return time
    }
}

/// Nested Responses output-item events have no response_id. Match their outer
/// Live delegation_id to the ID captured from response.created.
struct LiveResponseRegistry {
    struct Pending {
        let delegationID: String?
        let lease: LiveTurnLedger.Lease?
        var calls: [[String: Any]] = []
    }
    private var pending: [String: Pending] = [:]
    private var activeByDelegation: [String: String] = [:]
    private var completed: Set<String> = []

    mutating func created(_ response: [String: Any], delegationID: String?, lease: LiveTurnLedger.Lease?) throws {
        guard let id = response["id"] as? String, !id.isEmpty, id.count <= 512,
              pending.count < 12, completed.count < 120 else {
            throw RealtimeMessageCodec.Failure.invalidEvent
        }
        if let delegationID, delegationID.isEmpty || delegationID.count > 512 { throw RealtimeMessageCodec.Failure.invalidEvent }
        guard pending[id] == nil, !completed.contains(id) else { return }
        let key = delegationID ?? ""
        guard activeByDelegation[key] == nil else { throw RealtimeMessageCodec.Failure.invalidEvent }
        pending[id] = Pending(delegationID: delegationID, lease: lease)
        activeByDelegation[key] = id
    }

    mutating func itemDone(_ event: [String: Any], delegationID: String?) throws {
        guard let item = event["item"] as? [String: Any] else { throw RealtimeMessageCodec.Failure.invalidEvent }
        guard item["type"] as? String == "function_call" else { return }
        guard let id = activeByDelegation[delegationID ?? ""], var response = pending[id],
              response.delegationID == delegationID,
              item["status"] == nil || item["status"] as? String == "completed",
              let callID = item["call_id"] as? String, !callID.isEmpty, callID.count <= 512 else {
            throw RealtimeMessageCodec.Failure.invalidTool
        }
        guard !response.calls.contains(where: { $0["call_id"] as? String == callID }) else { return }
        guard response.calls.count < 3 else { throw RealtimeMessageCodec.Failure.invalidTool }
        response.calls.append(item); pending[id] = response
    }

    mutating func finish(_ response: [String: Any], delegationID: String?) throws -> Pending? {
        guard let id = response["id"] as? String, !id.isEmpty else { throw RealtimeMessageCodec.Failure.invalidEvent }
        guard !completed.contains(id) else { return nil }
        guard let result = pending[id], result.delegationID == delegationID else { throw RealtimeMessageCodec.Failure.invalidEvent }
        pending.removeValue(forKey: id); completed.insert(id)
        activeByDelegation.removeValue(forKey: delegationID ?? "")
        return result
    }
}

import Foundation

@main struct LiveProtocolChecks {
    static func rejects(_ action: () throws -> Void) {
        do { try action(); assertionFailure("Expected rejection") } catch {}
    }
    static func main() throws {
        let progress = AudioLearningProgress()
        let event = try LiveTutorProtocol.start(progress: progress, cards: [])
        let wire = try RealtimeMessageCodec.encode(event)
        let decoded = try RealtimeMessageCodec.event(Data(wire.utf8))
        assert(decoded["type"] as? String == "session.start")
        assert(LiveTutorProtocol.endpoint.absoluteString == "wss://api.openai.com/v1/live/sessions")
        assert(LiveTutorProtocol.endpoint.query == nil)
        let session = decoded["session"] as! [String: Any]
        assert(session["model"] as? String == "gpt-live-1" && session["store"] as? Bool == false)
        assert(session["type"] == nil && session["tools"] == nil && session["output_modalities"] == nil)
        let audio = session["audio"] as! [String: Any]
        assert((audio["format"] as! [String: Any])["rate"] as? Int == 24000)
        assert(audio["input"] == nil && (audio["output"] as! [String: String])["voice"] == "marin")
        let delegation = session["delegation"] as! [String: Any]
        assert(delegation["type"] as? String == "responses")
        let backend = delegation["responses"] as! [String: Any]
        assert(backend["model"] as? String == "gpt-6-luna")
        assert(backend["parallel_tool_calls"] as? Bool == false && backend["max_output_tokens"] as? Int == 700)
        assert(Set((backend["tools"] as! [[String: Any]]).compactMap { $0["name"] as? String }) == ["begin_quiz", "record_answer", "propose_word"])
        assert((session["input"] as! [[String: Any]]).count == 1)
        let update = try LiveTutorProtocol.update(progress: progress, cards: [])
        assert(Set((update["session"] as! [String: Any]).keys) == ["delegation"])
        let context = LiveTutorProtocol.context(progress: progress)
        assert(context["type"] as? String == "session.instructions.append")
        assert(context["delegation_id"] is NSNull)
        assert((context["content"] as! String).count < 500)
        let result = try LiveTutorProtocol.toolResult(callID: "call_1", accepted: true, progress: progress, cards: [])
        assert(result["type"] as? String == "response.item.create")
        assert((result["item"] as! [String: Any])["call_id"] as? String == "call_1")

        var usage = LiveSessionUsage()
        usage.record(["usage": ["seconds": 12]])
        usage.record(["usage": ["seconds": 15.5]])
        usage.record(["usage": ["seconds": 14]])
        assert(usage.seconds == 15.5 && !usage.finalized)
        let invalidValues: [Any] = [true, -1, Double.infinity, Double.nan, "30", 100_000]
        for invalid in invalidValues {
            usage.record(["usage": ["seconds": invalid]], final: true)
            assert(usage.seconds == 15.5 && !usage.finalized)
        }
        usage.record(["usage": ["seconds": 18.5]], final: true)
        assert(usage.seconds == 18.5 && usage.finalized)

        var turns = LiveTurnLedger()
        func input(_ id: String, _ start: Int, _ end: Int) -> [String: Any] {
            ["event_id": id, "delta": "إجابة", "start_ms": start, "end_ms": end]
        }
        func output(_ start: Int, _ end: Int) -> [String: Any] {
            ["delta": " نعم نعم", "start_ms": start, "end_ms": end]
        }
        assert(turns.lease(promptID: "prompt1") == nil)
        try turns.input(input("i0", 10, 20), muted: true)
        assert(turns.lease(promptID: "prompt1") == nil)
        let fragment = try turns.output(output(100, 200))
        assert(fragment == " نعم نعم")
        try turns.input(input("i0", 10, 20), muted: false) // Muted event cannot be replayed.
        try turns.input(input("i1", 800, 1000), muted: false)
        let lease = turns.lease(promptID: "prompt1")
        assert(turns.permits(lease, promptID: "prompt1"))
        assert(!turns.permits(lease, promptID: "prompt2"))
        turns.invalidate()
        assert(!turns.permits(lease, promptID: "prompt1"))
        try turns.input(input("i1", 800, 1000), muted: false)
        try turns.input(input("tail", 1000, 1100), muted: false) // Continued old utterance.
        try turns.input(input("early", 1700, 1800), muted: false) // No new question yet.
        assert(turns.lease(promptID: "prompt2") == nil)
        _ = try turns.output(output(50, 60)) // Stale output cannot open the next question.
        try turns.input(input("stillEarly", 2400, 2500), muted: false)
        assert(turns.lease(promptID: "prompt2") == nil)
        _ = try turns.output(output(2600, 2700))
        try turns.input(input("tooSoon", 2800, 2900), muted: false) // Not a fresh utterance gap.
        assert(turns.lease(promptID: "prompt2") == nil)
        try turns.input(input("i2", 3500, 3700), muted: false)
        let newLease = turns.lease(promptID: "prompt2")
        assert(turns.permits(newLease, promptID: "prompt2"))
        rejects { try turns.input(["event_id": "bad", "delta": "x", "start_ms": true, "end_ms": 30], muted: false) }
        rejects { try turns.input(input("bad2", 120, 100), muted: false) }

        var responses = LiveResponseRegistry()
        try responses.created(["id": "r1"], delegationID: "d1", lease: newLease)
        try responses.created(["id": "r2"], delegationID: "d2", lease: nil)
        let item: [String: Any] = ["type": "function_call", "status": "completed", "call_id": "c1", "name": "record_answer", "arguments": "{}"]
        let done: [String: Any] = ["type": "response.output_item.done", "item": item, "output_index": 0, "sequence_number": 1]
        assert(done["response_id"] == nil) // Exact documented shape, not Realtime.
        try responses.itemDone(done, delegationID: "d1")
        try responses.itemDone(done, delegationID: "d1") // Duplicate output is idempotent.
        let finished = try responses.finish(["id": "r1", "output": []], delegationID: "d1")
        assert(finished?.calls.count == 1 && finished?.lease?.promptID == "prompt2")
        let second = try responses.finish(["id": "r2", "output": []], delegationID: "d2")
        assert(second?.calls.isEmpty == true)
        let duplicate = try responses.finish(["id": "r1"], delegationID: "d1")
        assert(duplicate == nil)
        rejects { try responses.itemDone(done, delegationID: "unknown") }
        try responses.created(["id": "r3"], delegationID: "d3", lease: nil)
        rejects { try responses.created(["id": "r4"], delegationID: "d3", lease: nil) }
        rejects { _ = try responses.finish(["id": "r3"], delegationID: "d4") }
        var badItem = item; badItem["status"] = "incomplete"
        rejects { try responses.itemDone(["item": badItem], delegationID: "d3") }
        print("PASS: Live wire configuration, nested delegation correlation, fresh-input guards, cumulative usage and malformed event rejection")
    }
}

import Foundation

@main struct RealtimeDiagnosticsChecks {
    static func main() throws {
        var diagnostics = RealtimeDiagnostics()
        diagnostics.record(.starting); diagnostics.record(.starting)
        assert(diagnostics.entries.count == 1)
        for _ in 0..<40 { diagnostics.record(.socketOpened); diagnostics.record(.networkLost) }
        assert(diagnostics.entries.count == RealtimeDiagnostics.capacity)
        assert(Set(diagnostics.entries.map(\.id)).count == diagnostics.entries.count)
        let secret = "private text, Authorization and key material must never be reflected"
        let urlError = NSError(domain: NSURLErrorDomain, code: URLError.notConnectedToInternet.rawValue,
                               userInfo: [NSLocalizedDescriptionKey: secret, NSURLErrorFailingURLStringErrorKey: secret])
        assert(RealtimeDiagnostics.networkCode(urlError) == .networkOffline)
        assert(RealtimeDiagnostics.networkCode(NSError(domain: secret, code: -1009)) == .networkOther)
        let cases: [(URLError.Code, RealtimeDiagnosticCode)] = [
            (.timedOut, .networkTimeout), (.dnsLookupFailed, .networkDNS),
            (.serverCertificateUntrusted, .networkTLS), (.networkConnectionLost, .networkLost),
            (.cancelled, .networkOther)
        ]
        for (error, expected) in cases { assert(RealtimeDiagnostics.networkCode(URLError(error)) == expected) }
        assert(!String(describing: diagnostics.entries).contains(secret))

        var budget = RealtimeSendBudget()
        assert(budget.reserve(audioBytes: 144_000))
        assert(!budget.reserve(audioBytes: 1))
        assert(!budget.reserve(audioBytes: -1))
        budget.release(audioBytes: 144_000)
        assert(budget.bytes == 0 && budget.messages == 0)
        for _ in 0..<RealtimeSendBudget.maximumMessages { assert(budget.reserve(audioBytes: 0)) }
        assert(!budget.reserve(audioBytes: 0))
        budget.release(audioBytes: 0)
        assert(budget.reserve(audioBytes: 0))

        let encoded = try RealtimeMessageCodec.encode(["type": "event", "value": [1, 2]])
        let decoded = try RealtimeMessageCodec.event(Data(encoded.utf8))
        assert(decoded["type"] as? String == "event")
        expectThrow { _ = try RealtimeMessageCodec.encode(["unsupported": Date()]) }
        expectThrow { _ = try RealtimeMessageCodec.encode(["number": Double.infinity]) }
        expectThrow { _ = try RealtimeMessageCodec.encode(["huge": String(repeating: "x", count: 1_000_001)]) }
        for text in ["", "{", "[]", "null", "{}", "{\"type\":3}", "{\"type\":\"\"}"] {
            expectThrow { _ = try RealtimeMessageCodec.event(Data(text.utf8)) }
        }
        expectThrow { _ = try RealtimeMessageCodec.event(Data(repeating: 0, count: 1_000_001)) }
        // Unknown event names remain forward-compatible but do not enter diagnostics.
        let unknown = try RealtimeMessageCodec.event(Data("{\"type\":\"future.event\"}".utf8))
        assert(unknown["type"] as? String == "future.event")
        let audio = Data([0, 0, 1, 255])
        let decodedAudio = try RealtimeMessageCodec.audio(audio.base64EncodedString())
        assert(decodedAudio == audio)
        for input in [NSNull(), "", "not base64", Data([1]).base64EncodedString(), Data(repeating: 0, count: 512_002).base64EncodedString()] as [Any] {
            expectThrow { _ = try RealtimeMessageCodec.audio(input) }
        }
        let arguments = try RealtimeMessageCodec.arguments("{}")
        assert(arguments.isEmpty)
        for input in [NSNull(), "[]", "null", "broken", String(repeating: "x", count: 8_001)] as [Any] {
            expectThrow { _ = try RealtimeMessageCodec.arguments(input) }
        }
        print("PASS: bounded redacted diagnostics, network categories, bounded sends, fail-closed JSON/audio/tool parsing")
    }
    static func expectThrow(_ operation: () throws -> Void) {
        do { try operation(); assertionFailure("Expected rejection") } catch { }
    }
}

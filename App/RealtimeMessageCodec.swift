import Foundation

/// Throw at actual fallible boundaries instead of hiding failures with try?.
/// No error carries payload text, keys, transcripts, request IDs or URLs.
enum RealtimeMessageCodec {
    enum Failure: Error { case encoding, decoding, invalidEvent, invalidAudio, invalidTool }
    static let maximumMessageBytes = 1_000_000

    static func encode(_ object: [String: Any]) throws -> String {
        // JSONSerialization may raise an Objective-C exception for invalid
        // objects; Swift catch cannot catch that. Validate before calling it.
        guard JSONSerialization.isValidJSONObject(object) else { throw Failure.encoding }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard data.count <= maximumMessageBytes, let value = String(data: data, encoding: .utf8) else { throw Failure.encoding }
        return value
    }

    static func event(_ data: Data) throws -> [String: Any] {
        guard !data.isEmpty, data.count <= maximumMessageBytes else { throw Failure.decoding }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let event = object as? [String: Any], let type = event["type"] as? String,
              !type.isEmpty, type.utf8.count <= 128 else { throw Failure.invalidEvent }
        return event
    }

    static func audio(_ value: Any?) throws -> Data {
        guard let value = value as? String, value.utf8.count <= 682_672,
              let data = Data(base64Encoded: value), !data.isEmpty,
              data.count <= 512_000, data.count % 2 == 0 else { throw Failure.invalidAudio }
        return data
    }

    static func arguments(_ value: Any?) throws -> [String: Any] {
        guard let raw = value as? String, raw.utf8.count <= 8_000,
              let result = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] else { throw Failure.invalidTool }
        return result
    }
}

import Foundation

@main struct AudioProtocolChecks {
    static func main() throws {
        assert(AudioTutorProtocol.endpoint.scheme == "wss" && AudioTutorProtocol.endpoint.host == "api.openai.com")
        assert(AudioTutorProtocol.endpoint.user == nil && AudioTutorProtocol.model == "gpt-realtime-2.1")
        assert(Set(AudioTutorProtocol.tools.compactMap { $0["name"] as? String }) == ["begin_quiz", "record_answer", "propose_word"])
        for tool in AudioTutorProtocol.tools { assert(JSONSerialization.isValidJSONObject(tool)) }
        let instructions = AudioTutorProtocol.instructions(progress: AudioLearningProgress(), cards: [])
        assert(instructions.contains("unclear") && instructions.contains("لا تسجّل إجابة في مرحلة الشرح"))
        assert(instructions.contains("لا تحتاج إلى النظر إلى الشاشة"))
        let configuration = AudioTutorProtocol.sessionConfiguration(progress: AudioLearningProgress(), cards: [])
        assert(JSONSerialization.isValidJSONObject(configuration))
        assert(Set(configuration.keys) == ["type", "instructions", "output_modalities", "max_output_tokens", "audio", "tools", "tool_choice"])
        assert(configuration["model"] == nil, "Model is immutable after connection; do not send it in session.update")
        assert(configuration["type"] as? String == "realtime")
        assert(configuration["output_modalities"] as? [String] == ["audio"])
        assert(configuration["max_output_tokens"] as? Int == 700)
        assert(configuration["instructions"] as? String == instructions)
        let audio = configuration["audio"] as! [String: Any]
        for direction in ["input", "output"] {
            let settings = audio[direction] as! [String: Any]
            let format = settings["format"] as! [String: Any]
            assert(format["type"] as? String == "audio/pcm" && format["rate"] as? Int == 24000)
        }
        let input = audio["input"] as! [String: Any]
        let vad = input["turn_detection"] as! [String: Any]
        assert(vad as? [String: String] == ["type": "semantic_vad"])
        assert((audio["output"] as! [String: Any])["voice"] as? String == "marin")
        // Exercise the same event factory used by the live session.created handler.
        let event = AudioTutorProtocol.sessionUpdate(progress: AudioLearningProgress(), cards: [])
        let encoded = try JSONSerialization.data(withJSONObject: event)
        let decoded = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        // Independent full wire-shape expectation: exact keys, nesting and JSON types.
        var expected = try JSONSerialization.jsonObject(with: Data("""
        {"type":"session.update","session":{"type":"realtime","output_modalities":["audio"],
        "max_output_tokens":700,"tool_choice":"auto","audio":{
        "input":{"format":{"type":"audio/pcm","rate":24000},"noise_reduction":{"type":"near_field"},
        "turn_detection":{"type":"semantic_vad"}},
        "output":{"format":{"type":"audio/pcm","rate":24000},"voice":"marin"}}}}
        """.utf8)) as! [String: Any]
        var expectedSession = expected["session"] as! [String: Any]
        expectedSession["instructions"] = instructions
        expectedSession["tools"] = AudioTutorProtocol.tools
        expected["session"] = expectedSession
        let actualWire = try JSONSerialization.data(withJSONObject: decoded, options: [.sortedKeys])
        let expectedWire = try JSONSerialization.data(withJSONObject: expected, options: [.sortedKeys])
        assert(actualWire == expectedWire, "Serialized session.update must match the documented minimal semantic-VAD shape")
        let decodedSession = decoded["session"] as! [String: Any]
        let decodedInput = (decodedSession["audio"] as! [String: Any])["input"] as! [String: Any]
        let decodedVAD = decodedInput["turn_detection"] as! [String: Any]
        for forbidden in ["threshold", "prefix_padding_ms", "silence_duration_ms", "idle_timeout_ms"] {
            assert(decodedVAD[forbidden] == nil, "Do not mix server-VAD fields into semantic VAD")
        }
        assert(decodedSession["model"] == nil)
        print("PASS: fixed TLS endpoint, expected model, bounded tools and exact serialized semantic-VAD session.update")
    }
}

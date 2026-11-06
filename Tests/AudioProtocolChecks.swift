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
        assert(vad["type"] as? String == "server_vad" && vad["create_response"] as? Bool == true)
        assert((audio["output"] as! [String: Any])["voice"] as? String == "marin")
        let event: [String: Any] = ["type": "session.update", "session": configuration]
        let encoded = try JSONSerialization.data(withJSONObject: event)
        let decoded = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        assert((decoded["session"] as! [String: Any])["model"] == nil)
        print("PASS: fixed TLS endpoint, expected model, bounded tools and GA session.update payload")
    }
}

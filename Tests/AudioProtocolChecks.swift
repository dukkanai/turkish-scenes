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
        print("PASS: fixed TLS endpoint, expected model and bounded tools")
    }
}

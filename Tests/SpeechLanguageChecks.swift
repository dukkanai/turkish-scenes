import Foundation
@main struct SpeechLanguageChecks {
    static func main() {
        let text = "شرح İstanbul و Bush’un و ışık"
        let runs = SpeechLanguageRuns.runs(in: text, baseLanguage: "ar")
        precondition(runs.first?.language == "ar-SA")
        for word in ["İstanbul", "Bush’un", "ışık"] {
            precondition(runs.contains(SpeechLanguageRun(range: (text as NSString).range(of: word), language: "tr-TR")))
        }
        let emoji = "🌟 İstanbul"
        precondition(SpeechLanguageRuns.runs(in: emoji, baseLanguage: "ar-SA").last?.range.location == 3)
        let decomposed = "كلمة s\u{0327}"
        precondition(SpeechLanguageRuns.runs(in: decomposed, baseLanguage: "ar").last?.range.length == 2)
        let phrase = "اسم Amerika Birleşik Devletleri"
        precondition(SpeechLanguageRuns.runs(in: phrase, baseLanguage: "ar").count == 2)
        precondition(SpeechLanguageRuns.runs(in: "شرح عربي فقط", baseLanguage: "ar").count == 1)
        precondition(SpeechLanguageRuns.runs(in: text, baseLanguage: "tr-TR").count == 1)
        print("PASS: Arabic base speech, Turkish spans, apostrophes and UTF-16 ranges")
    }
}

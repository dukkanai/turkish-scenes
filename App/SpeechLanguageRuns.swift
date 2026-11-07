import Foundation

struct SpeechLanguageRun: Equatable {
    let range: NSRange
    let language: String
}
enum SpeechLanguageRuns {
    private static let latin = try? NSRegularExpression(
        pattern: #"\p{Latin}[\p{Latin}\p{M}]*(?:['’][\p{Latin}\p{M}]+)*(?:[ \t]+\p{Latin}[\p{Latin}\p{M}]*(?:['’][\p{Latin}\p{M}]+)*)*"#)
    static func runs(in text: String, baseLanguage: String) -> [SpeechLanguageRun] {
        let language = baseLanguage.hasPrefix("ar") ? "ar-SA" : baseLanguage
        let whole = NSRange(location: 0, length: (text as NSString).length)
        var result = [SpeechLanguageRun(range: whole, language: language)]
        guard language.hasPrefix("ar"), let latin else { return result }
        for match in latin.matches(in: text, range: whole) {
            result.append(SpeechLanguageRun(range: match.range, language: "tr-TR"))
        }
        return result
    }
}

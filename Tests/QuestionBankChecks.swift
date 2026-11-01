import Foundation
@main struct QuestionBankChecks {
    static func main() throws {
        let film = try JSONDecoder().decode(Film.self, from: Data(contentsOf: URL(fileURLWithPath: "App/Resources/film.json")))
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "App/Resources/reviewed-prompts-2-10.json"))) as! [String: Any]
        let seeds = raw["segments"] as! [String: [[String]]]
        let review = try JSONDecoder().decode(ReviewedQuestionBank.Review.self, from: JSONSerialization.data(withJSONObject: raw))
        precondition(Set(review.excluded.keys) == ["miracle-cell-7:c0002:w08"])
        var total = 0
        var identifiers = Set<String>()
        for segment in film.segments where (2...10).contains(segment.number) {
            let rows = seeds[String(segment.number)]!
            let questions = ReviewedQuestionBank.make(segment: segment, rows: rows, review: review)
            let held = segment.words.filter { review.excluded[$0.id] != nil }
            precondition(questions.count + held.count == segment.words.count)
            for q in questions {
                let word = segment.words.first { q.id == $0.id + ":writing" }!
                precondition(review.excluded[word.id] == nil)
                precondition(!q.choices.contains("Blair'dan"))
                if let corrected = review.explanations[word.id] { precondition(q.explanation == corrected) }
                precondition(q.id == word.id + ":writing")
                precondition(q.answer == word.text)
                precondition(q.choices.count == 4 && Set(q.choices.map(TurkishGrader.normalize)).count == 4)
                precondition(q.choices.filter { TurkishGrader.isCorrect($0, expected: q.answer) }.count == 1)
                precondition(identifiers.insert(q.id).inserted)
                total += 1
            }
            var wrong = rows
            wrong[0][0] = "wrong-source-word"
            precondition(ReviewedQuestionBank.make(segment: segment, rows: wrong).isEmpty)
            precondition(ReviewedQuestionBank.make(segment: segment, rows: Array(rows.dropLast())).isEmpty)
        }
        let phrases = try JSONDecoder().decode([PracticeQuestion].self,
            from: Data(contentsOf: URL(fileURLWithPath: "App/Resources/reviewed-phrases-1-10.json")))
        precondition(phrases.count == 8)
        for q in phrases {
            precondition(q.kind == .phrase)
            precondition(q.choices.count == 4 && Set(q.choices.map(TurkishGrader.normalize)).count == 4)
            precondition(q.choices.filter { TurkishGrader.isCorrect($0, expected: q.answer) }.count == 1)
            precondition(identifiers.insert(q.id).inserted)
            let segment = film.segments.first { $0.id == q.segmentID }!
            let source = segment.turkish.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            precondition(source.contains(q.answer), "Phrase must be verbatim source text")
        }
        precondition(phrases.filter { $0.kind != .phrase }.isEmpty, "Phrases cannot enter word-writing mode")
        precondition(total == 74)
        print("PASS: 74 reviewed occurrences, one explicit source hold, eight phrases and source-drift rejection")
    }
}

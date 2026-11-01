import Foundation
@main struct QuestionBankChecks {
    static func main() throws {
        let film = try JSONDecoder().decode(Film.self, from: Data(contentsOf: URL(fileURLWithPath: "App/Resources/film.json")))
        let manifest = try JSONDecoder().decode(ReviewedQuestionBank.Manifest.self,
            from: Data(contentsOf: URL(fileURLWithPath: "App/Resources/reviewed-manifest.json")))
        let reviews = try manifest.files.map { name in
            try JSONDecoder().decode(ReviewedQuestionBank.Review.self,
                from: Data(contentsOf: URL(fileURLWithPath: "App/Resources/" + name + ".json")))
        }
        guard let review = ReviewedQuestionBank.merge(reviews) else { fatalError("Review batches conflict") }
        precondition(ReviewedQuestionBank.merge(reviews + reviews) == nil, "Duplicate batches must fail closed")
        let seeds = review.segments
        precondition(review.excluded.count == manifest.expectedExclusions)
        for id in ["miracle-cell-7:c0002:w08","miracle-cell-7:c0012:w07",
                   "miracle-cell-7:c0035:w03","miracle-cell-7:c0037:w08","miracle-cell-7:c0038:w02"] {
            precondition(review.excluded[id] != nil)
        }
        precondition((review.nonEducationalSegments ?? []) == manifest.nonEducationalSegments)
        var total = 0
        var identifiers = Set<String>()
        for segment in film.segments where (2...manifest.reviewedThrough).contains(segment.number) {
            let rows = seeds[String(segment.number)]!
            let questions = ReviewedQuestionBank.make(segment: segment, rows: rows, review: review)
            let held = segment.words.filter { review.excluded[$0.id] != nil }
            precondition(questions.count + held.count == segment.words.count)
            if review.nonEducationalSegments?.contains(segment.number) == true { precondition(held.count == segment.words.count) }
            for q in questions {
                let word = segment.words.first { q.id == $0.id + ":writing" }!
                precondition(review.excluded[word.id] == nil)
                precondition(Set(q.choices).isDisjoint(with: ["Blair'dan","Micheal","Ayşeme","Heidi'li"]))
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
        let phraseManifest = try JSONDecoder().decode(ReviewedPhraseBank.Manifest.self,
            from: Data(contentsOf: URL(fileURLWithPath: "App/Resources/reviewed-phrases-manifest.json")))
        let phraseBatches = try phraseManifest.files.map { name in
            try JSONDecoder().decode([PracticeQuestion].self,
                from: Data(contentsOf: URL(fileURLWithPath: "App/Resources/" + name + ".json")))
        }
        guard let phrases = ReviewedPhraseBank.merge(phraseBatches, expectedCount: phraseManifest.expectedQuestions) else {
            fatalError("Phrase batches invalid")
        }
        precondition(ReviewedPhraseBank.merge(phraseBatches + phraseBatches,
            expectedCount: phraseManifest.expectedQuestions * 2) == nil, "Duplicate phrase IDs must fail closed")
        precondition(ReviewedPhraseBank.merge(phraseBatches,
            expectedCount: phraseManifest.expectedQuestions + 1) == nil, "Missing phrases must fail closed")
        precondition(ReviewedPhraseBank.merge([[PracticeQuestion(id: "not-a-phrase", version: 1, segmentID: "test", prompt: "معنى", answer: "bir", explanation: "اختبار", choices: ["bir", "iki", "üç", "dört"])]], expectedCount: 1) == nil,
            "Word questions cannot enter phrase bank")
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
        precondition(total == manifest.expectedEligibleOccurrences)
        precondition(total + review.excluded.count == manifest.expectedSourceOccurrences)
        print("PASS: Reviewed occurrence counts, explicit holds/exclusions and manifest-backed phrases and source-drift rejection")
    }
}

import Foundation

enum ReviewedQuestionBank {
    struct Review: Decodable {
        let segments: [String: [[String]]]
        let excluded: [String: String]
        let explanations: [String: String]
        let choiceOverrides: [String: [String]]
        let nonEducationalSegments: [Int]?
    }
    struct Manifest: Decodable {
        let files: [String]
        let reviewedThrough: Int
        let expectedSourceOccurrences: Int
        let expectedEligibleOccurrences: Int
        let expectedExclusions: Int
        let nonEducationalSegments: [Int]
    }
    static func merge(_ reviews: [Review]) -> Review? {
        guard !reviews.isEmpty else { return nil }
        var segments: [String: [[String]]] = [:]
        var excluded: [String: String] = [:]
        var explanations: [String: String] = [:]
        var choices: [String: [String]] = [:]
        var nonEducational = Set<Int>()
        for review in reviews {
            guard Set(segments.keys).isDisjoint(with: review.segments.keys),
                  Set(excluded.keys).isDisjoint(with: review.excluded.keys),
                  Set(explanations.keys).isDisjoint(with: review.explanations.keys),
                  Set(choices.keys).isDisjoint(with: review.choiceOverrides.keys) else { return nil }
            segments.merge(review.segments) { first, _ in first }
            excluded.merge(review.excluded) { first, _ in first }
            explanations.merge(review.explanations) { first, _ in first }
            choices.merge(review.choiceOverrides) { first, _ in first }
            nonEducational.formUnion(review.nonEducationalSegments ?? [])
        }
        return Review(segments: segments, excluded: excluded, explanations: explanations,
            choiceOverrides: choices, nonEducationalSegments: nonEducational.sorted())
    }
    private static let document: Review? = {
        guard let url = Bundle.main.url(forResource: "reviewed-manifest", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return nil }
        var reviews: [Review] = []
        for name in manifest.files {
            guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let review = try? JSONDecoder().decode(Review.self, from: data) else { return nil }
            reviews.append(review)
        }
        return merge(reviews)
    }()
    static var reviewedThrough: Int { document?.segments.keys.compactMap(Int.init).max() ?? 0 }
    static func isNonEducational(_ segment: Segment) -> Bool {
        document?.nonEducationalSegments?.contains(segment.number) ?? false
    }
    static func explanation(for word: WordOccurrence) -> String {
        document?.excluded[word.id] ?? document?.explanations[word.id] ?? word.explanation
    }
    static func questions(for segment: Segment) -> [PracticeQuestion] {
        guard let document, let rows = document.segments[String(segment.number)] else { return [] }
        return make(segment: segment, rows: rows, review: document)
    }
    static func make(segment: Segment, rows: [[String]], review: Review? = nil) -> [PracticeQuestion] {
        guard rows.count == segment.words.count, rows.allSatisfy({ $0.count == 2 }),
              zip(rows, segment.words).allSatisfy({ $0.0[0] == $0.1.text }) else { return [] }
        let held = segment.words.filter { review?.excluded[$0.id] != nil }
        let heldSpellings = Set(held.map(\.text))
        var result: [PracticeQuestion] = []
        for (index, row) in rows.enumerated() {
            let word = segment.words[index]
            if review?.excluded[word.id] != nil { continue }
            let answer = row[0]
            let candidates = Array(rows.dropFirst(index + 1)) + Array(rows.prefix(index))
            var choices = review?.choiceOverrides[word.id] ?? [answer]
            if choices.count == 1 {
                for candidate in candidates.map({ $0[0] }) + ["Irak", "Tony", "İngiltere"] {
                    if !heldSpellings.contains(candidate),
                       !choices.contains(where: { TurkishGrader.isCorrect($0, expected: candidate) }) {
                        choices.append(candidate)
                    }
                    if choices.count == 4 { break }
                }
            }
            guard choices.count == 4, Set(choices.map(TurkishGrader.normalize)).count == 4,
                  choices.allSatisfy({ !heldSpellings.contains($0) }),
                  choices.filter({ TurkishGrader.isCorrect($0, expected: answer) }).count == 1 else { return [] }
            result.append(PracticeQuestion(id: word.id + ":writing", version: 1, segmentID: segment.id,
                prompt: row[1], answer: answer,
                explanation: review?.explanations[word.id] ?? word.explanation, choices: choices))
        }
        guard result.count + held.count == segment.words.count else { return [] }
        return result
    }
}

enum ReviewedPhraseBank {
    struct Manifest: Decodable {
        let files: [String]
        let expectedQuestions: Int
    }
    static func merge(_ batches: [[PracticeQuestion]], expectedCount: Int) -> [PracticeQuestion]? {
        guard !batches.isEmpty, expectedCount > 0 else { return nil }
        let values = batches.flatMap { $0 }
        guard values.count == expectedCount,
              Set(values.map { $0.id }).count == values.count,
              values.allSatisfy({ q in
                  q.kind == .phrase && !q.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  && !q.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  && q.choices.count == 4
                  && Set(q.choices.map(TurkishGrader.normalize)).count == 4
                  && q.choices.filter { TurkishGrader.isCorrect($0, expected: q.answer) }.count == 1
              }) else { return nil }
        return values
    }
    static let all: [PracticeQuestion] = {
        guard let url = Bundle.main.url(forResource: "reviewed-phrases-manifest", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              Set(manifest.files).count == manifest.files.count else { return [] }
        var batches: [[PracticeQuestion]] = []
        for name in manifest.files {
            guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let values = try? JSONDecoder().decode([PracticeQuestion].self, from: data) else { return [] }
            batches.append(values)
        }
        return merge(batches, expectedCount: manifest.expectedQuestions) ?? []
    }()
}

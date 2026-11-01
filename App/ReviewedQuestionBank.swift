import Foundation

enum ReviewedQuestionBank {
    private struct File: Decodable { let segments: [String: [[String]]] }
    private static let seeds: [String: [[String]]] = {
        guard let url = Bundle.main.url(forResource: "reviewed-prompts-2-10", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [:] }
        return file.segments
    }()
    static func questions(for segment: Segment) -> [PracticeQuestion] {
        guard let rows = seeds[String(segment.number)] else { return [] }
        return make(segment: segment, rows: rows)
    }
    static func make(segment: Segment, rows: [[String]]) -> [PracticeQuestion] {
        guard rows.count == segment.words.count, rows.allSatisfy({ $0.count == 2 }),
              zip(rows, segment.words).allSatisfy({ $0.0[0] == $0.1.text }) else { return [] }
        // This first reviewed batch has distinct senses within each segment.
        // All distractors are source spellings with different meanings, not generated translations.
        return rows.enumerated().compactMap { index, row in
            let answer = row[0]
            let candidates = Array(rows.dropFirst(index + 1)) + Array(rows.prefix(index))
            var choices = [answer]
            for candidate in candidates.map({ $0[0] }) + ["Irak", "Tony", "İngiltere"] {
                if !choices.contains(where: { TurkishGrader.isCorrect($0, expected: candidate) }) {
                    choices.append(candidate)
                }
                if choices.count == 4 { break }
            }
            guard choices.count == 4 else { return nil }
            let word = segment.words[index]
            return PracticeQuestion(id: word.id + ":writing", version: 1, segmentID: segment.id,
                prompt: row[1], answer: answer, explanation: word.explanation, choices: choices)
        }
    }
}

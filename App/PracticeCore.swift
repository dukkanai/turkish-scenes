import Foundation

enum TurkishGrader {
    static func normalize(_ input: String) -> String {
        let text = input.precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return trimmed.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .lowercased(with: Locale(identifier: "tr_TR"))
    }
    static func isCorrect(_ input: String, expected: String) -> Bool {
        let answer = normalize(input)
        return !answer.isEmpty && answer == normalize(expected)
    }
}
enum QuestionKind: String, Codable { case word, phrase }
struct PracticeQuestion: Codable, Identifiable, Equatable {
    let id: String
    let version: Int
    let segmentID: String
    let prompt: String
    let answer: String
    let explanation: String
    let choices: [String]
    var kind: QuestionKind? = nil
}
enum PracticeMode: String, Codable { case writing, choice, review }
enum AnswerPhase: String, Codable { case unanswered, correct, incorrect, skipped }
struct PracticeAnswer: Codable, Equatable {
    let questionID: String
    let input: String
    let correct: Bool
    let date: Date
}
struct PracticeSession: Codable {
    let id: UUID
    let mode: PracticeMode
    let questions: [PracticeQuestion]
    var index: Int = 0
    var phases: [String: AnswerPhase] = [:]
    var answers: [String: PracticeAnswer] = [:]
    var completed: Bool { index >= questions.count }
    var current: PracticeQuestion? { completed ? nil : questions[index] }
    init(mode: PracticeMode, questions: [PracticeQuestion]) {
        self.id = UUID()
        self.mode = mode
        self.questions = questions
    }
    mutating func submit(_ input: String, date: Date = Date()) -> PracticeAnswer? {
        guard let question = current,
              phases[question.id, default: .unanswered] == .unanswered,
              !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let answer = PracticeAnswer(questionID: question.id, input: input,
            correct: TurkishGrader.isCorrect(input, expected: question.answer), date: date)
        answers[question.id] = answer
        phases[question.id] = answer.correct ? .correct : .incorrect
        return answer
    }
    mutating func next() {
        guard let question = current else { return }
        if phases[question.id, default: .unanswered] == .unanswered { phases[question.id] = .skipped }
        index += 1
    }
    mutating func previous() { if index > 0 { index -= 1 } }
}
struct MistakeRecord: Codable, Identifiable {
    var id: String { question.id }
    var question: PracticeQuestion
    var wrongCount: Int
    var open: Bool
    var lastDate: Date
}
struct RecordedAttempt: Codable {
    let sessionID: UUID?
    let questionID: String
    let questionVersion: Int
    let mode: PracticeMode
    let input: String
    let correct: Bool
    let date: Date
}
struct CompletedPractice: Codable, Identifiable {
    let id: UUID
    let mode: PracticeMode
    let questionIDs: [String]
    let date: Date
}
struct LearningProgress: Codable {
    var schemaVersion: Int = 1
    var lastSegmentID: String?
    var visited: Set<String> = []
    var session: PracticeSession?
    var mistakes: [String: MistakeRecord] = [:]
    var firstAnswers: [String: Bool] = [:]
    // Optional additions preserve decoding of existing version-one progress.
    var attempts: [RecordedAttempt]?
    var completedPractices: [CompletedPractice]?
    mutating func recordCompletion(_ session: PracticeSession, date: Date = Date()) {
        guard session.completed, !session.questions.isEmpty,
              session.questions.allSatisfy({ session.answers[$0.id] != nil }),
              !(completedPractices ?? []).contains(where: { $0.id == session.id }) else { return }
        var values = completedPractices ?? []
        values.append(CompletedPractice(id: session.id, mode: session.mode,
            questionIDs: session.questions.map(\.id), date: date))
        completedPractices = values
    }
    mutating func record(_ answer: PracticeAnswer, question: PracticeQuestion, mode: PracticeMode) {
        var history = attempts ?? []
        history.append(RecordedAttempt(sessionID: session?.id, questionID: question.id,
            questionVersion: question.version, mode: mode, input: answer.input,
            correct: answer.correct, date: answer.date))
        attempts = history
        let key = "\(question.id):v\(question.version)"
        if firstAnswers[key] == nil { firstAnswers[key] = answer.correct }
        if !answer.correct {
            var item = mistakes[key] ?? MistakeRecord(question: question, wrongCount: 0, open: true, lastDate: answer.date)
            item.wrongCount += 1
            item.open = true
            item.lastDate = answer.date
            mistakes[key] = item
        } else if mode == .review, var item = mistakes[key] {
            item.open = false
            item.lastDate = answer.date
            mistakes[key] = item
        }
    }
}

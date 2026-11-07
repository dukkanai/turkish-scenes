import Foundation

enum AudioTrack: String, Codable, CaseIterable, Identifiable {
    case word, phrase, grammar, personal
    var id: String { rawValue }
    var title: String {
        switch self {
        case .word: return "الكلمات"
        case .phrase: return "العبارات اليومية"
        case .grammar: return "القواعد"
        case .personal: return "كلماتي"
        }
    }
    var lessonSize: Int { self == .grammar ? 1 : 5 }
}

struct AudioCard: Codable, Identifiable, Equatable {
    let id: String
    let kind: AudioTrack
    let category: String
    let turkish: String
    let arabic: String
    let acceptedArabic: [String]
    let exampleTurkish: String
    let exampleArabic: String
    var explanationArabic: String? = nil
    var questionArabic: String? = nil
    var acceptedAnswers: [String]? = nil
    var correctionArabic: String? = nil
    var question: String { questionArabic ?? "ما معنى \(turkish) بالعربية؟" }
    var expectedAnswers: [String] { acceptedAnswers ?? acceptedArabic }
    var isValid: Bool {
        !id.isEmpty && !turkish.isEmpty && !arabic.isEmpty && !expectedAnswers.isEmpty
            && [turkish, arabic, exampleTurkish, exampleArabic].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 2000 }
            && expectedAnswers.allSatisfy { !$0.isEmpty && $0.count <= 1000 }
    }
}

struct GrammarSource: Decodable {
    let id: String
    let titleArabic: String
    let explanationArabic: String
    let exampleTurkish: String
    let exampleArabic: String
    let questionArabic: String
    let expectedTurkish: String
    let acceptedAnswers: [String]
    let correctionArabic: String
    var card: AudioCard {
        AudioCard(id: id, kind: .grammar, category: "القواعد", turkish: expectedTurkish,
                  arabic: titleArabic, acceptedArabic: [], exampleTurkish: exampleTurkish,
                  exampleArabic: exampleArabic, explanationArabic: explanationArabic,
                  questionArabic: questionArabic, acceptedAnswers: acceptedAnswers,
                  correctionArabic: correctionArabic)
    }
}

struct AudioLesson: Identifiable {
    let id: String
    let track: AudioTrack
    let number: Int
    let cards: [AudioCard]
}

enum AudioCurriculum {
    static func normalized(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased(with: Locale(identifier: "tr_TR"))
    }
    static func lessons(_ cards: [AudioCard], track: AudioTrack) -> [AudioLesson] {
        let filtered = cards.filter { $0.kind == track }
        return stride(from: 0, to: filtered.count, by: track.lessonSize).map { start in
            AudioLesson(id: "\(track.rawValue)-lesson-\(start / track.lessonSize + 1)", track: track,
                        number: start / track.lessonSize + 1,
                        cards: Array(filtered[start..<min(start + track.lessonSize, filtered.count)]))
        }
    }
    static func load(bundle: Bundle = .main) throws -> [AudioCard] {
        let decoder = JSONDecoder()
        var cards: [AudioCard] = []
        for name in ["audio-words-a", "audio-words-b", "audio-phrases"] {
            guard let url = bundle.url(forResource: name, withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
            cards += try decoder.decode([AudioCard].self, from: Data(contentsOf: url))
        }
        guard let grammarURL = bundle.url(forResource: "audio-grammar", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
        cards += try decoder.decode([GrammarSource].self, from: Data(contentsOf: grammarURL)).map(\.card)
        guard cards.allSatisfy(\.isValid), Set(cards.map(\.id)).count == cards.count,
              cards.filter({ $0.kind == .word }).count >= 1200,
              cards.filter({ $0.kind == .phrase }).count >= 250 else { throw CocoaError(.coderReadCorrupt) }
        for kind in [AudioTrack.word, .phrase] {
            let terms = cards.filter { $0.kind == kind }.map { normalized($0.turkish) }
            guard Set(terms).count == terms.count else { throw CocoaError(.coderReadCorrupt) }
        }
        return cards
    }
}

enum AudioVerdict: String, Codable { case correct, incorrect, unclear }
enum AudioPhase: String, Codable { case teaching, quiz, complete }
struct AudioMastery: Codable {
    var correctCount = 0
    var wrongCount = 0
    var openMistake = false
    var masteredAt: Date?
    var reviewDue: Date?
}
struct AudioAttempt: Codable {
    let cardID: String
    let verdict: AudioVerdict
    let date: Date
    // Raw microphone audio, transcripts and API credentials are never persisted.
}
struct AudioLessonSession: Codable {
    let lessonID: String
    let cardIDs: [String]
    let isReview: Bool
    var phase: AudioPhase = .teaching
    var queue: [String]
    var streaks: [String: Int] = [:]
    var promptID = UUID().uuidString
    var currentID: String? { phase == .quiz ? queue.first : nil }
    init(lessonID: String, cardIDs: [String], isReview: Bool) {
        self.lessonID = lessonID; self.cardIDs = cardIDs; self.queue = cardIDs; self.isReview = isReview
    }
    var isValid: Bool {
        let ids = Set(cardIDs)
        return !ids.isEmpty && ids.count == cardIDs.count && cardIDs.count <= 5
            && Set(queue).isSubset(of: ids) && Set(queue).count == queue.count
            && Set(streaks.keys).isSubset(of: ids) && streaks.values.allSatisfy { (0...2).contains($0) }
            && ((phase == .complete) == queue.isEmpty) && !promptID.isEmpty
    }
}
struct AudioLearningProgress: Codable {
    var schemaVersion = 1
    var mastery: [String: AudioMastery] = [:]
    var session: AudioLessonSession?
    var attempts: [AudioAttempt] = []
    var personalCards: [AudioCard] = []
    var completedLessons: Set<String> = []
    var isValid: Bool {
        schemaVersion == 1 && (session?.isValid ?? true)
            && personalCards.count <= 5000 && personalCards.allSatisfy { $0.kind == .personal && $0.isValid }
            && Set(personalCards.map(\.id)).count == personalCards.count
            && mastery.values.allSatisfy { $0.correctCount >= 0 && $0.wrongCount >= 0 }
    }
    mutating func begin(_ lesson: AudioLesson, review: Bool = false) -> Bool {
        guard !lesson.cards.isEmpty, lesson.cards.count <= 5 else { return false }
        session = AudioLessonSession(lessonID: lesson.id, cardIDs: lesson.cards.map(\.id), isReview: review)
        return true
    }
    mutating func beginQuiz() -> Bool {
        guard var current = session, current.phase == .teaching else { return false }
        current.phase = .quiz; current.promptID = UUID().uuidString; session = current
        return true
    }
    /// Application state, not the model, owns progression. Two independent correct recalls
    /// per item are required; a mistake resets that item's streak and schedules it again.
    mutating func record(promptID: String, cardID: String, verdict: AudioVerdict, now: Date = Date()) -> Bool {
        guard var current = session, current.isValid, current.phase == .quiz, current.promptID == promptID,
              current.currentID == cardID else { return false }
        current.promptID = UUID().uuidString // Reject duplicate, stale and replayed tool results.
        if verdict != .unclear {
            var item = mastery[cardID] ?? AudioMastery()
            current.queue.removeFirst()
            if verdict == .correct {
                guard item.correctCount < Int.max else { return false }
                item.correctCount += 1
                current.streaks[cardID, default: 0] += 1
                if current.streaks[cardID, default: 0] >= 2 {
                    item.masteredAt = now
                    item.openMistake = false
                    item.reviewDue = now.addingTimeInterval(current.isReview ? 3 * 86400 : 86400)
                } else { current.queue.append(cardID) }
            } else {
                guard item.wrongCount < Int.max else { return false }
                item.wrongCount += 1; item.openMistake = true; item.masteredAt = nil
                item.reviewDue = now; current.streaks[cardID] = 0; current.queue.append(cardID)
            }
            mastery[cardID] = item
        }
        attempts.append(AudioAttempt(cardID: cardID, verdict: verdict, date: now))
        if attempts.count > 10000 { attempts.removeFirst(attempts.count - 10000) }
        if current.queue.isEmpty {
            current.phase = .complete
            if !current.isReview { completedLessons.insert(current.lessonID) }
        }
        session = current
        return true
    }
    func reviewCards(from cards: [AudioCard], now: Date = Date()) -> [AudioCard] {
        cards.filter { card in
            guard let m = mastery[card.id] else { return false }
            return m.openMistake || (m.reviewDue.map { $0 <= now } ?? false)
        }.sorted {
            let l = mastery[$0.id]!, r = mastery[$1.id]!
            if l.openMistake != r.openMistake { return l.openMistake }
            return (l.reviewDue ?? .distantPast, $0.id) < (r.reviewDue ?? .distantPast, $1.id)
        }
    }
}

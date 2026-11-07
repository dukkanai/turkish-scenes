import Foundation

@main struct AudioLearningChecks {
    static func card(_ id: Int) -> AudioCard {
        AudioCard(id: "word-\(id)", kind: .word, category: "اختبار", turkish: "ev\(id)", arabic: "بيت",
                  acceptedArabic: ["بيت"], exampleTurkish: "Bu bir ev.", exampleArabic: "هذا بيت.")
    }
    static func main() throws {
        let cards = (1...10).map { card($0) }
        let lessons = AudioCurriculum.lessons(cards, track: .word)
        assert(lessons.count == 2 && lessons.allSatisfy { $0.cards.count == 5 })
        assert(AudioCurriculum.normalized("  İSTANBUL! ") == "istanbul")
        assert(AudioCurriculum.normalized("IŞIK") == "ışık")
        assert(AudioCurriculum.normalized("sık") != AudioCurriculum.normalized("sik"))
        var p = AudioLearningProgress()
        assert(p.begin(lessons[0]) && p.isValid)
        let stale = p.session!.promptID
        assert(!p.record(promptID: stale, cardID: cards[0].id, verdict: .correct))
        assert(!p.completedLessons.contains(lessons[0].id))
        assert(p.beginQuiz() && !p.beginQuiz())
        let first = p.session!.promptID
        assert(!p.record(promptID: first, cardID: "unknown", verdict: .correct))
        assert(p.record(promptID: first, cardID: cards[0].id, verdict: .unclear))
        assert(p.mastery[cards[0].id] == nil)
        assert(!p.record(promptID: first, cardID: cards[0].id, verdict: .correct))
        for _ in 0..<5 {
            let current = p.session!
            assert(p.record(promptID: current.promptID, cardID: current.currentID!, verdict: .correct))
        }
        assert(p.session!.phase == .quiz && p.completedLessons.isEmpty)
        let wrong = p.session!
        assert(p.record(promptID: wrong.promptID, cardID: wrong.currentID!, verdict: .incorrect))
        assert(p.mastery[wrong.currentID!]!.openMistake && p.session!.streaks[wrong.currentID!] == 0)
        p = try JSONDecoder().decode(AudioLearningProgress.self, from: JSONEncoder().encode(p))
        assert(p.isValid)
        while p.session!.phase == .quiz {
            let current = p.session!
            assert(p.record(promptID: current.promptID, cardID: current.currentID!, verdict: .correct))
        }
        assert(p.isValid && p.completedLessons == [lessons[0].id])
        assert(p.mastery.count == 5 && p.mastery.values.allSatisfy { $0.masteredAt != nil && !$0.openMistake })
        assert(p.reviewCards(from: cards).isEmpty)
        assert(p.reviewCards(from: cards, now: Date().addingTimeInterval(86401)).count == 5)
        assert(!p.begin(AudioLesson(id: "too-many", track: .word, number: 3, cards: cards)))
        var corrupt = p; corrupt.session!.queue = ["unrecognized"]
        assert(!corrupt.isValid)
        for verdict in [AudioVerdict.correct, .incorrect] {
            var overflow = AudioLearningProgress()
            assert(overflow.begin(lessons[0]) && overflow.beginQuiz())
            let before = overflow.session!
            overflow.mastery[cards[0].id] = AudioMastery(correctCount: Int.max, wrongCount: Int.max)
            assert(!overflow.record(promptID: before.promptID, cardID: cards[0].id, verdict: verdict))
            assert(overflow.session?.promptID == before.promptID && overflow.attempts.isEmpty)
        }
        print("PASS: lesson mastery, unclear, retry, stale/replay rejection, persistence and review")
    }
}

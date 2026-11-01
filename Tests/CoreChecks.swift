import Foundation

@main struct CoreChecks {
    static func main() throws {
        func check(_ ok: @autoclosure () -> Bool, _ label: String) {
            guard ok() else { fatalError("FAILED: " + label) }
        }
        check(TurkishGrader.isCorrect("  İSTANBUL! ", expected: "istanbul"), "Turkish dotted I")
        check(TurkishGrader.isCorrect("IŞIK", expected: "ışık"), "Turkish dotless I")
        check(!TurkishGrader.isCorrect("isik", expected: "ışık"), "Do not erase diacritics")
        check(!TurkishGrader.isCorrect("", expected: ""), "Empty never correct")
        check(TurkishGrader.isCorrect("Bush’un", expected: "Bush'un"), "Apostrophe variants")
        let q = PracticeQuestion(id:"q1",version:1,segmentID:"s1",prompt:"دعم",answer:"destek",explanation:"دعم",choices:[])
        var s = PracticeSession(mode:.writing,questions:[q])
        check(s.submit(" ") == nil, "Empty does not count")
        let wrong = s.submit("wrong")!
        check(!wrong.correct, "Wrong classified")
        check(s.index == 0, "Wrong waits for next")
        check(s.submit("destek") == nil, "Duplicate submission ignored")
        let data = try JSONEncoder().encode(s)
        var restored = try JSONDecoder().decode(PracticeSession.self,from:data)
        check(restored.phases[q.id] == .incorrect, "Restore correction phase")
        check(restored.submit("destek") == nil, "Restore does not duplicate")
        restored.next()
        check(restored.completed, "Final next completes")
        restored.previous()
        check(restored.phases[q.id] == .incorrect, "Previous retains answer")
        var p = LearningProgress()
        p.record(wrong,question:q,mode:.writing)
        check(p.mistakes["q1:v1"]?.open == true, "Wrong opens review")
        let correct = PracticeAnswer(questionID:"q1",input:"destek",correct:true,date:Date())
        p.record(correct,question:q,mode:.writing)
        check(p.mistakes["q1:v1"]?.open == true, "Ordinary correction does not resolve")
        p.record(correct,question:q,mode:.review)
        check(p.mistakes["q1:v1"]?.open == false, "Independent review resolves")
        p.record(wrong,question:q,mode:.review)
        check(p.mistakes["q1:v1"]?.open == true, "Wrong reopens")
        var skip = PracticeSession(mode:.choice,questions:[q])
        skip.next()
        check(skip.phases[q.id] == .skipped && skip.answers.isEmpty, "Skip is not success")
        check(p.attempts?.count == 4, "All independent attempts retained")
        p.recordCompletion(skip)
        check(p.completedPractices == nil, "Skipped session is not completed training")
        var full = PracticeSession(mode: .writing, questions: [q])
        _ = full.submit("destek")
        full.next()
        p.recordCompletion(full)
        p.recordCompletion(full)
        check(p.completedPractices?.count == 1, "Completion is idempotent")
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as! [String: Any]
        old.removeValue(forKey: "attempts")
        old.removeValue(forKey: "completedPractices")
        let migrated = try JSONDecoder().decode(LearningProgress.self,
            from: JSONSerialization.data(withJSONObject: old))
        check(migrated.firstAnswers == p.firstAnswers, "Existing version-one answers survive")
        check(migrated.mistakes.count == p.mistakes.count, "Existing mistakes survive")
        check(migrated.attempts == nil, "Missing historic attempt log is not invented")
        print("Core checks passed.")
    }
}

import Foundation

@main struct AudioProgressChecks {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let card = AudioCard(id: "personal-test", kind: .personal, category: "اختبار", turkish: "elma", arabic: "تفاحة", acceptedArabic: ["تفاحة"], exampleTurkish: "Elma yiyorum.", exampleArabic: "آكل تفاحة.")
        let lesson = AudioLesson(id: "test", track: .personal, number: 1, cards: [card])
        let store = AudioProgressStore(directory: root, loadCurriculum: false)
        assert(store.addPersonal(card) && !store.addPersonal(card))
        assert(store.change { $0.begin(lesson) })
        assert(store.change { $0.beginQuiz() })
        let reopened = AudioProgressStore(directory: root, loadCurriculum: false)
        assert(reopened.progress.session?.phase == .quiz && reopened.progress.personalCards.count == 1)
        let file = root.appendingPathComponent("audio-progress-v1.json")
        let backup = root.appendingPathComponent("audio-progress-v1.previous.json")
        try Data("not-json".utf8).write(to: file)
        let recovered = AudioProgressStore(directory: root, loadCurriculum: false)
        assert(recovered.progress.session?.phase == .teaching && recovered.errorMessage != nil)
        assert(recovered.change { $0.beginQuiz() })
        let savedFiles = try FileManager.default.contentsOfDirectory(atPath: root.path)
        assert(savedFiles.contains { $0.hasPrefix("unreadable-") })
        try Data("broken".utf8).write(to: file); try Data("broken".utf8).write(to: backup)
        let blocked = AudioProgressStore(directory: root, loadCurriculum: false)
        assert(!blocked.canUseProgress && blocked.persistenceFailure)
        assert(!blocked.change { $0.begin(lesson) })
        let preserved = try String(contentsOf: file)
        assert(preserved == "broken")
        let blockedPath = root.appendingPathComponent("not-a-directory")
        try Data("keep".utf8).write(to: blockedPath)
        let unwritable = AudioProgressStore(directory: blockedPath, loadCurriculum: false)
        assert(!unwritable.addPersonal(card) && unwritable.progress.personalCards.isEmpty)
        assert(unwritable.persistenceFailure && !unwritable.canUseProgress)
        assert(!reopened.persistenceFailure && reopened.canUseProgress)
        print("PASS: persistence, backup recovery, corrupt-file preservation and failed-write rollback")
    }
}

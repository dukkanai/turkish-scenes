import Foundation
import Combine

@MainActor final class ProgressStore: ObservableObject {
    @Published private(set) var progress = LearningProgress()
    @Published var errorMessage: String?
    private let directory: URL
    private var file: URL { directory.appendingPathComponent("progress-v1.json") }
    private var backup: URL { directory.appendingPathComponent("progress-v1.previous.json") }
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TurkishScenes", isDirectory: true)
        load()
    }
    private func decode(_ url: URL) throws -> LearningProgress {
        let value = try JSONDecoder().decode(LearningProgress.self, from: Data(contentsOf: url))
        guard value.schemaVersion == 1 else { throw CocoaError(.coderReadCorrupt) }
        return value
    }
    private func load() {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do { progress = try decode(file) }
        catch {
            do {
                progress = try decode(backup)
                errorMessage = "استُعيدت نسخة سابقة من التقدم لأن النسخة الأخيرة تعذرت قراءتها."
            } catch {
                errorMessage = "تعذر قراءة التقدم المحفوظ. لم تُحذف الملفات، ولن يُستبدل التقدم تلقائيًا."
            }
        }
    }
    @discardableResult private func commit(_ value: LearningProgress) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                let prior = try Data(contentsOf: file)
                // Never overwrite a corrupt primary or lose evidence silently.
                _ = try decode(file)
                try prior.write(to: backup, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            let data = try JSONEncoder().encode(value)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            progress = value
            return true
        } catch {
            errorMessage = "لم يُحفظ هذا التغيير. بقي التقدم السابق محفوظًا؛ حاول مجددًا."
            return false
        }
    }
    func visit(_ segmentID: String) {
        var value = progress
        value.lastSegmentID = segmentID
        value.visited.insert(segmentID)
        _ = commit(value)
    }
    func begin(mode: PracticeMode, questions: [PracticeQuestion]) -> Bool {
        var value = progress
        value.session = PracticeSession(mode: mode, questions: questions)
        return commit(value)
    }
    func submit(_ input: String) -> PracticeAnswer? {
        var value = progress
        guard var session = value.session, let question = session.current,
              let answer = session.submit(input) else { return nil }
        value.record(answer, question: question, mode: session.mode)
        value.session = session
        return commit(value) ? answer : nil
    }
    func next() {
        var value = progress
        value.session?.next()
        _ = commit(value)
    }
    func previous() {
        var value = progress
        value.session?.previous()
        _ = commit(value)
    }
}

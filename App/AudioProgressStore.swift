import Foundation
import Combine

@MainActor final class AudioProgressStore: ObservableObject {
    @Published private(set) var progress = AudioLearningProgress()
    @Published private(set) var cards: [AudioCard] = []
    @Published var errorMessage: String?
    private let directory: URL
    private var blocked = false
    private var recovered = false
    private var file: URL { directory.appendingPathComponent("audio-progress-v1.json") }
    private var backup: URL { directory.appendingPathComponent("audio-progress-v1.previous.json") }
    var allCards: [AudioCard] { cards + progress.personalCards }
    init(directory: URL? = nil, loadCurriculum: Bool = true) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TurkishScenesAudio", isDirectory: true)
        if loadCurriculum {
            do { cards = try AudioCurriculum.load() }
            catch { errorMessage = "تعذر قراءة منهج التعلم. لم تتغير بياناتك." }
        }
        load()
    }
    private func decode(_ url: URL) throws -> AudioLearningProgress {
        let data = try Data(contentsOf: url)
        guard data.count <= 20_000_000 else { throw CocoaError(.coderReadCorrupt) }
        let value = try JSONDecoder().decode(AudioLearningProgress.self, from: data)
        guard value.isValid else { throw CocoaError(.coderReadCorrupt) }
        return value
    }
    private func load() {
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do { progress = try decode(file) }
        catch {
            do {
                progress = try decode(backup); recovered = true
                errorMessage = "استُعيدت النسخة السابقة من تقدم التعلم الصوتي."
            } catch {
                blocked = true; errorMessage = "تعذر قراءة تقدم التعلم الصوتي. الملفات محفوظة ولن نستبدلها تلقائيًا."
            }
        }
    }
    @discardableResult func change(_ transform: (inout AudioLearningProgress) -> Bool) -> Bool {
        guard !blocked else { return false }
        var value = progress
        guard transform(&value), value.isValid else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                if recovered {
                    try FileManager.default.copyItem(at: file, to: directory.appendingPathComponent("unreadable-\(UUID().uuidString).json"))
                } else {
                    _ = try decode(file)
                    try Data(contentsOf: file).write(to: backup, options: [.atomic, .completeFileProtection])
                }
            }
            try JSONEncoder().encode(value).write(to: file, options: [.atomic, .completeFileProtection])
            progress = value; recovered = false; errorMessage = nil; return true
        } catch {
            errorMessage = "لم يُحفظ التغيير. بقي التقدم السابق محفوظًا. أوقف الجلسة وحاول مجددًا."
            return false
        }
    }
    func addPersonal(_ card: AudioCard) -> Bool {
        guard card.kind == .personal, card.isValid,
              !allCards.contains(where: { AudioCurriculum.normalized($0.turkish) == AudioCurriculum.normalized(card.turkish) }) else {
            errorMessage = "هذه الكلمة موجودة بالفعل أو بياناتها غير مكتملة."; return false
        }
        return change { value in value.personalCards.append(card); return true }
    }
}

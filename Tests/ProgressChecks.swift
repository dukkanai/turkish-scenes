import Foundation

@main struct ProgressChecks {
    @MainActor static func main() throws {
        func check(_ ok: @autoclosure () -> Bool, _ label: String) {
            guard ok() else { fatalError("FAILED: "+label) }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = ProgressStore(directory: root)
        a.visit("s1")
        a.visit("s2")
        let b = ProgressStore(directory: root)
        check(b.progress.lastSegmentID == "s2", "Reopen preserves latest")
        let primary = root.appendingPathComponent("progress-v1.json")
        try Data("corrupt".utf8).write(to: primary)
        let c = ProgressStore(directory: root)
        check(c.progress.lastSegmentID == "s1", "Valid backup recovered")
        check(c.errorMessage != nil, "Recovery is disclosed")
        c.visit("s3")
        check(c.progress.lastSegmentID == "s3", "Recovered state remains writable")
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        check(names.contains(where: {$0.hasPrefix("unreadable-")}), "Corrupt primary retained")
        try Data("corrupt".utf8).write(to: primary)
        try Data("also corrupt".utf8).write(to: root.appendingPathComponent("progress-v1.previous.json"))
        let d = ProgressStore(directory: root)
        d.visit("must-not-overwrite")
        check(d.errorMessage != nil, "Both invalid reported")
        let retained = try Data(contentsOf: primary)
        check(String(data: retained, encoding: .utf8) == "corrupt", "Both invalid not silently replaced")
        let sibling = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try Data("unrelated".utf8).write(to: sibling)
        defer { try? FileManager.default.removeItem(at: sibling) }
        check(d.deleteAllProgress(), "Explicit reset can clear corrupt local progress")
        check(!FileManager.default.fileExists(atPath: root.path), "Primary, backup and preserved copies are removed")
        check(FileManager.default.fileExists(atPath: sibling.path), "Unrelated sibling is untouched")
        check(d.progress.visited.isEmpty && d.progress.session == nil, "Memory is reset")
        d.visit("after-reset")
        check(ProgressStore(directory: root).progress.lastSegmentID == "after-reset", "Saving works after explicit reset")
        let badRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: badRoot) }
        try FileManager.default.createDirectory(at: badRoot, withIntermediateDirectories: true)
        let q = PracticeQuestion(id:"q",version:1,segmentID:"s",prompt:"اختبار",answer:"evet",explanation:"نعم",choices:[])
        var bad = LearningProgress()
        bad.session = PracticeSession(mode: .writing, questions: [q])
        bad.session?.index = -1
        try JSONEncoder().encode(bad).write(to: badRoot.appendingPathComponent("progress-v1.json"))
        let rejected = ProgressStore(directory: badRoot)
        check(rejected.errorMessage != nil && rejected.progress.session == nil, "Malformed semantic session rejected safely")
        print("Disk progress checks passed.")
    }
}

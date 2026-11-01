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
        check(try FileManager.default.contentsOfDirectory(atPath: root.path).contains(where: {$0.hasPrefix("unreadable-")}), "Corrupt primary retained")
        try Data("corrupt".utf8).write(to: primary)
        try Data("also corrupt".utf8).write(to: root.appendingPathComponent("progress-v1.previous.json"))
        let d = ProgressStore(directory: root)
        d.visit("must-not-overwrite")
        check(d.errorMessage != nil, "Both invalid reported")
        check(String(data: try Data(contentsOf: primary), encoding: .utf8) == "corrupt", "Both invalid not silently replaced")
        print("Disk progress checks passed.")
    }
}

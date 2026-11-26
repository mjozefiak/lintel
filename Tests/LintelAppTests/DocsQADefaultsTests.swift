import Foundation
import Testing

/// QA cleanup must only ever touch the QA defaults domain: `defaults delete com.lintelapp.Lintel` (without `.QA`)
/// would erase the settings of the owner's real app.
@Suite struct DocsQADefaultsTests {
    @Test func noDocOrScriptDeletesTheRealAppsDefaultsDomain() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let pattern = try Regex(#"defaults\s+(?:-\S+\s+)*delete\s+["']?com\.lintelapp\.Lintel(?!\.QA)"#)
        // The one allowed mention is the warning in docs/qa.md that names the forbidden command.
        let allowed = "(without `.QA`)"
        var offenders: [String] = []
        let targets = ["docs", "scripts", ".ai", "AGENTS.md", "SDLC.md"]
        for target in targets {
            let base = root.appending(path: target)
            var isDirectory: ObjCBool = false
            #expect(
                FileManager.default.fileExists(atPath: base.path, isDirectory: &isDirectory),
                "\(target) is missing")
            var urls: [URL] = [base]
            if isDirectory.boolValue {
                let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
                urls = (files?.compactMap { $0 as? URL }) ?? []
            }
            var scanned = 0
            for url in urls {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                scanned += 1
                for line in text.split(separator: "\n") where line.contains(pattern) && !line.contains(allowed) {
                    offenders.append(url.lastPathComponent)
                }
            }
            #expect(scanned > 0, "nothing scanned under \(target)")
        }
        #expect(offenders.isEmpty, "real-app defaults delete in: \(offenders)")
    }
}

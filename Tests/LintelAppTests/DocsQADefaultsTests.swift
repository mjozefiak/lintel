import Foundation
import Testing

/// QA cleanup must only ever touch the QA defaults domain: `defaults delete com.lintelapp.Lintel` (without `.QA`)
/// would erase the settings of the owner's real app.
@Suite struct DocsQADefaultsTests {
    @Test func noDocOrScriptDeletesTheRealAppsDefaultsDomain() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let pattern = try Regex(#"defaults\s+delete\s+["']?com\.lintelapp\.Lintel(?!\.QA)"#)
        // The one allowed mention is the warning in docs/qa.md that names the forbidden command.
        let allowed = "(without `.QA`)"
        var offenders: [String] = []
        var scanned = 0
        let targets = ["docs", "scripts", ".ai", "AGENTS.md", "SDLC.md"]
        for target in targets {
            let base = root.appending(path: target)
            var urls: [URL] = [base]
            if let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) {
                urls = files.compactMap { $0 as? URL }
            }
            for url in urls {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                scanned += 1
                for line in text.split(separator: "\n") where line.contains(pattern) && !line.contains(allowed) {
                    offenders.append(url.lastPathComponent)
                }
            }
        }
        #expect(scanned > 0)
        #expect(offenders.isEmpty, "real-app defaults delete in: \(offenders)")
    }
}

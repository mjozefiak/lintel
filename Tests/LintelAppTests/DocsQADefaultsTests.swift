import Foundation
import Testing

/// QA cleanup must only ever touch the QA defaults domain: `defaults delete com.lintelapp.Lintel` (without `.QA`)
/// would erase the settings of the owner's real app.
@Suite struct DocsQADefaultsTests {
    @Test func noDocOrScriptDeletesTheRealAppsDefaultsDomain() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let pattern = try Regex(#"defaults\s+delete\s+com\.lintelapp\.Lintel(?!\.QA)"#)
        var offenders: [String] = []
        for folder in ["docs", "scripts"] {
            let base = root.appending(path: folder)
            guard let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else {
                continue
            }
            for case let url as URL in files {
                guard ["md", "sh", "zsh", "yml"].contains(url.pathExtension),
                    url.lastPathComponent != "DocsQADefaultsTests.swift",
                    let text = try? String(contentsOf: url, encoding: .utf8)
                else { continue }
                for line in text.split(separator: "\n") where line.contains(pattern) {
                    let isWarning = line.contains("never run") || line.contains("Warning")
                    if !isWarning { offenders.append(url.lastPathComponent) }
                }
            }
        }
        #expect(offenders.isEmpty, "real-app defaults delete in: \(offenders)")
    }
}

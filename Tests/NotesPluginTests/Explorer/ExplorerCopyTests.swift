import Foundation
import Testing

/// C5 (no jargon) and C6 (help of at most 15 words, decided per sentence) of the foolproof checklist, over the
/// strings the explorer and its preview own (their catalog comments start with "Explorer", "Preview" or
/// "Sidebar and list"), in English and in Polish, except the older "Explorer: state line" strings.
@Suite("Explorer: copy rules (C5, C6)")
struct ExplorerCopyTests {
    private struct Entry {
        var key: String
        var en: String
        var pl: String
    }

    private static let catalogURL: URL = {
        var url = URL(filePath: #filePath).deletingLastPathComponent()
        while url.path != "/", !FileManager.default.fileExists(atPath: url.appending(path: "Package.swift").path) {
            url = url.deletingLastPathComponent()
        }
        return url.appending(path: "Resources/Localizable.xcstrings")
    }()

    private static func entries() throws -> [Entry] {
        let data = try Data(contentsOf: catalogURL)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(root["strings"] as? [String: [String: Any]])
        var result: [Entry] = []
        for (key, value) in strings {
            let comment = value["comment"] as? String ?? ""
            guard ["Explorer", "Preview", "Sidebar and list"].contains(where: comment.hasPrefix) else { continue }
            // The older state lines (`NoteRowPresentation.stateText`) are not new copy: the explorer's rows say their
            // own words (`ExplorerRowText.state`), which this test does cover.
            if comment.hasPrefix("Explorer: state line") { continue }
            let localizations = value["localizations"] as? [String: [String: Any]] ?? [:]
            func text(_ language: String) -> String? {
                (localizations[language]?["stringUnit"] as? [String: Any])?["value"] as? String
            }
            // A plural has no single string; its words are the unit and the count.
            guard let en = text("en"), let pl = text("pl") else { continue }
            result.append(Entry(key: key, en: en, pl: pl))
        }
        return result
    }

    @Test("every explorer string has an English and a Polish value")
    func bothLanguages() throws {
        let all = try Self.entries()
        #expect(all.count > 20)
        for entry in all {
            #expect(!entry.en.isEmpty && !entry.pl.isEmpty, "\(entry.key)")
        }
    }

    @Test("no jargon in the explorer's words")
    func noJargon() throws {
        let english = [
            "model", "llm", "server", "index", "plugin", "parakeet", "whisper", "gguf", "token", "diarization",
        ]
        let polish = ["model", "llm", "serwer", "indeks", "wtyczk", "parakeet", "whisper", "gguf", "token", "diaryzac"]
        for entry in try Self.entries() {
            let en = entry.en.lowercased()
            let pl = entry.pl.lowercased()
            for word in english { #expect(!en.contains(word), "\(entry.key): \(word)") }
            for word in polish { #expect(!pl.contains(word), "\(entry.key): \(word)") }
        }
    }

    @Test("no sentence is longer than 15 words")
    func shortSentences() throws {
        for entry in try Self.entries() {
            for text in [entry.en, entry.pl] {
                let cleaned = text.replacingOccurrences(of: "%@", with: "x").replacingOccurrences(of: "%lld", with: "1")
                for sentence in cleaned.split(whereSeparator: { ".!?".contains($0) }) {
                    let words = sentence.split(separator: " ").count
                    #expect(words <= 15, "\(entry.key): \(sentence)")
                }
            }
        }
    }
}

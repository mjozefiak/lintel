import Foundation
import Testing

@testable import DictationPlugin

/// The popup's examples tell the truth: the Light example is what `LightCleaner` really does to it, in both
/// languages (the strings come from the catalog), and the Standard example only claims what the prompt does.
@Suite struct TidyUpTextTests {
    private struct Catalog: Decodable {
        struct Entry: Decodable {
            struct Localization: Decodable {
                struct Unit: Decodable { let value: String }
                let stringUnit: Unit?
            }
            let localizations: [String: Localization]?
        }
        let strings: [String: Entry]
    }

    private static let root: URL = {
        var url = URL(filePath: #filePath).deletingLastPathComponent()
        while url.path != "/", !FileManager.default.fileExists(atPath: url.appending(path: "Package.swift").path) {
            url = url.deletingLastPathComponent()
        }
        return url
    }()

    private static func catalog() throws -> Catalog {
        let url = root.appending(path: "Resources/Localizable.xcstrings")
        return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    }

    private func value(_ key: String, _ language: String) throws -> String {
        let entry = try #require(Self.catalog().strings[key], "\(key) is not in the catalog")
        return try #require(entry.localizations?[language]?.stringUnit?.value, "\(key) has no \(language) value")
    }

    @Test func offHasNoExampleAndTheOtherValuesHaveOne() {
        #expect(TidyUpText.example(.off) == nil)
        #expect(TidyUpText.example(.light) != nil)
        #expect(TidyUpText.example(.standard) != nil)
    }

    @Test func theLightExampleIsWhatTheCleanerReallyDoes() throws {
        let example = try #require(TidyUpText.example(.light))
        // The process runs in English under `swift test`: the sentences are the keys themselves.
        #expect(LightCleaner.clean(example.before) == example.after)
        // The Polish pair comes from the catalog and is checked the same way.
        let before = try value(example.before, "pl")
        let after = try value(example.after, "pl")
        #expect(LightCleaner.clean(before) == after)
        #expect(before != after)
    }

    @Test func theLightExampleChangesOnlyAFillerAndItsPunctuation() throws {
        let example = try #require(TidyUpText.example(.light))
        func words(_ text: String) -> [String] {
            text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        }
        let kept = words(example.before).filter { !LightCleaner.fillers.contains($0) }
        #expect(kept == words(example.after))
    }

    @Test func everyTextOfTheRowHasEnglishAndPolish() throws {
        let keys = [
            "Tidy up my text", "Off", "Light", "Standard", "Pastes exactly what you said.",
            "Removes “um” and “uh”. Never changes your words.",
            "Also keeps only your corrections and turns spoken lists into lists.", "Example: %@ becomes %@",
        ]
        for key in keys {
            #expect(try value(key, "en") == key)
            #expect(try !value(key, "pl").isEmpty)
        }
        #expect(try value("Light", "pl") == "Lekkie")
        #expect(try value("Standard", "pl") == "Standardowe")
        #expect(try value("Off", "pl") == "Wyłączone")
        #expect(try value("Tidy up my text", "pl") == "Porządkuj mój tekst")
    }

    @Test func theHelpLinesAreShort() throws {
        for key in [
            "Pastes exactly what you said.", "Removes “um” and “uh”. Never changes your words.",
            "Also keeps only your corrections and turns spoken lists into lists.",
        ] {
            for language in ["en", "pl"] {
                let words = try value(key, language).split(separator: " ").count
                #expect(words <= 15, "\(key) (\(language)) has \(words) words")
            }
        }
    }
}

import Foundation
import Testing

/// The words of the onboarding pages (spec `2026-11-24-first-run-onboarding`, UI/UX, "Copy"): every string has an
/// English and a Polish value, no jargon from the C5 list, no exclamation marks, short sentences, and Lintel is
/// never declined in Polish. The strings are found by scanning the sources, so a new one cannot escape the checks.
@Suite struct OnboardingCopyTests {
    private static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    private struct Catalog: Decodable {
        struct Entry: Decodable {
            struct Localization: Decodable {
                struct Unit: Decodable {
                    let state: String
                    let value: String
                }
                let stringUnit: Unit?
            }
            let localizations: [String: Localization]?
        }
        let strings: [String: Entry]
    }

    private static func catalog() throws -> Catalog {
        let data = try Data(contentsOf: root.appending(path: "Resources/Localizable.xcstrings"))
        return try JSONDecoder().decode(Catalog.self, from: data)
    }

    static func sources() throws -> [(name: String, code: String)] {
        let folder = root.appending(path: "Sources/LintelUI/Onboarding")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path()).filter {
            $0.hasSuffix(".swift")
        }
        return try names.sorted().map { ($0, try String(contentsOf: folder.appending(path: $0), encoding: .utf8)) }
    }

    /// The catalog keys the onboarding sources use: `String(localized: "key", comment: …)` and `Text("key")`.
    /// A Swift interpolation becomes the format specifier of its type; only whole numbers are used.
    static func keys() throws -> [String] {
        let call = /String\(\s*localized:\s*"((?:[^"\\]|\\.)*)"/
        let text = /Text\("((?:[^"\\]|\\.)*)"\)/
        var keys = Set<String>()
        for (_, code) in try sources() {
            for match in code.matches(of: call) { keys.insert(String(match.1)) }
            for match in code.matches(of: text) { keys.insert(String(match.1)) }
        }
        return keys.map {
            $0.replacingOccurrences(of: #"\\\([^)]*\)"#, with: "%lld", options: .regularExpression)
            // A number drawn on its own ("3" in a step's circle) is not a string to translate.
        }.filter { $0 != "%lld" }.sorted()
    }

    @Test func theScanFindsTheStringsOfEveryPage() throws {
        let keys = try Self.keys()
        for key in [
            "What would you like Lintel to do?", "Your words stay on this Mac", "Lintel needs your OK for a few things",
            "Step %lld of %lld", "Set Up Both", "Needs your OK", "Not needed now", "Back",
        ] {
            #expect(keys.contains(key), "the scan missed \(key)")
        }
        #expect(keys.count >= 40)
    }

    @Test func everyStringHasATranslatedEnglishAndPolishValue() throws {
        let catalog = try Self.catalog()
        for key in try Self.keys() {
            let entry = try #require(catalog.strings[key], "\(key) is not in the catalog")
            for language in ["en", "pl"] {
                let unit = entry.localizations?[language]?.stringUnit
                #expect(unit?.state == "translated", "\(key) \(language)")
                #expect(unit?.value.isEmpty == false, "\(key) \(language)")
            }
        }
    }

    /// C5 (research-foolproof-ui), with the Polish forms, plus the system names the spec keeps out of the basics
    /// (Accessibility, Full Disk Access, System Audio Recording).
    static var jargon: Regex<(Substring, Substring)> {
        /(?i:\b(model|llm|server|serwer|address|adres|endpoint|bundle|index|indeks|ranking|diagnost|launcher|plugin|wtyczk|parakeet|whisper|gguf|token|diarization|diaryzacj|accessibility|dostępno|full disk|pełn\w+ dostęp\w* do dysku|system audio|system settings)\w*)/
    }

    private static func values(_ language: String) throws -> [(key: String, value: String)] {
        let catalog = try catalog()
        return try keys().map { key in
            (key, try #require(catalog.strings[key]?.localizations?[language]?.stringUnit?.value, "\(key)"))
        }
    }

    @Test func noStringHasJargonInEitherLanguage() throws {
        for language in ["en", "pl"] {
            for (key, value) in try Self.values(language) {
                // "Settings → Privacy & data" is the name of a place the user opens; it is not a system pane.
                #expect(value.firstMatch(of: Self.jargon) == nil, "\(key) (\(language)) → \(value)")
            }
        }
    }

    @Test func theJargonCheckCatchesWhatItShouldAndOnlyThat() {
        #expect("Allow Accessibility".firstMatch(of: Self.jargon) != nil)
        #expect("Pliki na modelu".firstMatch(of: Self.jargon) != nil)
        #expect("Uruchom serwer".firstMatch(of: Self.jargon) != nil)
        #expect("Open System Settings".firstMatch(of: Self.jargon) != nil)
        #expect("Type into other apps".firstMatch(of: Self.jargon) == nil)
        #expect("Hear other people in a call".firstMatch(of: Self.jargon) == nil)
        #expect("Microphone".firstMatch(of: Self.jargon) == nil)
    }

    @Test func noStringHasAnExclamationMark() throws {
        for language in ["en", "pl"] {
            for (key, value) in try Self.values(language) {
                #expect(!value.contains("!"), "\(key) (\(language)) → \(value)")
            }
        }
    }

    @Test func everySentenceIsShortEnoughForOneGlance() throws {
        // About 15 words at most (tone of voice, #247), counted per sentence.
        for language in ["en", "pl"] {
            for (key, value) in try Self.values(language) {
                let sentences = value.split(whereSeparator: { ".?".contains($0) })
                for sentence in sentences {
                    // An arrow or an ampersand is not a word.
                    let words = sentence.split(separator: " ").filter { $0.contains(where: \.isLetter) }.count
                    #expect(words <= 15, "\(key) (\(language)): \(words) words in “\(sentence)”")
                }
            }
        }
    }

    @Test func polishNeverDeclinesTheAppName() throws {
        let inflected = /Lintel(?:[\p{Ll}]|['’\-]\p{Ll})/
        let bareInOtherCase =
            /(?i:\b(?:o|w|we|z|ze|dla|do|od|przy|pozwala|pozwól|zezwól|uruchomić|uruchomienia|oknie|okna|schowka|samego)\s+Lintel\b)/
        for (key, value) in try Self.values("pl") {
            #expect(value.firstMatch(of: inflected) == nil, "\(key) → \(value)")
            #expect(value.firstMatch(of: bareInOtherCase) == nil, "\(key) → \(value)")
        }
    }

    @Test func theDeclensionCheckCatchesWhatItShouldAndOnlyThat() {
        let inflected = /Lintel(?:[\p{Ll}]|['’\-]\p{Ll})/
        let bare =
            /(?i:\b(?:o|w|we|z|ze|dla|do|od|przy|pozwala|pozwól|zezwól|uruchomić|uruchomienia|oknie|okna|schowka|samego)\s+Lintel\b)/
        #expect("Otwórz Lintela".firstMatch(of: inflected) != nil)
        #expect("Zezwól Lintel".firstMatch(of: bare) != nil)
        #expect("Lintel potrzebuje Twojej zgody".firstMatch(of: inflected) == nil)
        #expect("Najpierw przenieś aplikację Lintel do folderu Aplikacje".firstMatch(of: bare) == nil)
    }

    @Test func thePolishWordsAreTheOwnersPrototypeWhereThePrototypeHasThem() throws {
        let catalog = try Self.catalog()
        let expected = [
            "What would you like Lintel to do?": "W czym Lintel ma Ci pomagać?",
            "Your words stay on this Mac": "Twoje słowa zostają na tym Macu",
            "Lintel needs your OK for a few things": "Lintel potrzebuje Twojej zgody na kilka rzeczy",
            "Step %lld of %lld": "Krok %lld z %lld",
            "Your goal": "Twój cel",
            "You can change this later in Settings.": "Zmienisz to później w Ustawieniach.",
        ]
        for (key, polish) in expected {
            #expect(catalog.strings[key]?.localizations?["pl"]?.stringUnit?.value == polish, "\(key)")
        }
    }
}

import Foundation
import SwiftUI
import Testing

@testable import LintelUI

/// The floating helper's view: its words, and that its copy follows the product's rules (spec 2026-11-24, UI/UX:
/// "Copy": calm, no jargon (C5), Lintel is never declined in Polish).
@Suite struct PermissionHelperViewTests {
    private static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    /// The words the helper shows, as catalog keys.
    private static let keys = [
        "Drag Lintel into the list, then turn on its switch.", "Turn on the switch next to Lintel.",
        "Show Lintel in Finder", "Done", "Allowed",
    ]

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

    private func catalog() throws -> Catalog {
        let data = try Data(contentsOf: Self.root.appending(path: "Resources/Localizable.xcstrings"))
        return try JSONDecoder().decode(Catalog.self, from: data)
    }

    @Test func eachStateAsksForOneThingAndAllowedSaysNothingMore() {
        let drag = PermissionHelperView<EmptyView>.sentence(for: .dragTile)
        let toggle = PermissionHelperView<EmptyView>.sentence(for: .turnOnSwitch)
        #expect(drag == "Drag Lintel into the list, then turn on its switch.")
        #expect(toggle == "Turn on the switch next to Lintel.")
        #expect(PermissionHelperView<EmptyView>.sentence(for: .allowed) == nil)
        #expect(PermissionHelperView<EmptyView>.showInFinderTitle == "Show Lintel in Finder")
        #expect(PermissionHelperView<EmptyView>.doneTitle == "Done")
    }

    @Test func everyStringHasATranslatedEnglishAndPolishValue() throws {
        let catalog = try catalog()
        for key in Self.keys {
            let entry = try #require(catalog.strings[key], "\(key) is not in the catalog")
            for language in ["en", "pl"] {
                let unit = entry.localizations?[language]?.stringUnit
                #expect(unit?.state == "translated", "\(key) \(language)")
                #expect(unit?.value.isEmpty == false, "\(key) \(language)")
            }
        }
    }

    @Test func theCopyHasNoJargonInEitherLanguage() throws {
        // C5 (research-foolproof-ui): words that stay under "More options". Polish forms included.
        let jargon =
            /(?i:\b(model|llm|server|serwer|address|adres|endpoint|bundle|index|indeks|ranking|diagnost|launcher|plugin|wtyczk|parakeet|whisper|gguf|token|diarization|diaryzacj)\w*)/
        let catalog = try catalog()
        for key in Self.keys {
            for language in ["en", "pl"] {
                let value = try #require(catalog.strings[key]?.localizations?[language]?.stringUnit?.value)
                #expect(value.firstMatch(of: jargon) == nil, "\(key) (\(language)) → \(value)")
                #expect(!value.contains("!"), "\(key) (\(language)) has an exclamation mark")
            }
        }
    }

    @Test func thePolishCopyKeepsTheAppNameInTheNominative() throws {
        let catalog = try catalog()
        let inflected = /Lintel(?:[\p{Ll}]|['’\-]\p{Ll})/
        for key in Self.keys {
            let value = try #require(catalog.strings[key]?.localizations?["pl"]?.stringUnit?.value)
            #expect(value.firstMatch(of: inflected) == nil, "\(key) → \(value)")
        }
        #expect(
            catalog.strings["Drag Lintel into the list, then turn on its switch."]?.localizations?["pl"]?.stringUnit?
                .value == "Przeciągnij Lintel na listę, a potem włącz przełącznik.")
    }

    /// Owner decision (2026-11-26, the sheet's copy review): the Polish button drops the app name, the English key
    /// keeps it. The button sits under a sentence that already says where Lintel is.
    @Test func theFinderButtonDropsTheAppNameInPolish() throws {
        let catalog = try catalog()
        let entry = try #require(catalog.strings["Show Lintel in Finder"])
        #expect(entry.localizations?["pl"]?.stringUnit?.value == "Pokaż w Finderze")
        #expect(entry.localizations?["en"]?.stringUnit?.value == "Show Lintel in Finder")
    }

    @Test func theSentencesAreShortEnoughForOneGlance() throws {
        // About 15 words at most (tone of voice, #247).
        let catalog = try catalog()
        for key in Self.keys {
            for language in ["en", "pl"] {
                let value = try #require(catalog.strings[key]?.localizations?[language]?.stringUnit?.value)
                #expect(value.split(separator: " ").count <= 15, "\(key) (\(language))")
            }
        }
    }
}

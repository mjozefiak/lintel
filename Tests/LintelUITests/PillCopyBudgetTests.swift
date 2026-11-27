import Foundation
import Testing

/// The pill copy budget (spec `2026-11-25-minimal-hud`, "The pill family" and "Copy"): every visible pill string is at
/// most 40 characters in English and in Polish. A key belongs to the budget when its comment starts with `HUD pill:`;
/// a text only VoiceOver hears (comment `HUD pill, VoiceOver:`, e.g. "Don't ask again for %@") is outside it. A `%@`
/// counts as 20 characters (a device or app name, shortened by the pill beyond that), a number as 3 characters.
enum PillCopyBudget {
    static let limit = 40
    static let commentPrefix = "HUD pill:"
    static let objectWidth = 20
    static let numberWidth = 3

    struct Violation: Equatable, CustomStringConvertible {
        var key: String
        var language: String
        var text: String
        var length: Int

        var description: String { "\(key) [\(language)] \(length) characters: \(text)" }
    }

    struct Result {
        /// Every key in the catalog, and the ones in the budget.
        var keys = 0
        var budgetKeys: [String] = []
        var violations: [Violation] = []
    }

    /// The length the budget counts: placeholders at their stand-in widths, `%%` as one character, everything else
    /// as user-perceived characters.
    static func length(of text: String) -> Int {
        let pattern = #"%(?:\d+\$)?(?:@|l{0,2}[diuxX]|[0-9.]*f|%)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text.count }
        var length = 0
        var cursor = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            length += text[cursor..<range.lowerBound].count
            let token = text[range]
            let width =
                if token == "%%" { 1 } else if token.hasSuffix("@") { objectWidth } else { numberWidth }
            length += width
            cursor = range.upperBound
        }
        return length + text[cursor...].count
    }

    /// Checks a decoded `Localizable.xcstrings`.
    static func check(catalog: [String: Any]) -> Result {
        var result = Result()
        let strings = catalog["strings"] as? [String: Any] ?? [:]
        result.keys = strings.count
        for key in strings.keys.sorted() {
            guard let entry = strings[key] as? [String: Any],
                let comment = entry["comment"] as? String, comment.hasPrefix(commentPrefix)
            else { continue }
            result.budgetKeys.append(key)
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            var texts: [(language: String, text: String)] = []
            for (language, value) in localizations {
                texts += values(in: value).map { (language, $0) }
            }
            // The source text is the key itself while the catalog has no English localization for it.
            if localizations["en"] == nil { texts.append(("en", key)) }
            for (language, text) in texts {
                let length = length(of: text)
                if length > limit {
                    result.violations.append(Violation(key: key, language: language, text: text, length: length))
                }
            }
        }
        return result
    }

    /// Every `stringUnit.value` below a localization: the plain one and every plural or device variation.
    static func values(in node: Any) -> [String] {
        guard let dictionary = node as? [String: Any] else { return [] }
        var found: [String] = []
        if let unit = dictionary["stringUnit"] as? [String: Any], let value = unit["value"] as? String {
            found.append(value)
        }
        for (key, child) in dictionary where key != "stringUnit" {
            found += values(in: child)
        }
        return found
    }
}

@Suite struct PillCopyBudgetTests {
    private static func entry(comment: String, en: String?, pl: String) -> [String: Any] {
        var localizations: [String: Any] = ["pl": ["stringUnit": ["state": "translated", "value": pl]]]
        if let en { localizations["en"] = ["stringUnit": ["state": "translated", "value": en]] }
        return ["comment": comment, "localizations": localizations]
    }

    @Test func placeholdersCountAtTheirStandInWidths() {
        #expect(PillCopyBudget.length(of: "Using %@") == 6 + 20)
        #expect(PillCopyBudget.length(of: "Meeting in %1$@") == 11 + 20)
        #expect(PillCopyBudget.length(of: "Transkrybuję, zostały %lld") == 22 + 3)
        #expect(PillCopyBudget.length(of: "%d%% done") == 3 + 1 + 5)
        #expect(PillCopyBudget.length(of: "Łączenie z mikrofonem…") == 22)
        #expect(PillCopyBudget.length(of: "Poprzednie spotkanie wciąż się zapisuje") == 39)
    }

    @Test func aKeyOverTheBudgetInEitherLanguageIsReported() {
        let catalog: [String: Any] = [
            "strings": [
                "Short": Self.entry(comment: "HUD pill: a fine line", en: "Short", pl: "Krótko"),
                "Too long in Polish": Self.entry(
                    comment: "HUD pill: line", en: "Too long in Polish",
                    pl: "Ta linia jest zdecydowanie za długa na pastylkę"),
                "Using %@ today and tomorrow too": Self.entry(
                    comment: "HUD pill: device", en: "Using %@ today and tomorrow too", pl: "Mikrofon: %@"),
                "No en localization, a long key over budget": Self.entry(
                    comment: "HUD pill: source", en: nil, pl: "Krótko"),
            ]
        ]
        let result = PillCopyBudget.check(catalog: catalog)
        #expect(result.budgetKeys.count == 4)
        #expect(
            Set(result.violations.map { "\($0.key)|\($0.language)" }) == [
                "Too long in Polish|pl", "Using %@ today and tomorrow too|en",
                "No en localization, a long key over budget|en",
            ])
    }

    @Test func pluralVariationsAreCheckedToo() {
        let catalog: [String: Any] = [
            "strings": [
                "Transcribing, %lld left": [
                    "comment": "HUD pill: processing",
                    "localizations": [
                        "en": ["stringUnit": ["state": "translated", "value": "Transcribing, %lld left"]],
                        "pl": [
                            "variations": [
                                "plural": [
                                    "one": [
                                        "stringUnit": ["state": "translated", "value": "Transkrybuję, został %lld"]
                                    ],
                                    "many": [
                                        "stringUnit": [
                                            "state": "translated",
                                            "value": "Transkrybuję wszystko, co zostało, czyli jeszcze %lld",
                                        ]
                                    ],
                                ]
                            ]
                        ],
                    ],
                ]
            ]
        ]
        let violations = PillCopyBudget.check(catalog: catalog).violations
        #expect(violations.count == 1 && violations.first?.language == "pl")
    }

    @Test func onlyKeysWithTheHUDPillCommentAreInTheBudget() {
        let long = "A long accessibility sentence that only VoiceOver ever reads aloud"
        let catalog: [String: Any] = [
            "strings": [
                long: Self.entry(comment: "HUD pill, VoiceOver: the hover link's full name", en: long, pl: long),
                "Other": Self.entry(comment: "Settings row", en: long, pl: long),
                "No comment": ["localizations": [:]],
            ]
        ]
        let result = PillCopyBudget.check(catalog: catalog)
        #expect(result.budgetKeys.isEmpty && result.violations.isEmpty && result.keys == 3)
    }

    /// The real catalog: every pill key of both languages is within 40 characters.
    @Test func everyPillStringOfTheAppIsWithinTheBudget() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appending(path: "Resources/Localizable.xcstrings"))
        let catalog = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = PillCopyBudget.check(catalog: catalog)
        // The catalog was read (a wrong path or format would check nothing).
        #expect(result.keys > 500)
        #expect(result.violations.isEmpty, "\(result.violations)")
    }
}

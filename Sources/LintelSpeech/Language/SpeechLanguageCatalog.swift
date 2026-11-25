import Foundation

/// The writing system a language is transcribed in. Parakeet's script hint can limit its decoder to one of
/// `latin`, `cyrillic` or `greek`; everything else is `other` and never gets a hint.
public enum LanguageScript: String, Sendable, Equatable, Hashable, CaseIterable {
    case latin
    case cyrillic
    case greek
    case other
}

/// One language Lintel can be told about.
public struct SpeechLanguage: Sendable, Equatable, Identifiable {
    /// Whisper's language code: ISO 639-1 where one exists, plus a few others (`haw`, `yue`).
    public let code: String
    public let script: LanguageScript
    /// Parakeet TDT v3 transcribes it.
    public let parakeetSupported: Bool
    /// Whisper large-v3-turbo transcribes it (every catalog entry: the catalog is Whisper's list).
    public let whisperSupported: Bool

    public var id: String { code }
}

/// The languages a user can list for dictation and meetings (spec 2026-11-23-automatic-language-detection).
/// It is the list Whisper large-v3-turbo knows; Parakeet TDT v3's 25 languages are a subset, marked per entry.
/// Display names are not here: the UI asks `Locale.localizedString(forLanguageCode:)`.
public enum SpeechLanguageCatalog {
    /// Parakeet TDT v3's languages.
    static let parakeetCodes: Set<String> = [
        "bg", "cs", "da", "de", "el", "en", "es", "et", "fi", "fr", "hr", "hu", "it", "lt", "lv", "mt", "nl",
        "pl", "pt", "ro", "ru", "sk", "sl", "sv", "uk",
    ]

    private static let latin =
        "en de es fr pt tr pl ca nl sv it id fi vi ms cs ro da hu no hr la mi cy sk lv lt az sl et br eu is bs sq sw "
        + "gl af oc uz fo ht tk mt lb tl mg haw ln ha jw su sn yo so"
    private static let cyrillic = "ru uk bg be mk mn kk tg tt ba"
    private static let greek = "el"
    /// Serbian is written in both Cyrillic and Latin, so it gets no script hint either way.
    private static let other =
        "zh ko ja ar hi he ta th ur fa ml te bn kn hy ne mr pa si km ka sd gu am yi lo ps sa my bo as yue sr"

    /// Every language, grouped by script (the UI sorts by localized name).
    public static let all: [SpeechLanguage] = {
        func entries(_ codes: String, _ script: LanguageScript) -> [SpeechLanguage] {
            codes.split(separator: " ").map {
                SpeechLanguage(
                    code: String($0), script: script, parakeetSupported: parakeetCodes.contains(String($0)),
                    whisperSupported: true)
            }
        }
        return entries(latin, .latin) + entries(cyrillic, .cyrillic) + entries(greek, .greek) + entries(other, .other)
    }()

    private static let byCode: [String: SpeechLanguage] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.code, $0) })

    public static func language(for code: String) -> SpeechLanguage? { byCode[code] }

    public static func contains(_ code: String) -> Bool { byCode[code] != nil }

    /// Codes other systems use for a language the catalog lists under another one.
    private static let aliases: [String: String] = [
        "nb": "no", "nn": "no", "iw": "he", "jv": "jw", "fil": "tl", "in": "id", "mo": "ro", "zh-hans": "zh",
        "zh-hant": "zh",
    ]

    /// Reduces a locale or language identifier (`pl-PL`, `zh-Hans-CN`, `nb`) to a catalog code, or `nil` when the
    /// catalog does not list that language. The language subtag decides; `yue` and `haw` are three-letter
    /// codes the catalog itself uses.
    public static func normalize(_ identifier: String) -> String? {
        let lowered = identifier.lowercased().replacingOccurrences(of: "_", with: "-")
        if let alias = aliases[lowered] { return byCode[alias] != nil ? alias : nil }
        let subtag = lowered.split(separator: "-").first.map(String.init) ?? lowered
        let code = aliases[subtag] ?? subtag
        return byCode[code] != nil ? code : nil
    }

    /// The scripts of a set of language codes. A code that is not in the catalog counts as `other`, so a
    /// caller never assumes a script it does not know.
    public static func scripts(of codes: [String]) -> Set<LanguageScript> {
        Set(codes.map { byCode[$0]?.script ?? .other })
    }
}

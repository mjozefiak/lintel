import FluidAudio
import Foundation

/// The script hint Parakeet takes (FluidAudio's `TokenLanguageFilter`): it limits the decoder to one writing
/// system, it does not pick a language. Sent only when every language in play is written in one known script,
/// so Cyrillic or Greek speech is never forced into Latin letters (issues #132, #210).
///
/// The plugins send it per request (`SpeechRequestOptions.scriptHint`) since step 2.3 of the spec. `ParakeetLanguage`
/// (only `pl` and `en`) is left only as the default of `ParakeetEngine(language:)` for tools and tests.
public enum ScriptHint: String, Sendable, Equatable, CaseIterable {
    case latin
    case cyrillic
    case greek

    /// A language of the hint's script, in FluidAudio's terms. Every Latin-script case filters the same tokens.
    var fluidAudioLanguage: Language {
        switch self {
        case .latin: .english
        case .cyrillic: .russian
        case .greek: .greek
        }
    }

    /// The hint for a set of scripts: one hintable script gives it, `other`, a mix or no scripts give `nil`.
    public static func hint(for scripts: Set<LanguageScript>) -> ScriptHint? {
        guard scripts.count == 1, let script = scripts.first else { return nil }
        switch script {
        case .latin: return .latin
        case .cyrillic: return .cyrillic
        case .greek: return .greek
        case .other: return nil
        }
    }

    /// The hint for language codes. An empty list, a code outside the catalog or any language in another
    /// script gives `nil`.
    public static func hint(forLanguages codes: [String]) -> ScriptHint? {
        guard !codes.isEmpty else { return nil }
        return hint(for: SpeechLanguageCatalog.scripts(of: codes))
    }
}

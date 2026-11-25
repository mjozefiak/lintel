import Foundation

/// The two speech models.
public enum SpeechModelFamily: String, Sendable, Equatable {
    case parakeet
    case whisper
}

/// Decides which engine a recording or a dictation starts with (spec: "Automatic switch to Whisper", owner
/// decision D3), from the model chosen in Settings, the languages in play and what is installed. Pure.
///
/// The engine is fixed per recording; Lintel never downloads Whisper by itself, so when it is needed and not
/// there the answer is Parakeet without a script hint plus the language to name in the "Get Whisper" banner.
public enum SpeechEngineRouter {
    public struct Decision: Sendable, Equatable {
        public let engine: SpeechModelFamily
        /// A Parakeet decoding may send a script hint. `false` when the languages need a model that is missing.
        public let allowsScriptHint: Bool
        /// The first language Parakeet cannot transcribe while Whisper is not installed: the banner asks for
        /// Whisper for it. `nil` when nothing is missing.
        public let missingWhisperLanguage: String?
    }

    /// - Parameters:
    ///   - selected: the model chosen in Settings.
    ///   - languages: the languages in play: the one language in "Always one language" mode, otherwise the
    ///     user's list. Codes outside the catalog are ignored; they need no model.
    ///   - whisperInstalled: the Whisper model is in the models folder.
    public static func decide(
        selected: SpeechModelFamily, languages: [String], whisperInstalled: Bool
    ) -> Decision {
        if selected == .whisper {
            return Decision(engine: .whisper, allowsScriptHint: false, missingWhisperLanguage: nil)
        }
        let needsWhisper = languages.first { code in
            SpeechLanguageCatalog.language(for: code).map { !$0.parakeetSupported && $0.whisperSupported } ?? false
        }
        guard let needsWhisper else {
            return Decision(engine: .parakeet, allowsScriptHint: true, missingWhisperLanguage: nil)
        }
        if whisperInstalled {
            return Decision(engine: .whisper, allowsScriptHint: false, missingWhisperLanguage: nil)
        }
        return Decision(engine: .parakeet, allowsScriptHint: false, missingWhisperLanguage: needsWhisper)
    }
}

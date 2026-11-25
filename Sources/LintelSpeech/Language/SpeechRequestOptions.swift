import Foundation

/// How Whisper picks the language of one request.
public enum WhisperLanguageChoice: Sendable, Equatable {
    /// Decode in this language (today's behaviour: a code such as `pl`).
    case pinned(String)
    /// Detect the language among `candidates` only, from the audio, and decode in it. When the detection fails or
    /// the audio is too short for it the engine uses `fallback`.
    case detect(candidates: [String], fallback: String)
}

/// What one transcription request asks of the engine. The hint and the language are **per request, never per
/// engine instance**: `SpeechEngineLease` shares one engine between Dictation and Meetings and ignores the engine
/// a second caller passes, so an option stored in the engine would belong to whoever loaded the model first.
public struct SpeechRequestOptions: Sendable, Equatable {
    /// Parakeet: limit the decoder to this script. `nil` sends no hint.
    public var scriptHint: ScriptHint?
    /// Whisper: how the language is chosen. `nil` keeps the language the engine was built with.
    public var whisperLanguage: WhisperLanguageChoice?

    public init(scriptHint: ScriptHint? = nil, whisperLanguage: WhisperLanguageChoice? = nil) {
        self.scriptHint = scriptHint
        self.whisperLanguage = whisperLanguage
    }

    /// No hint and no language: the engine behaves as it did before options existed.
    public static let none = SpeechRequestOptions()
}

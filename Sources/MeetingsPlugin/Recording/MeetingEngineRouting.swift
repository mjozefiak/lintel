import Foundation
import LintelKit
import LintelSpeech

/// The model a recording uses (spec `2026-11-23-automatic-language-detection`, "Automatic switch to Whisper",
/// owner decision D3): `SpeechEngineRouter` over the model chosen in Settings, the shared language setting and
/// whether Whisper is on this Mac. The recording's engine, the stored `speech_model_id`, `modelUsage` and the
/// Settings banner all ask this one place, so they never disagree.
enum MeetingEngineRouting {
    /// The family of a catalog model id; anything that is not Whisper is the standard model.
    static func family(of modelID: String) -> SpeechModelFamily {
        modelID == ModelCatalog.whisperLargeV3Turbo.id ? .whisper : .parakeet
    }

    /// The languages the setting puts in play: the one language in "Always one language" mode, else the list.
    static func languagesInPlay(_ selection: SpeechLanguageSelection) -> [String] {
        if case .single(let code) = selection.mode { return [code] }
        return selection.languages
    }

    /// The router's answer for the model chosen in Settings.
    static func decide(
        selected: ModelPackage, selection: SpeechLanguageSelection, whisperInstalled: Bool
    ) -> SpeechEngineRouter.Decision {
        SpeechEngineRouter.decide(
            selected: family(of: selected.id), languages: languagesInPlay(selection),
            whisperInstalled: whisperInstalled)
    }

    /// The package the recording would use now: the chosen one, or Whisper when the router switches to it.
    static func package(
        selected: ModelPackage, selection: SpeechLanguageSelection, whisperInstalled: Bool
    ) -> ModelPackage {
        let decision = decide(selected: selected, selection: selection, whisperInstalled: whisperInstalled)
        guard decision.engine != family(of: selected.id) else { return selected }
        return decision.engine == .whisper ? ModelCatalog.whisperLargeV3Turbo : ModelCatalog.parakeetUltra
    }

    /// Whether a Parakeet decoding may get a script hint with this setting. `false` when a language in play
    /// needs Whisper: the recording then runs on Parakeet only because Whisper is missing (table row 4, "Parakeet
    /// without hint"), or on Whisper, which takes no hint. Read per request, so a list changed mid-meeting applies
    /// to the next segment.
    static func allowsScriptHint(_ selection: SpeechLanguageSelection) -> Bool {
        SpeechEngineRouter.decide(
            selected: .parakeet, languages: languagesInPlay(selection), whisperInstalled: false
        ).allowsScriptHint
    }
}

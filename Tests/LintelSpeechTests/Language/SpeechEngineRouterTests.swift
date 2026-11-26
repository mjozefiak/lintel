import Foundation
import Testing

@testable import LintelSpeech

/// The table of the spec ("Automatic switch to Whisper"), every row.
@Suite struct SpeechEngineRouterTests {
    private struct Row: CustomTestStringConvertible {
        let selected: SpeechModelFamily
        let languages: [String]
        let whisperInstalled: Bool
        let engine: SpeechModelFamily
        let allowsHint: Bool
        let missing: String?
        var testDescription: String {
            "\(selected) \(languages) whisper=\(whisperInstalled) -> \(engine)"
        }
    }

    private static let rows: [Row] = [
        // Whisper selected: Whisper, whatever the languages.
        Row(
            selected: .whisper, languages: ["pl"], whisperInstalled: true, engine: .whisper, allowsHint: false,
            missing: nil),
        Row(
            selected: .whisper, languages: ["ja"], whisperInstalled: true, engine: .whisper, allowsHint: false,
            missing: nil),
        Row(
            selected: .whisper, languages: [], whisperInstalled: true, engine: .whisper, allowsHint: false, missing: nil
        ),
        // Parakeet, every language supported: Parakeet, installed or not.
        Row(
            selected: .parakeet, languages: ["pl"], whisperInstalled: false, engine: .parakeet, allowsHint: true,
            missing: nil),
        Row(
            selected: .parakeet, languages: ["pl", "en", "uk"], whisperInstalled: true, engine: .parakeet,
            allowsHint: true, missing: nil),
        Row(
            selected: .parakeet, languages: [], whisperInstalled: false, engine: .parakeet, allowsHint: true,
            missing: nil),
        // A language Parakeet cannot transcribe, Whisper installed: Whisper.
        Row(
            selected: .parakeet, languages: ["ja"], whisperInstalled: true, engine: .whisper, allowsHint: false,
            missing: nil),
        Row(
            selected: .parakeet, languages: ["pl", "ja"], whisperInstalled: true, engine: .whisper, allowsHint: false,
            missing: nil),
        // The same without Whisper: Parakeet with no hint, and the banner names the language.
        Row(
            selected: .parakeet, languages: ["ja"], whisperInstalled: false, engine: .parakeet, allowsHint: false,
            missing: "ja"),
        Row(
            selected: .parakeet, languages: ["pl", "tr", "ja"], whisperInstalled: false, engine: .parakeet,
            allowsHint: false, missing: "tr"),
        // A code outside the catalog needs no model.
        Row(
            selected: .parakeet, languages: ["xx"], whisperInstalled: false, engine: .parakeet, allowsHint: true,
            missing: nil),
    ]

    @Test(arguments: rows)
    private func theTableRow(_ row: Row) {
        let decision = SpeechEngineRouter.decide(
            selected: row.selected, languages: row.languages, whisperInstalled: row.whisperInstalled)
        #expect(decision.engine == row.engine)
        #expect(decision.allowsScriptHint == row.allowsHint)
        #expect(decision.missingWhisperLanguage == row.missing)
    }
}

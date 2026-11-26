import FluidAudio
import Foundation
import Synchronization
import Testing

@testable import LintelSpeech

@Suite struct ParakeetLanguageTests {
    @Test func settingsCodesMapToScriptHints() {
        #expect(ParakeetLanguage.hint(for: "pl") == .polish)
        #expect(ParakeetLanguage.hint(for: "en") == .english)
    }

    @Test func unknownOrMissingCodeSendsNoHint() {
        #expect(ParakeetLanguage.hint(for: nil) == nil)
        #expect(ParakeetLanguage.hint(for: "") == nil)
        #expect(ParakeetLanguage.hint(for: "xx") == nil)
    }

    @Test func onlyLatinScriptLanguagesGetAHint() {
        #expect(ParakeetLanguage.hint(for: ["pl"]) == .polish)
        #expect(ParakeetLanguage.hint(for: ["en"]) == .english)
        #expect(ParakeetLanguage.hint(for: ["en", "pl"]) != nil)
        // Not in the table (Cyrillic, Greek, unknown, "auto"): no hint.
        #expect(ParakeetLanguage.hint(for: ["uk"]) == nil)
        #expect(ParakeetLanguage.hint(for: ["ru"]) == nil)
        #expect(ParakeetLanguage.hint(for: ["el"]) == nil)
        #expect(ParakeetLanguage.hint(for: ["auto"]) == nil)
        #expect(ParakeetLanguage.hint(for: []) == nil)
        // One non-Latin or unknown language among several: no hint.
        #expect(ParakeetLanguage.hint(for: ["pl", "uk"]) == nil)
        #expect(ParakeetLanguage.hint(for: ["en", "xx"]) == nil)
    }

    @Test func everyTableEntryIsLatinOrDoesNotHint() {
        for (code, script) in ParakeetLanguage.scripts {
            #expect((ParakeetLanguage.hint(for: [code]) != nil) == (script == .latin))
        }
    }

    @Test func engineDefaultsToNoHint() async {
        // Dictation builds `ParakeetEngine()` and must keep decoding exactly as before.
        #expect(await ParakeetEngine().languageHint == nil)
    }

    @Test func engineReadsTheLanguageForEverySegment() async {
        let code = Mutex<String?>("pl")
        let engine = ParakeetEngine(language: { code.withLock { $0 } })
        #expect(await engine.languageHint == .polish)
        code.withLock { $0 = "en" }
        #expect(await engine.languageHint == .english)
    }

    /// Spec `2026-11-23-automatic-language-detection`, step 2.3: no plugin builds an engine with a language any more
    /// (the lease shares one engine between them); every request carries its own `SpeechRequestOptions`.
    @Test func noPluginBuildsAnEngineWithALanguage() throws {
        let sources = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Sources")
        for file in ["DictationPlugin/DictationPlugin.swift", "MeetingsPlugin/MeetingsRuntime.swift"] {
            let source = try String(contentsOf: sources.appending(path: file), encoding: .utf8)
            #expect(source.contains("ParakeetEngine()"), "\(file)")
            #expect(source.contains("WhisperKitEngine()"), "\(file)")
            #expect(!source.contains("ParakeetEngine(language:"), "\(file)")
            #expect(!source.contains("WhisperKitEngine(language:"), "\(file)")
        }
    }
}

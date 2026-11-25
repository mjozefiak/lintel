import FluidAudio
import Foundation
import Testing

@testable import LintelSpeech

/// Local only, off by default (step 1.6 and the measurement of the D3 brief): the real models on speech, never in
/// CI. Nothing here is written to the repository; the corpus and the results stay on the evaluation volume.
///
/// Whisper folder: `LINTEL_LANGUAGE_WHISPER_FOLDER=~/Library/Application\ Support/Lintel/Models/speech/whisper-large-v3-turbo`
/// Parakeet folder (for the corpus run): `LINTEL_DICTATION_MODEL_FOLDER=.../Models/speech/parakeet-ultra`
private enum LanguageEvalEnvironment {
    static func value(_ name: String) -> String? {
        let raw = ProcessInfo.processInfo.environment[name]
        guard let raw, !raw.isEmpty else { return nil }
        return (raw as NSString).expandingTildeInPath
    }

    static var whisperFolder: URL? {
        value("LINTEL_LANGUAGE_WHISPER_FOLDER").map { URL(filePath: $0, directoryHint: .isDirectory) }
    }
    static var parakeetFolder: URL? {
        value("LINTEL_DICTATION_MODEL_FOLDER").map { URL(filePath: $0, directoryHint: .isDirectory) }
    }
    static var audioFolder: URL? {
        value("LINTEL_LANGUAGE_EVAL_AUDIO").map { URL(filePath: $0, directoryHint: .isDirectory) }
    }
    static var outputFolder: URL? {
        value("LINTEL_LANGUAGE_EVAL_OUT").map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    /// Speech made with a system voice, as 16 kHz mono samples (invented text, no recording of a person).
    static func spoken(_ text: String, voice: String) throws -> [Float] {
        let file = FileManager.default.temporaryDirectory.appending(path: "lintel-lang-\(UUID().uuidString).aiff")
        defer { try? FileManager.default.removeItem(at: file) }
        let say = Process()
        say.executableURL = URL(filePath: "/usr/bin/say")
        say.arguments = ["-v", voice, "-o", file.path, text]
        try say.run()
        say.waitUntilExit()
        return try AudioConverter().resampleAudioFile(file)
    }
}

/// The constrained language detection on the real Whisper model: its result decides between the design and the
/// fallback of the spec (an unconstrained result when it is listed, else the first listed language).
@Suite(.enabled(if: LanguageEvalEnvironment.whisperFolder != nil))
struct RealLanguageDetectionTests {
    private static let english = "Yesterday evening we talked about how to prepare the presentation for the new client."
    private static let german =
        "Gestern Abend haben wir darüber gesprochen, wie wir die Präsentation für den neuen Kunden vorbereiten."

    @Test func detectionAmongTheListedLanguagesPicksTheSpokenOneAndNeverAnUnlistedOne() async throws {
        let folder = try #require(LanguageEvalEnvironment.whisperFolder)
        let engine = WhisperKitEngine(language: { "en" })
        try await engine.load(modelFolder: folder)
        let en = try LanguageEvalEnvironment.spoken(Self.english, voice: "Samantha")
        let de = try LanguageEvalEnvironment.spoken(Self.german, voice: "Anna")

        func detect(_ samples: [Float], _ candidates: [String], fallback: String = "pl") async throws -> String {
            try await engine.resolvedLanguage(.detect(candidates: candidates, fallback: fallback), for: samples)
        }
        let results = [
            ("en among en,de", try await detect(en, ["en", "de"])),
            ("de among en,de", try await detect(de, ["en", "de"])),
            // English speech, but English is not listed: the answer must be one of the listed languages.
            ("en among de,ja", try await detect(en, ["de", "ja"])),
            ("de among pl,en", try await detect(de, ["pl", "en"])),
        ]
        for (label, language) in results { print("DETECT", label, "->", language) }
        #expect(results[0].1 == "en")
        #expect(results[1].1 == "de")
        #expect(["de", "ja"].contains(results[2].1))
        #expect(["pl", "en"].contains(results[3].1))
        // A segment shorter than 3 s is never detected: the fallback is used.
        #expect(try await detect(Array(en.prefix(2 * AudioFormat.sampleRate)), ["en", "de"], fallback: "de") == "de")
        // One candidate needs no detection.
        #expect(try await detect(en, ["de"]) == "de")
        await engine.unload()
    }

    @Test func aDetectedLanguageIsUsedForTheDecodingAndThePinnedOneStillWorks() async throws {
        let folder = try #require(LanguageEvalEnvironment.whisperFolder)
        let engine = WhisperKitEngine(language: { "en" })
        try await engine.load(modelFolder: folder)
        let de = try LanguageEvalEnvironment.spoken(Self.german, voice: "Anna")
        let detected = try await engine.transcribe(
            de, options: SpeechRequestOptions(whisperLanguage: .detect(candidates: ["en", "de"], fallback: "en")))
        let pinned = try await engine.transcribe(de, options: SpeechRequestOptions(whisperLanguage: .pinned("de")))
        print("DETECTED-DECODE", detected.text, "| PINNED-DECODE", pinned.text)
        #expect(
            detected.text.lowercased().contains("präsentation") || detected.text.lowercased().contains("prasentation"))
        #expect(pinned.text == detected.text)
        #expect(detected.avgLogProb != nil && detected.noSpeechProb != nil)
        await engine.unload()
    }
}

/// The owner's dictation recordings through the engines, raw (no formatting), as JSON lines in the format of
/// `score_dictation.py`: `{id, app, output, latency_ms}` plus the language Whisper picked. Writes one file per setup
/// into `LINTEL_LANGUAGE_EVAL_OUT`.
///
/// `LINTEL_LANGUAGE_EVAL_AUDIO=~/DeveloperTools/lintel-market-benchmark/data/dictation/owner-voice`
@Suite(
    .enabled(
        if: LanguageEvalEnvironment.audioFolder != nil && LanguageEvalEnvironment.outputFolder != nil
            && LanguageEvalEnvironment.whisperFolder != nil && LanguageEvalEnvironment.parakeetFolder != nil))
struct OwnerCorpusEval {
    private struct Line: Encodable {
        let id: String
        let app: String
        let output: String
        let latencyMs: Int
        let language: String?

        /// The key `score_dictation.py` reads.
        enum CodingKeys: String, CodingKey {
            case id, app, output, language
            case latencyMs = "latency_ms"
        }
    }

    private func write(_ lines: [Line], app: String, to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try lines.map { try encoder.encode($0) }.map { String(decoding: $0, as: UTF8.self) }
            .joined(separator: "\n")
        try (data + "\n").write(to: folder.appending(path: "\(app).jsonl"), atomically: true, encoding: .utf8)
    }

    @Test func everyRecordingThroughEverySetup() async throws {
        let audio = try #require(LanguageEvalEnvironment.audioFolder)
        let out = try #require(LanguageEvalEnvironment.outputFolder)
        let whisperFolder = try #require(LanguageEvalEnvironment.whisperFolder)
        let parakeetFolder = try #require(LanguageEvalEnvironment.parakeetFolder)
        let files = try FileManager.default.contentsOfDirectory(at: audio, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "wav" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(!files.isEmpty)
        let converter = AudioConverter()
        let recordings = try files.map {
            ($0.deletingPathExtension().lastPathComponent, try converter.resampleAudioFile($0))
        }

        func milliseconds(_ start: ContinuousClock.Instant) -> Int {
            let parts = start.duration(to: .now).components
            return Int(parts.seconds * 1000 + parts.attoseconds / 1_000_000_000_000_000)
        }

        // Parakeet: today (no hint) and with the Latin script hint a Polish+English profile would send.
        let parakeet = ParakeetEngine()
        try await parakeet.load(modelFolder: parakeetFolder)
        for (app, options) in [
            ("lintel-parakeet-nohint", SpeechRequestOptions.none),
            ("lintel-parakeet-latin", SpeechRequestOptions(scriptHint: .latin)),
        ] {
            var lines: [Line] = []
            for (id, samples) in recordings {
                let start = ContinuousClock.now
                let segment = try await parakeet.transcribe(samples, options: options)
                lines.append(
                    Line(id: id, app: app, output: segment.text, latencyMs: milliseconds(start), language: nil))
            }
            try write(lines, app: app, to: out)
        }
        await parakeet.unload()

        // Whisper: pinned to Polish (what a pinned list gives) and detecting among Polish and English.
        let whisper = WhisperKitEngine(language: { "pl" })
        try await whisper.load(modelFolder: whisperFolder)
        for (app, choice) in [
            ("lintel-whisper-pl", WhisperLanguageChoice.pinned("pl")),
            ("lintel-whisper-auto-pl-en", WhisperLanguageChoice.detect(candidates: ["pl", "en"], fallback: "pl")),
        ] {
            var lines: [Line] = []
            for (id, samples) in recordings {
                let start = ContinuousClock.now
                let language = try await whisper.resolvedLanguage(choice, for: samples)
                let segment = try await whisper.transcribe(
                    samples, options: SpeechRequestOptions(whisperLanguage: .pinned(language)))
                lines.append(
                    Line(id: id, app: app, output: segment.text, latencyMs: milliseconds(start), language: language))
            }
            try write(lines, app: app, to: out)
        }
        await whisper.unload()
    }
}

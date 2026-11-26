import Foundation
import LintelSpeech
import Testing

@testable import MeetingsPlugin

/// The language part of the meeting evaluation, without a model: keys, the settle replay, the changed rows and the
/// additive shape of the result.
struct LanguageEvalHarnessTests {
    private func segment(_ id: Int64, _ startMs: Int, _ endMs: Int, _ text: String) -> StoredSegment {
        StoredSegment(id: id, channel: .mic, startMs: startMs, endMs: endMs, text: text)
    }

    @Test func optionsKeysAreClosedCodes() {
        #expect(LanguageEval.key(.none) == "none")
        #expect(LanguageEval.key(SpeechRequestOptions(scriptHint: .latin)) == "script:latin")
        #expect(LanguageEval.key(SpeechRequestOptions(scriptHint: .cyrillic)) == "script:cyrillic")
        #expect(LanguageEval.key(SpeechRequestOptions(whisperLanguage: .pinned("pl"))) == "whisper:pinned:pl")
        #expect(
            LanguageEval.key(SpeechRequestOptions(whisperLanguage: .detect(candidates: ["pl", "en"], fallback: "pl")))
                == "whisper:detect")
        let both = SpeechRequestOptions(scriptHint: .latin, whisperLanguage: .pinned("en"))
        #expect(LanguageEval.key(both) == "script:latin+whisper:pinned:en")
        // Only the half the engine reads.
        #expect(LanguageEval.key(both, whisper: false) == "script:latin")
        #expect(LanguageEval.key(both, whisper: true) == "whisper:pinned:en")
        #expect(LanguageEval.key(SpeechRequestOptions(whisperLanguage: .pinned("pl")), whisper: false) == "none")
    }

    @Test func theTallyFilesRequestsUnderThePhase() async throws {
        let tally = RequestTally()
        let engine = CountingEngine(base: SilentEngine(), tally: tally, isWhisper: false)
        _ = try await engine.transcribe([0], options: SpeechRequestOptions(scriptHint: .latin))
        _ = try await engine.transcribe([0], options: .none)
        _ = try await engine.transcribe([0])
        tally.enterRepair()
        _ = try await engine.transcribe([0], options: SpeechRequestOptions(scriptHint: .latin))
        #expect(tally.counts(.live) == ["script:latin": 1, "none": 2])
        #expect(tally.counts(.repair) == ["script:latin": 1])
    }

    @Test func theProfileSettlesAtTheEndOfTheSegmentThatCrossesThirtySeconds() {
        let long = "jeden dwa trzy cztery pięć sześć siedem osiem dziewięć dziesięć"
        let english = "one two three four five six seven eight nine ten"
        let identifier = TableIdentifier([
            long: LanguageGuess(code: "pl", confidence: 0.95),
            english: LanguageGuess(code: "en", confidence: 0.9),
            "tak": LanguageGuess(code: "sk", confidence: 0.99),
        ])
        // Out of order on purpose: the replay sorts by start, as the segments were sent.
        let segments = [
            segment(3, 24_000, 36_000, long),
            segment(1, 0, 12_000, long),
            segment(2, 12_000, 13_000, "tak"),
            segment(4, 40_000, 50_000, english),
        ]
        let result = LanguageEval.settle(segments, identifier: identifier, hints: ["pl", "en"])
        // 12 s, then a short one that never counts, then 12 s more (24 s), then 10 s of English (34 s).
        #expect(result.settledAtMs == 50_000)
        #expect(result.profile.confidentSeconds == 34)
        #expect(abs((result.profile.shares["pl"] ?? 0) - 24.0 / 34.0) < 1e-9)
        #expect(result.profile.shares["sk"] == nil)

        let never = LanguageEval.settle(Array(segments.prefix(2)), identifier: identifier, hints: ["pl"])
        #expect(never.settledAtMs == nil)
    }

    @Test func changedIDsAreTheRowsWhoseTextDiffers() {
        let before = [segment(1, 0, 1_000, "a"), segment(2, 1_000, 2_000, "b"), segment(3, 2_000, 3_000, "c")]
        let after = [segment(1, 0, 1_000, "a"), segment(2, 1_000, 2_000, "B"), segment(4, 3_000, 4_000, "d")]
        #expect(LanguageEval.changedIDs(before: before, after: after) == [2])
    }

    @Test func theBlockCarriesTheRepairCounts() {
        let tally = RequestTally()
        tally.record("none")
        tally.enterRepair()
        tally.record("whisper:pinned:pl")
        var report = LanguageRepairReport()
        report.suspect = 7
        report.replaced = 2
        report.keep(.noSpeech)
        report.keep(.noSpeech)
        report.keep(.outsideProfile)
        report.stop = .timeLimit
        let run = LanguageEval.RepairRun(
            engine: "whisper-large-v3-turbo", report: report, seconds: 12.5, beforeReadySeconds: 12.75,
            peakFootprintMB: 900, before: [], changed: [5, 6])
        let block = LanguageEval.block(
            settle: (settledAtMs: 31_000, profile: LanguageProfile()), languages: ["pl", "en"], tally: tally,
            repair: run)
        #expect(block.requests == ["none": 1])
        let repair = try? #require(block.repair)
        #expect(repair?.redecoded == 5)
        #expect(repair?.keptReasons == ["noSpeech": 2, "outsideProfile": 1])
        #expect(repair?.skipped == 2)
        #expect(repair?.stop == "timeLimit")
        #expect(repair?.requests == ["whisper:pinned:pl": 1])
        #expect(repair?.changedSegments == 2)
        #expect(
            LanguageEval.block(
                settle: (settledAtMs: nil, profile: LanguageProfile()), languages: ["pl"], tally: tally, repair: nil
            ).repair == nil)
    }

    private func result(language: EvalResult.Language?, repaired: Bool?) -> EvalResult {
        var value = EvalResult(
            recording: "demo", audioSeconds: 60,
            config: .init(
                engine: "parakeet-ultra", language: "auto", codeVersion: "abc", languages: ["pl", "en"]),
            asr: .init(
                processingSeconds: 5, rtf: 0.1, peakFootprintMB: 800, deferredSegments: 0,
                segments: [.init(track: "mic", startMs: 0, endMs: 900, text: "t", repaired: repaired)]))
        value.language = language
        return value
    }

    private let block = EvalResult.Language(
        languages: ["pl", "en"], profileSettledAtMs: 42_000, profileConfidentSeconds: 120.5,
        shares: ["pl": 0.9, "en": 0.1], requests: ["none": 4, "script:latin": 40],
        repair: .init(
            engine: "whisper-large-v3-turbo", suspect: 9, redecoded: 8, replaced: 3, kept: 5,
            keptReasons: ["noSpeech": 4, "same": 1], skipped: 1, stop: "none", seconds: 20.5,
            beforeReadySeconds: 21, peakFootprintMB: 1_500, requests: ["whisper:pinned:pl": 8], changedSegments: 3))

    @Test func theLanguageBlockAndTheRowFlagRoundTripAndAreNumbersOnly() throws {
        let value = result(language: block, repaired: true)
        let data = try EvalResultWriter.data(for: value)
        #expect(try JSONDecoder().decode(EvalResult.self, from: data) == value)

        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let language = try #require(object["language"] as? [String: Any])
        #expect(
            Set(language.keys) == [
                "languages", "profileSettledAtMs", "profileConfidentSeconds", "shares", "requests", "repair",
            ])
        let repair = try #require(language["repair"] as? [String: Any])
        #expect(
            Set(repair.keys) == [
                "engine", "suspect", "redecoded", "replaced", "kept", "keptReasons", "skipped", "stop", "seconds",
                "beforeReadySeconds", "peakFootprintMB", "requests", "changedSegments",
            ])
        let asr = try #require(object["asr"] as? [String: Any])
        let row = try #require((asr["segments"] as? [[String: Any]])?.first)
        #expect(row["repaired"] as? Bool == true)
        let config = try #require(object["config"] as? [String: Any])
        #expect(config["languages"] as? [String] == ["pl", "en"])
    }

    @Test func aResultWithoutTheBlockKeepsTheOldShape() throws {
        let value = result(language: nil, repaired: nil)
        let data = try EvalResultWriter.data(for: value)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["language"] == nil)
        let asr = try #require(object["asr"] as? [String: Any])
        let row = try #require((asr["segments"] as? [[String: Any]])?.first)
        #expect(Set(row.keys) == ["track", "startMs", "endMs", "text"])
        // An older file (no block, no flag) still decodes.
        let old = """
            {"schema":1,"recording":"r","audioSeconds":1,"config":{"engine":"e","language":"pl","codeVersion":"v"},
             "asr":{"processingSeconds":1,"rtf":1,"peakFootprintMB":1,"deferredSegments":0,
                    "segments":[{"track":"mic","startMs":1,"endMs":2,"text":"t"}]},"diarization":null,"notes":null}
            """
        let decoded = try JSONDecoder().decode(EvalResult.self, from: Data(old.utf8))
        #expect(decoded.language == nil)
        #expect(decoded.asr.segments.first?.repaired == nil)
        #expect(decoded.config.languages == nil)
    }

    @Test func aRunWithoutTheRepairWritesANullRepair() throws {
        var plain = block
        plain.repair = nil
        plain.profileSettledAtMs = nil
        let data = try EvalResultWriter.data(for: result(language: plain, repaired: nil))
        let decoded = try JSONDecoder().decode(EvalResult.self, from: data)
        #expect(decoded.language?.repair == nil)
        #expect(decoded.language?.profileSettledAtMs == nil)
    }
}

/// An engine that answers every request with an empty transcript.
private struct SilentEngine: SpeechEngine {
    var isLoaded: Bool { get async { true } }
    func load(modelFolder: URL) async throws {}
    func transcribe(_ samples: [Float]) async throws -> TranscriptSegment { TranscriptSegment(text: "") }
    func transcribe(_ samples: [Float], options _: SpeechRequestOptions) async throws -> TranscriptSegment {
        TranscriptSegment(text: "")
    }
    func unload() async {}
}

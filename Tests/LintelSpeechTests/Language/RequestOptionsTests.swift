import CoreML
import FluidAudio
import Foundation
import Testing
import WhisperKit

@testable import LintelSpeech

private let folder = URL(filePath: "/models/speech/shared")

@Suite struct SpeechRequestOptionsTests {
    @Test func noOptionsMeansNoHintAndNoLanguage() {
        #expect(SpeechRequestOptions.none == SpeechRequestOptions())
        #expect(SpeechRequestOptions.none.scriptHint == nil)
        #expect(SpeechRequestOptions.none.whisperLanguage == nil)
    }

    @Test func anEngineThatKnowsNothingAboutOptionsIgnoresThem() async throws {
        // `FakeEngine` only implements `transcribe(_:)`; the protocol extension's default calls it.
        let engine = FakeEngine()
        let segment = try await engine.transcribe(
            [0.07], options: SpeechRequestOptions(scriptHint: .cyrillic, whisperLanguage: .pinned("uk")))
        #expect(segment.text == "segment 7")
    }

    /// The shared-engine case: Dictation and Meetings lease the same model, so the engine is one object and the
    /// options must belong to the request.
    @Test func twoLeasesOnOneKeyEachGetTheirOwnOptions() async throws {
        let lease = SpeechEngineLease()
        let engine = OptionsEngine()
        let meeting = try await lease.acquire(
            modelID: "parakeet", folder: folder, engine: engine, priority: .background, keepWarm: { .seconds(60) })
        // The second caller's engine is ignored: the first one is shared.
        let otherEngine = OptionsEngine()
        let dictation = try await lease.acquire(
            modelID: "parakeet", folder: folder, engine: otherEngine, priority: .interactive, keepWarm: { .seconds(60) }
        )

        let latin = SpeechRequestOptions(scriptHint: .latin)
        let cyrillic = SpeechRequestOptions(scriptHint: .cyrillic)
        #expect(try await meeting.transcribe([1], options: latin) == .transcript(TranscriptSegment(text: "options 1")))
        #expect(
            try await dictation.transcribe([2], options: cyrillic) == .transcript(TranscriptSegment(text: "options 2")))
        #expect(try await dictation.transcribe([3]) == .transcript(TranscriptSegment(text: "options 3")))
        #expect(try await meeting.transcribe([4], options: latin) == .transcript(TranscriptSegment(text: "options 4")))

        #expect(engine.received.withLock { $0 } == [latin, cyrillic, .none, latin])
        #expect(otherEngine.received.withLock { $0 }.isEmpty)
        await meeting.release()
        await dictation.release()
    }

    @Test func aSingleLeaseCarriesTheOptionsOfEachCallToTheEngine() async throws {
        let lease = SpeechEngineLease()
        let engine = OptionsEngine()
        let handle = try await lease.acquire(
            modelID: "parakeet", folder: folder, engine: engine, priority: .interactive, keepWarm: { .seconds(1) })
        _ = try await handle.transcribe([5], options: SpeechRequestOptions(scriptHint: .greek))
        #expect(engine.received.withLock { $0 } == [SpeechRequestOptions(scriptHint: .greek)])
        await handle.release()
    }

    @Test func theSwitchingEngineForwardsTheOptionsOfTheRequest() async throws {
        let chosen = OptionsEngine()
        let engine = SwitchingEngine(engines: ["a": chosen, "b": OptionsEngine()], selected: { "a" })
        try await engine.load(modelFolder: folder)
        let options = SpeechRequestOptions(whisperLanguage: .detect(candidates: ["pl", "en"], fallback: "pl"))
        #expect(try await engine.transcribe([9], options: options).text == "options 9")
        #expect(chosen.received.withLock { $0 } == [options])
    }
}

@Suite struct EngineOptionsTests {
    @Test func parakeetUsesTheRequestsHintElseItsDefault() {
        #expect(ParakeetEngine.hint(for: .none, default: nil) == nil)
        #expect(ParakeetEngine.hint(for: .none, default: .polish) == .polish)
        #expect(
            ParakeetEngine.hint(for: SpeechRequestOptions(scriptHint: .cyrillic), default: nil)?.script == .cyrillic)
        #expect(ParakeetEngine.hint(for: SpeechRequestOptions(scriptHint: .greek), default: .polish)?.script == .greek)
        #expect(ParakeetEngine.hint(for: SpeechRequestOptions(scriptHint: .latin), default: nil)?.script == .latin)
    }

    @Test func parakeetWithoutOptionsKeepsToday() async {
        #expect(await ParakeetEngine().languageHint == nil)
        #expect(await ParakeetEngine(language: { "pl" }).languageHint == .polish)
    }

    /// `.pinned` builds today's decoding options, byte for byte.
    @Test func aPinnedLanguageBuildsTheDecodingOptionsOfBefore() {
        let options = WhisperKitEngine.decodingOptions(language: "pl")
        #expect(options.task == .transcribe)
        #expect(options.language == "pl")
        #expect(options.temperature == 0)
        #expect(options.usePrefillPrompt)
        #expect(!options.detectLanguage)
        #expect(options.skipSpecialTokens)
        #expect(options.withoutTimestamps)
        #expect(!options.wordTimestamps)
        let reference = DecodingOptions(
            task: .transcribe, language: "pl", temperature: 0, usePrefillPrompt: true, detectLanguage: false,
            skipSpecialTokens: true, withoutTimestamps: true, wordTimestamps: false)
        #expect(String(describing: options) == String(describing: reference))
    }

    @Test func whisperNeverTranslates() {
        for code in ["pl", "en", "uk", "ja"] {
            #expect(WhisperKitEngine.decodingOptions(language: code).task == .transcribe)
        }
    }

    @Test func detectionIsNeverRunOnAShortSegment() {
        #expect(WhisperKitEngine.minimumDetectionSeconds == 3)
        #expect(WhisperKitEngine.minimumDetectionSeconds == Int(LanguageProfile.minimumDuration))
    }
}

@Suite struct ConstrainedLanguageDetectionTests {
    @Test func theBestListedLanguageWinsAndAnUnlistedOneIsNeverASource() {
        // "ja" is not offered, so its huge logit does not exist for the chooser.
        let choice = ConstrainedLanguagePick.choose([("pl", 1.0), ("en", 4.0), ("uk", 2.0)])
        #expect(choice?.code == "en")
        let expected = 1 / (1 + exp(Float(1.0 - 4.0)) + exp(Float(2.0 - 4.0)))
        #expect(abs((choice?.probability ?? 0) - expected) < 1e-6)
    }

    @Test func aTieGoesToTheFirstCandidateAndNothingGivesNothing() {
        #expect(ConstrainedLanguagePick.choose([("pl", 2), ("en", 2)])?.code == "pl")
        #expect(ConstrainedLanguagePick.choose([]) == nil)
        #expect(ConstrainedLanguagePick.choose([("pl", -.infinity), ("en", .nan)]) == nil)
        #expect(ConstrainedLanguagePick.choose([("pl", -.infinity), ("en", -3)])?.code == "en")
    }

    private func logits(_ values: [Int: Float], size: Int = 12) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [1, 1, NSNumber(value: size)], dataType: .float32)
        for index in 0..<size { array[[0, 0, NSNumber(value: index)]] = NSNumber(value: values[index] ?? -20) }
        return array
    }

    /// Tokens 3 (pl), 5 (en), 7 (uk) are the candidates; token 8 is a language token that is not listed.
    @Test func theSamplerPicksTheBestCandidateAndIgnoresAHigherUnlistedLanguage() async throws {
        let sampler = CandidateLanguageSampler(candidates: [("pl", 3), ("en", 5), ("uk", 7)])
        let result = await sampler.update(
            tokens: [50258], logits: try logits([3: 1.0, 5: 2.0, 7: 0.5, 8: 9.0]), logProbs: [0])
        #expect(result.tokens == [50258, 5])
        #expect(result.completed)
        #expect(sampler.choice?.code == "en")
        #expect(result.logProbs.count == 2)
        #expect((result.logProbs.last ?? 0) < 0)
    }

    @Test func theSamplerRemembersNothingWhenNoCandidateHasARealLogit() async throws {
        let sampler = CandidateLanguageSampler(candidates: [("pl", 3), ("en", 5)])
        let values: [Int: Float] = [3: -.infinity, 5: -.infinity]
        let result = await sampler.update(tokens: [50258], logits: try logits(values), logProbs: [0])
        #expect(result.tokens == [50258])
        #expect(sampler.choice == nil)
    }
}

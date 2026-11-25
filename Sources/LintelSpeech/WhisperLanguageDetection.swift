import CoreML
import Foundation
import Synchronization
import WhisperKit

/// Picks the language of a segment among the user's languages only (spec: "Meetings and Dictation, Whisper").
///
/// WhisperKit's own `detectLangauge(audioArray:)` returns the single best of all ~100 languages, so a Polish
/// speaker with Czech-sounding vowels may come out as Czech although Czech is not in the list. This runs the same
/// three calls (mel, encoder, decoder's language step) with a sampler that looks at the listed languages' tokens
/// only.
enum ConstrainedLanguagePick {
    struct Choice: Equatable {
        let code: String
        /// Softmax over the candidates only, 0...1.
        let probability: Float
    }

    /// The candidate with the highest logit, with its probability among the candidates. A tie goes to the
    /// first candidate (the list is ordered by what the user speaks most). `nil` for no candidate or no real number.
    static func choose(_ logits: [(code: String, logit: Float)]) -> Choice? {
        guard
            let best = logits.enumerated().filter({ $0.element.logit.isFinite }).max(by: {
                $0.element.logit < $1.element.logit || ($0.element.logit == $1.element.logit && $0.offset > $1.offset)
            })
        else { return nil }
        let top = best.element.logit
        let sum = logits.filter(\.logit.isFinite).reduce(Float(0)) { $0 + exp($1.logit - top) }
        return Choice(code: best.element.code, probability: 1 / sum)
    }
}

/// A `TokenSampling` for the decoder's language step: of all the language tokens it picks the highest logit among
/// the listed ones. The decoder filters the other tokens out already (`LanguageLogitsFilter`); this narrows the
/// rest to the candidates, and remembers what it chose.
final class CandidateLanguageSampler: TokenSampling, Sendable {
    /// Language code per token id of the candidates, in the user's order.
    private let candidates: [(code: String, token: Int)]
    private let chosen = Mutex<ConstrainedLanguagePick.Choice?>(nil)

    init(candidates: [(code: String, token: Int)]) {
        self.candidates = candidates
    }

    var choice: ConstrainedLanguagePick.Choice? { chosen.withLock { $0 } }

    func update(tokens: [Int], logits: MLMultiArray, logProbs: [Float]) async -> SamplingResult {
        let size = logits.shape.count == 3 ? logits.shape[2].intValue : 0
        let scored = candidates.filter { $0.token < size }.map { candidate in
            (code: candidate.code, logit: logits[[0, 0, NSNumber(value: candidate.token)]].floatValue)
        }
        guard let pick = ConstrainedLanguagePick.choose(scored),
            let token = candidates.first(where: { $0.code == pick.code })?.token
        else {
            return SamplingResult(tokens: tokens, logProbs: logProbs, completed: true)
        }
        chosen.withLock { $0 = pick }
        return SamplingResult(
            tokens: tokens + [token], logProbs: logProbs + [log(max(pick.probability, .leastNonzeroMagnitude))],
            completed: true)
    }

    func finalize(tokens: [Int], logProbs: [Float]) -> SamplingResult {
        SamplingResult(tokens: tokens, logProbs: logProbs, completed: true)
    }
}

extension WhisperKitEngine {
    /// Detection looks at one 30 s window; a shorter segment is padded with silence and Whisper guesses badly on it,
    /// so a segment below this length is never detected (the fallback is used).
    public static let minimumDetectionSeconds = 3

    /// The language of `samples` among `candidates`, or `fallback` when there is one candidate to choose from, the
    /// audio is too short, the model has no token for a candidate, or anything fails. Never throws: a detection
    /// that fails must not fail the transcription.
    func detectLanguage(
        _ samples: [Float], among candidates: [String], fallback: String, kit: WhisperKit
    ) async -> String {
        let listed = candidates.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        if listed.count == 1, let only = listed.first { return only }
        guard listed.count > 1, samples.count >= Self.minimumDetectionSeconds * AudioFormat.sampleRate,
            let tokenizer = kit.tokenizer, kit.textDecoder.isModelMultilingual
        else { return fallback }
        let tokens = listed.compactMap { code in
            tokenizer.convertTokenToId("<|\(code)|>").map { (code: code, token: $0) }
        }
        guard tokens.count > 1 else { return tokens.first?.code ?? fallback }
        do {
            guard
                let window = kit.audioProcessor.padOrTrim(
                    fromArray: samples, startAt: 0,
                    toLength: kit.featureExtractor.windowSamples ?? Constants.defaultWindowSamples),
                let mel = try await kit.featureExtractor.logMelSpectrogram(fromAudio: window),
                let encoded = try await kit.audioEncoder.encodeFeatures(mel)
            else { return fallback }
            let inputs = try kit.textDecoder.prepareDecoderInputs(
                withPrompt: [tokenizer.specialTokens.startOfTranscriptToken])
            let sampler = CandidateLanguageSampler(candidates: tokens)
            _ = try await kit.textDecoder.detectLanguage(
                from: encoded, using: inputs, sampler: sampler, options: DecodingOptions(), temperature: 0)
            return sampler.choice?.code ?? fallback
        } catch {
            return fallback
        }
    }
}

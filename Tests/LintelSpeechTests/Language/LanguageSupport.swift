import Foundation
import Synchronization

@testable import LintelSpeech

/// Answers from a table keyed by the exact text; no answer means "says nothing".
struct FakeIdentifier: TextLanguageIdentifier {
    var answers: [String: LanguageGuess] = [:]

    func identify(_ text: String, hints: [String], constraints: [String]?) -> LanguageGuess? {
        answers[text]
    }
}

/// `count` placeholder words, so a test controls the word count without writing real sentences.
func words(_ count: Int, _ tag: String = "slowo") -> String {
    (1...count).map { "\(tag)\($0)" }.joined(separator: " ")
}

/// A profile of confident speech: seconds per language code.
func confidentProfile(_ spoken: KeyValuePairs<String, TimeInterval>) -> LanguageProfile {
    var profile = LanguageProfile()
    for (code, seconds) in spoken {
        profile.add(LanguageGuess(code: code, confidence: 0.95), duration: seconds)
    }
    return profile
}

/// An engine that answers with the options of the call, so a test sees what each request carried.
final class OptionsEngine: SpeechEngine, @unchecked Sendable {
    let received = Mutex<[SpeechRequestOptions]>([])
    private let loaded = Mutex(false)

    var isLoaded: Bool { loaded.withLock { $0 } }
    func load(modelFolder: URL) async throws { loaded.withLock { $0 = true } }
    func unload() async { loaded.withLock { $0 = false } }

    func transcribe(_ samples: [Float]) async throws -> TranscriptSegment {
        received.withLock { $0.append(.none) }
        return TranscriptSegment(text: "plain \(Int(samples.first ?? 0))")
    }

    func transcribe(_ samples: [Float], options: SpeechRequestOptions) async throws -> TranscriptSegment {
        received.withLock { $0.append(options) }
        return TranscriptSegment(text: "options \(Int(samples.first ?? 0))")
    }
}

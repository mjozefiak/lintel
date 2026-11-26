import Foundation
import LintelKit
import LintelSpeech
import Synchronization
import Testing

@testable import MeetingsPlugin

/// Answers from a table keyed by the exact text and records the hints and constraints of every call.
final class TableIdentifier: TextLanguageIdentifier {
    private let answers: [String: LanguageGuess]
    let calls = Mutex<[(hints: [String], constraints: [String]?)]>([])

    init(_ answers: [String: LanguageGuess]) { self.answers = answers }

    func identify(_ text: String, hints: [String], constraints: [String]?) -> LanguageGuess? {
        calls.withLock { $0.append((hints, constraints)) }
        return answers[text]
    }
}

/// A shared language setting a test can change while a meeting runs.
final class ChangingSpeechLanguages: SpeechLanguageSettings {
    private let selection: Mutex<SpeechLanguageSelection>

    init(_ languages: [String], mode: SpeechLanguageSelection.Mode = .automatic) {
        selection = Mutex(SpeechLanguageSelection(mode: mode, languages: languages, isDerived: false))
    }

    func current() -> SpeechLanguageSelection { selection.withLock { $0 } }
    func update(_ selection: SpeechLanguageSelection) { self.selection.withLock { $0 = selection } }
    var changes: AsyncStream<Void> { AsyncStream { $0.finish() } }
}

/// Invented placeholder words, never real speech: `count` words tagged with the utterance's code.
private func placeholder(_ code: Int, words: Int = 12) -> String {
    (1...words).map { "u\(code)w\($0)" }.joined(separator: " ")
}

private func confident(_ code: String) -> LanguageGuess { LanguageGuess(code: code, confidence: 0.95) }

private func profile(_ spoken: KeyValuePairs<String, TimeInterval>) -> LanguageProfile {
    var profile = LanguageProfile()
    for (code, seconds) in spoken { profile.add(confident(code), duration: seconds) }
    return profile
}

private let automatic = SpeechLanguageSelection(mode: .automatic, languages: ["pl", "en"], isDerived: false)

/// Spec `2026-11-23-automatic-language-detection`, step 2.3: the options every meeting segment is sent with.
@Suite struct MeetingLanguageOptionsTests {
    @Test func automaticSendsNoHintBeforeTheProfileIsSettled() {
        let unsettled = profile(["pl": LanguageProfile.settleSeconds - 1])
        #expect(!unsettled.isSettled)
        #expect(
            MeetingLanguage.options(for: automatic, profile: unsettled)
                == SpeechRequestOptions(scriptHint: nil, whisperLanguage: .pinned("pl")))
        #expect(MeetingLanguage.options(for: automatic, profile: LanguageProfile()).scriptHint == nil)
    }

    @Test func aSettledLatinProfileSendsTheLatinHint() {
        let settled = profile(["pl": 25, "en": 10])
        #expect(MeetingLanguage.options(for: automatic, profile: settled).scriptHint == .latin)
    }

    /// #210: a Ukrainian meeting is never forced into Latin letters, even with a Polish and English list.
    @Test func aCyrillicDominantProfileSendsTheCyrillicHint() {
        // Polish below the 15% share does not count for the script.
        let settled = profile(["uk": 40, "pl": 5])
        #expect(MeetingLanguage.options(for: automatic, profile: settled).scriptHint == .cyrillic)
        #expect(MeetingLanguage.options(for: automatic, profile: profile(["el": 31])).scriptHint == .greek)
    }

    @Test func aProfileOfMixedScriptsSendsNoHint() {
        let mixed = profile(["pl": 20, "uk": 20])
        #expect(mixed.isSettled)
        #expect(MeetingLanguage.options(for: automatic, profile: mixed).scriptHint == nil)
    }

    /// Automatic Whisper detection comes with step 2.5: until then Whisper is pinned to the first listed language.
    @Test func automaticPinsWhisperToTheFirstListedLanguage() {
        let list = SpeechLanguageSelection(mode: .automatic, languages: ["uk", "pl"], isDerived: false)
        #expect(MeetingLanguage.options(for: list, profile: profile(["pl": 60])).whisperLanguage == .pinned("uk"))
        let empty = SpeechLanguageSelection(mode: .automatic, languages: [], isDerived: true)
        #expect(MeetingLanguage.options(for: empty, profile: LanguageProfile()).whisperLanguage == .pinned("en"))
    }

    /// Always one language: Whisper pinned to it, Parakeet the hint of that language's script only, whatever the
    /// profile says.
    @Test(
        arguments: [
            ("pl", ScriptHint.latin), ("uk", .cyrillic), ("el", .greek), ("ja", nil), ("sr", nil),
        ] as [(String, ScriptHint?)])
    func singleModeUsesOnlyThatLanguage(_ code: String, _ hint: ScriptHint?) {
        let single = SpeechLanguageSelection(mode: .single(code), languages: ["pl", "en"], isDerived: false)
        for spoken in [LanguageProfile(), profile(["pl": 20, "uk": 20]), profile(["en": 60])] {
            #expect(
                MeetingLanguage.options(for: single, profile: spoken)
                    == SpeechRequestOptions(scriptHint: hint, whisperLanguage: .pinned(code)))
        }
    }

    @Test func onlyLongSegmentsAreIdentifiedWithTheListAsHintsAndTheCatalogAsTheConstraint() {
        let long = placeholder(1)
        let identifier = TableIdentifier([long: confident("uk"), placeholder(2, words: 9): confident("uk")])
        let language = MeetingLanguage(settings: ChangingSpeechLanguages(["pl", "en"]), identifier: identifier)
        language.observe(placeholder(2, words: 9), duration: 12)  // too few words
        language.observe(long, duration: 2.9)  // too short
        #expect(identifier.calls.withLock { $0.count } == 0)
        language.observe(long, duration: 12)
        let calls = identifier.calls.withLock { $0 }
        #expect(calls.count == 1)
        #expect(calls.first?.hints == ["pl", "en"])
        // Not the list: a Polish and English list must not turn Ukrainian speech into Polish (#210).
        #expect(calls.first?.constraints == nil)
        #expect(language.snapshot.seconds == ["uk": 12])
    }

    @Test func anUnsureGuessDoesNotCount() {
        let text = placeholder(1)
        let language = MeetingLanguage(
            settings: ChangingSpeechLanguages(["pl"]),
            identifier: TableIdentifier([text: LanguageGuess(code: "pl", confidence: 0.5)]))
        language.observe(text, duration: 14)
        #expect(language.snapshot.confidentSeconds == 0)
    }

    /// Rollback and upgrade (spec Data Model): a `plugins.meetings.speechLanguage` an older build wrote after the
    /// migration is never read; the shared list decides.
    @MainActor
    @Test func aStoredOldLanguageKeyIsNotRead() throws {
        let harness = try MeetingsHarness(
            settings: ["plugins.meetings.speechLanguage": .string("en")],
            speechLanguages: FixedSpeechLanguageSettings(.automatic, ["pl"]))
        let runtime = MeetingsRuntime(context: harness.context, settings: harness.meetingsSettings)
        #expect(runtime.makeLanguage().options().whisperLanguage == .pinned("pl"))
        #expect(runtime.makeLanguage().options().scriptHint == nil)
    }
}

/// A scripted meeting (fake engine and identifier): what each segment was really sent with.
@Suite(.serialized) struct MeetingLanguageSessionTests {
    /// Runs a microphone-only meeting of 12-second utterances and returns the options per utterance, in order.
    private func run(
        _ codes: [Int], identified: [Int: String], settings: any SpeechLanguageSettings
    ) async throws -> [SpeechRequestOptions] {
        var texts: [Int: String] = [:]
        var answers: [String: LanguageGuess] = [:]
        for code in codes {
            texts[code] = placeholder(code)
            if let language = identified[code] { answers[placeholder(code)] = confident(language) }
        }
        let rig = try SessionRig(texts: texts)
        let identifier = TableIdentifier(answers)
        var mic = TrackScript()
        for code in codes {
            mic.silence(1)
            mic.say(code, seconds: 12)
        }
        mic.silence(2)
        let session = rig.session(
            mic: mic, system: nil, withSystem: false,
            language: MeetingLanguage(settings: settings, identifier: identifier))
        _ = try await session.start()
        rig.mic.push(mic.samples)
        rig.mic.end()
        let outcome = await session.finish()
        #expect(outcome.result == .ready)
        let sent = rig.engine.options
        #expect(sent.map(\.code) == codes)
        return sent.map(\.options)
    }

    @Test func noHintBeforeTheProfileSettlesThenTheLatinScript() async throws {
        // 12 s each: the profile has 24 s after two segments, 36 s (settled) after three.
        let sent = try await run(
            [11, 12, 13, 14, 15], identified: [11: "pl", 12: "pl", 13: "en", 14: "pl", 15: "pl"],
            settings: ChangingSpeechLanguages(["pl", "en"]))
        #expect(sent.map(\.scriptHint) == [nil, nil, nil, .latin, .latin])
        #expect(sent.allSatisfy { $0.whisperLanguage == .pinned("pl") })
    }

    @Test func aCyrillicMeetingGetsTheCyrillicHint() async throws {
        let sent = try await run(
            [21, 22, 23, 24], identified: [21: "uk", 22: "uk", 23: "uk", 24: "uk"],
            settings: ChangingSpeechLanguages(["pl", "en"]))
        #expect(sent.map(\.scriptHint) == [nil, nil, nil, .cyrillic])
    }

    @Test func aMeetingInTwoScriptsGetsNoHint() async throws {
        let sent = try await run(
            [31, 32, 33, 34, 35], identified: [31: "pl", 32: "uk", 33: "pl", 34: "uk", 35: "pl"],
            settings: ChangingSpeechLanguages(["pl", "uk"]))
        #expect(sent.allSatisfy { $0.scriptHint == nil })
    }

    @Test func unidentifiedSpeechNeverSettlesTheProfile() async throws {
        let sent = try await run([41, 42, 43, 44], identified: [:], settings: ChangingSpeechLanguages(["pl"]))
        #expect(sent.allSatisfy { $0.scriptHint == nil })
    }

    @Test func singleModeSendsThatLanguageFromTheFirstSegment() async throws {
        let sent = try await run(
            [51, 52, 53, 54], identified: [51: "pl", 52: "pl", 53: "pl", 54: "pl"],
            settings: ChangingSpeechLanguages(["pl", "uk"], mode: .single("uk")))
        #expect(sent.allSatisfy { $0 == SpeechRequestOptions(scriptHint: .cyrillic, whisperLanguage: .pinned("uk")) })
    }
}

import AppKit
import Foundation
import LintelKit
import LintelSpeech
import Synchronization
import Testing

@testable import MeetingsPlugin

/// A shared language setting whose `changes` really yield, like the host's (a new stream per read).
private final class StreamingSpeechLanguages: SpeechLanguageSettings {
    private let selection: Mutex<SpeechLanguageSelection>
    private let continuations = Mutex<[AsyncStream<Void>.Continuation]>([])

    init(_ languages: [String]) {
        selection = Mutex(SpeechLanguageSelection(mode: .automatic, languages: languages, isDerived: false))
    }

    func current() -> SpeechLanguageSelection { selection.withLock { $0 } }

    func update(_ selection: SpeechLanguageSelection) {
        self.selection.withLock { $0 = selection }
        for continuation in continuations.withLock({ $0 }) { continuation.yield() }
    }

    var changes: AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        continuations.withLock { $0.append(continuation) }
        return stream
    }
}

/// Spec `2026-11-23-automatic-language-detection`, step 2.5, Banner: a language in play that needs Whisper while
/// Whisper is missing and the standard model is chosen is one thing to do, with "Get It in Models".
@MainActor
@Suite struct MeetingsWhisperBannerTests {
    private func status(
        location: ModelLocation = .installed(URL(filePath: "/tmp/model")),
        microphone: MicrophoneAccess = .granted,
        usesWhisperInstead: Bool = false,
        missing: String? = "ja",
        locale: Locale = Locale(identifier: "en")
    ) -> SettingsStatus? {
        MeetingsPlugin.settingsStatus(
            location: location, microphone: microphone, library: .ready,
            modelTitle: usesWhisperInstead ? "Whisper large-v3-turbo" : "Parakeet Ultra",
            packageID: ModelCatalog.parakeetUltra.id, usesWhisperInstead: usesWhisperInstead,
            missingWhisperLanguage: missing, locale: locale, allowMicrophone: {}, retryLibrary: {})
    }

    @Test func aMissingWhisperIsOneThingToDoWithGetItInModels() throws {
        let banner = try #require(status())
        #expect(banner.level == .attention)
        #expect(banner.title.key == "1 thing to do")
        #expect(banner.detail?.key == "Get Whisper to transcribe %@")
        #expect(String(localized: try #require(banner.detail)).hasSuffix("Japanese"))
        #expect(banner.fix.map(\.title.key) == ["Get It in Models"])
        guard case .models(let packageID) = banner.fix.first?.destination else {
            Issue.record("not a Models action")
            return
        }
        #expect(packageID == ModelCatalog.whisperLargeV3Turbo.id)
    }

    /// The language is named in the reader's language.
    @Test func theLanguageNameFollowsTheLocale() throws {
        let polish = try #require(status(locale: Locale(identifier: "pl")))
        let detail = try #require(polish.detail)
        var resource = detail
        resource.locale = Locale(identifier: "pl")
        #expect(String(localized: resource).contains("japoński"))
    }

    /// Something before it in the list is shown first; Whisper is still counted in the title.
    @Test func itIsCountedBehindTheMicrophoneAndTheSpeechModel() throws {
        let microphone = try #require(status(microphone: .notDetermined))
        #expect(microphone.title.key == "2 things to do")
        #expect(microphone.detail?.key == "Allow the microphone so Lintel can hear the meeting.")
        let model = try #require(status(location: .missing))
        #expect(model.title.key == "2 things to do")
        #expect(model.detail?.key == "The speech model isn’t installed.")
        let both = try #require(status(location: .missing, microphone: .notDetermined))
        #expect(both.title.key == "%lld things to do")
    }

    @Test func nothingMissingIsReady() throws {
        let ready = try #require(status(missing: nil))
        #expect(ready.title.key == "Ready")
    }

    /// The languages switch the recording to an installed Whisper: a missing standard model does not block it, and
    /// Ready names Whisper.
    @Test func aRecordingSwitchedToWhisperDoesNotNeedTheStandardModel() throws {
        let banner = try #require(status(location: .missing, usesWhisperInstead: true, missing: nil))
        #expect(banner.title.key == "Ready")
        #expect(String(localized: try #require(banner.detail)).contains("Whisper large-v3-turbo"))
    }

    // MARK: The plugin's banner

    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
        return condition()
    }

    @Test func theBannerAppearsWithTheListAndGoesWithWhisperInstalled() async throws {
        let languages = StreamingSpeechLanguages(["pl", "en"])
        let harness = try MeetingsHarness(speechLanguages: languages)
        try installSparseSpeechModel(ModelCatalog.parakeetUltra, in: harness.context.modelsDirectory)
        let plugin = MeetingsPlugin(context: harness.context, authorizer: FakeAuthorizer(.granted))
        let center = NotificationCenter()
        plugin.appActivationCenter = center
        try await plugin.activate()
        #expect(plugin.settingsStatus?.title.key == "Ready")

        // A language only Whisper transcribes: the shell is told to read the banner again.
        let before = harness.changes.get()
        languages.update(SpeechLanguageSelection(mode: .automatic, languages: ["pl", "ja"], isDerived: false))
        #expect(await eventually { harness.changes.get() > before })
        let banner = try #require(plugin.settingsStatus)
        #expect(banner.title.key == "1 thing to do")
        #expect(banner.detail?.key == "Get Whisper to transcribe %@")
        #expect(plugin.modelUsage[0].packageID == ModelCatalog.parakeetUltra.id)

        // Whisper arrives in Models: the banner is Ready and Whisper is the model the next recording uses.
        try installSparseSpeechModel(ModelCatalog.whisperLargeV3Turbo, in: harness.context.modelsDirectory)
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        #expect(await eventually { plugin.settingsStatus?.title.key == "Ready" })
        #expect(plugin.settingsStatus?.detail?.key != "Get Whisper to transcribe %@")
        #expect(plugin.modelUsage[0].packageID == ModelCatalog.whisperLargeV3Turbo.id)

        // Always one language that the standard model knows: no Whisper item, the standard model again.
        languages.update(SpeechLanguageSelection(mode: .single("pl"), languages: ["pl", "ja"], isDerived: false))
        #expect(plugin.modelUsage[0].packageID == ModelCatalog.parakeetUltra.id)
        await plugin.deactivate()
    }

    @Test func aChosenWhisperNeverShowsTheItem() async throws {
        let harness = try MeetingsHarness(
            settings: ["plugins.meetings.speechModel": .string(ModelCatalog.whisperLargeV3Turbo.id)],
            speechLanguages: StreamingSpeechLanguages(["ja"]))
        let plugin = MeetingsPlugin(context: harness.context, authorizer: FakeAuthorizer(.granted))
        plugin.appActivationCenter = NotificationCenter()
        try await plugin.activate()
        let banner = try #require(plugin.settingsStatus)
        // Whisper is the chosen model and missing: the ordinary speech-model item, never a second one for it.
        #expect(banner.title.key == "1 thing to do")
        #expect(banner.detail?.key == "The speech model isn’t installed.")
        await plugin.deactivate()
    }
}

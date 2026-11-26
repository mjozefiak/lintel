import Foundation
import LintelKit
import LintelSpeech
import Synchronization
import Testing

@testable import MeetingsPlugin

/// Every file of `package` at its expected size, as sparse files in the Meetings speech folder: the model looks
/// installed without a download and without using the disk space.
func installSparseSpeechModel(_ package: ModelPackage, in models: URL) throws {
    let folder = models.appending(path: "speech/\(package.id)", directoryHint: .isDirectory)
    for entry in package.files {
        let url = folder.appending(path: package.relativePath(of: entry.file, in: entry.source))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(entry.file.size))
        try handle.close()
    }
}

/// Spec `2026-11-23-automatic-language-detection`, step 2.5 ("Automatic switch to Whisper", D3): the model a
/// recording starts with comes from `SpeechEngineRouter`, row by row, with fake model locations.
@MainActor
@Suite struct MeetingEngineRoutingTests {
    private static let parakeet = ModelCatalog.parakeetUltra
    private static let whisper = ModelCatalog.whisperLargeV3Turbo

    /// A runtime whose models are where `installed` says; records every lookup's custom folder.
    private final class Locations: Sendable {
        let installed: Set<String>
        let asked = Mutex<[(id: String, custom: URL?)]>([])

        init(_ installed: Set<String>) { self.installed = installed }

        func locate(_ package: ModelPackage, _ custom: URL?) -> ModelLocation {
            asked.withLock { $0.append((package.id, custom)) }
            if let custom {
                return installed.contains(package.id) ? .customFolder(custom) : .customFolderUnavailable(custom)
            }
            return installed.contains(package.id) ? .installed(URL(filePath: "/models/\(package.id)")) : .missing
        }
    }

    private func lookup(
        selected: ModelPackage, mode: SpeechLanguageSelection.Mode = .automatic, languages: [String],
        installed: Set<String>, settings extra: [String: SettingValue] = [:]
    ) async throws -> (SpeechModelLookup, Locations) {
        var values = extra
        values["plugins.meetings.speechModel"] = .string(selected.id)
        let harness = try MeetingsHarness(
            settings: values, speechLanguages: ChangingSpeechLanguages(languages, mode: mode))
        var runtime = MeetingsRuntime(context: harness.context, settings: harness.meetingsSettings)
        let locations = Locations(installed)
        runtime.locateSpeech = { locations.locate($0, $1) }
        return (await runtime.speechLookup(), locations)
    }

    private func ready(_ package: ModelPackage) -> SpeechModelLookup {
        .ready(modelID: package.id, folder: URL(filePath: "/models/\(package.id)"))
    }

    /// Row 1: Whisper chosen, any languages, Whisper installed.
    @Test func whisperChosenRecordsWithWhisper() async throws {
        for languages in [["pl", "en"], ["ja"]] {
            let (found, _) = try await lookup(
                selected: Self.whisper, languages: languages, installed: [Self.whisper.id, Self.parakeet.id])
            #expect(found == ready(Self.whisper))
        }
    }

    /// Row 2: every language in play is one Parakeet transcribes: Parakeet, whether Whisper is there or not.
    @Test func languagesParakeetSupportsKeepParakeet() async throws {
        for installed in [Set([Self.parakeet.id]), [Self.parakeet.id, Self.whisper.id]] {
            let (list, _) = try await lookup(
                selected: Self.parakeet, languages: ["pl", "en", "uk"], installed: installed)
            #expect(list == ready(Self.parakeet))
            let (single, _) = try await lookup(
                selected: Self.parakeet, mode: .single("pl"), languages: ["pl", "ja"], installed: installed)
            #expect(single == ready(Self.parakeet))
        }
    }

    /// Row 3: a listed (or the single) language Parakeet cannot transcribe and Whisper installed: Whisper, even
    /// with the standard model missing.
    @Test func aLanguageOnlyWhisperKnowsSwitchesToAnInstalledWhisper() async throws {
        let (list, _) = try await lookup(
            selected: Self.parakeet, languages: ["pl", "ja"], installed: [Self.parakeet.id, Self.whisper.id])
        #expect(list == ready(Self.whisper))
        let (single, _) = try await lookup(
            selected: Self.parakeet, mode: .single("ja"), languages: ["pl"], installed: [Self.whisper.id])
        #expect(single == ready(Self.whisper))
    }

    /// Row 4: Whisper needed but not installed: Parakeet (without a hint, see `MeetingLanguage`); never a download.
    @Test func aLanguageOnlyWhisperKnowsWithoutWhisperStaysOnParakeet() async throws {
        let (found, _) = try await lookup(
            selected: Self.parakeet, languages: ["pl", "ja"], installed: [Self.parakeet.id])
        #expect(found == ready(Self.parakeet))
        let (missing, _) = try await lookup(selected: Self.parakeet, languages: ["pl", "ja"], installed: [])
        #expect(missing == .missing)
    }

    /// A folder the user chose belongs to the chosen model: Whisper reached through the router comes from its
    /// download, never from the standard model's folder.
    @Test func theChosenFolderIsNeverUsedForTheRoutedWhisper() async throws {
        let folder = "/Volumes/Models/parakeet"
        let (found, locations) = try await lookup(
            selected: Self.parakeet, languages: ["ja"], installed: [Self.parakeet.id, Self.whisper.id],
            settings: ["plugins.meetings.speechModelFolder": .string(folder)])
        #expect(found == ready(Self.whisper))
        let asked = locations.asked.withLock { $0 }
        #expect(asked.allSatisfy { $0.id == Self.whisper.id ? $0.custom == nil : true })
        let (standard, _) = try await lookup(
            selected: Self.parakeet, languages: ["pl"], installed: [Self.parakeet.id],
            settings: ["plugins.meetings.speechModelFolder": .string(folder)])
        guard case .ready(let id, let url) = standard else {
            Issue.record("the chosen model's folder was not used")
            return
        }
        #expect(id == Self.parakeet.id)
        #expect(url.standardizedFileURL.path(percentEncoded: false).hasPrefix(folder))
    }

    /// The model the recording reports is the one it will record with: the request's model id, stored as the
    /// meeting's `speech_model_id`, is the routed one.
    @Test func theRecordingRequestCarriesTheRoutedModel() async throws {
        let harness = try MeetingsHarness(speechLanguages: ChangingSpeechLanguages(["pl", "ja"]))
        let plugin = MeetingsPlugin(context: harness.context)
        var runtime = plugin.runtime
        runtime.locateSpeech = { package, _ in
            .installed(URL(filePath: "/models/\(package.id)"))
        }
        let routed = runtime
        let requests = Mutex<[String]>([])
        plugin.adjustControllerDependencies = { dependencies in
            dependencies.authorizer = FakeAuthorizer(.granted)
            dependencies.hud = RecordingHUD()
            dependencies.speechModel = { await routed.speechLookup() }
            dependencies.makeSession = { request in
                requests.withLock { $0.append(request.modelID) }
                return ScriptedSession(ScriptedSession.Behaviour())
            }
        }
        try await plugin.activate()
        let controller = try #require(plugin.controller)
        controller.start()
        for _ in 0..<300 where requests.withLock({ $0.isEmpty }) { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(requests.withLock { $0 } == [Self.whisper.id])
        await plugin.deactivate()
    }

    /// Row 4's hint: while a language in play needs Whisper, a Parakeet recording never gets a script hint, even
    /// once a Polish profile is settled.
    @Test func noHintWhileALanguageNeedsWhisper() {
        var profile = LanguageProfile()
        profile.add(LanguageGuess(code: "pl", confidence: 0.95), duration: 60)
        let needsWhisper = SpeechLanguageSelection(mode: .automatic, languages: ["pl", "ja"], isDerived: false)
        #expect(MeetingLanguage.options(for: needsWhisper, profile: profile).scriptHint == nil)
        let standard = SpeechLanguageSelection(mode: .automatic, languages: ["pl", "en"], isDerived: false)
        #expect(MeetingLanguage.options(for: standard, profile: profile).scriptHint == .latin)
    }
}

/// `modelUsage` reports the model the next recording would use, so the Models pane shows Whisper as used and
/// needed and guards its removal.
@MainActor
@Suite struct MeetingsRoutedModelUsageTests {
    @Test func whisperIsTheSpeechUsageOnlyWhileTheLanguagesNeedItAndItIsInstalled() async throws {
        let languages = ChangingSpeechLanguages(["pl", "en"])
        let harness = try MeetingsHarness(speechLanguages: languages)
        let plugin = MeetingsPlugin(context: harness.context)
        let whisper = ModelCatalog.whisperLargeV3Turbo

        // Before: the standard model.
        await plugin.ui.model.refreshStatus()
        #expect(plugin.modelUsage[0].packageID == ModelCatalog.parakeetUltra.id)

        // A language only Whisper knows, Whisper missing: still the standard model (the banner asks for Whisper).
        languages.update(SpeechLanguageSelection(mode: .automatic, languages: ["pl", "ja"], isDerived: false))
        #expect(plugin.modelUsage[0].packageID == ModelCatalog.parakeetUltra.id)

        // Whisper installed: it is the speech model Meetings uses and needs, without a folder choice.
        try installSparseSpeechModel(whisper, in: harness.context.modelsDirectory)
        await plugin.ui.model.refreshStatus()
        let usage = plugin.modelUsage[0]
        #expect(usage.packageID == whisper.id)
        #expect(usage.kind == .speech)
        #expect(usage.isRequired && usage.isSelected)
        #expect(usage.chooseFolder == nil)
        #expect(usage.customFolder == nil)
        #expect(plugin.modelUsage.map(\.kind) == [.speech, .diarization, .llm])

        // Its removal guard: a recording or finishing meeting holds it; the reservation blocks a new recording.
        #expect(await usage.isInUse() == false)
        plugin.activity.begin()
        #expect(await usage.isInUse())
        plugin.activity.end()
        let release = usage.reserveRemoval()
        #expect(plugin.activity.isRemovingModel)
        release()

        // After: the list no longer needs it.
        languages.update(SpeechLanguageSelection(mode: .automatic, languages: ["pl"], isDerived: false))
        #expect(plugin.modelUsage[0].packageID == ModelCatalog.parakeetUltra.id)
        #expect(plugin.modelUsage[0].chooseFolder != nil)
    }
}

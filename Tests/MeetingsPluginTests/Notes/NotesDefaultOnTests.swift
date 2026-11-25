import Foundation
import LintelKit
import LintelSpeech
import Testing

@testable import MeetingsPlugin

/// Issue #252: notes are on by default and written by the model on this Mac. A new install that has not downloaded
/// the model records and saves meetings as before, says that the notes wait for the model, and writes them once
/// the model is there.
@MainActor
@Suite struct NotesDefaultOnTests {
    @Test func aNewInstallWritesNotesAfterAMeetingWithoutTouchingTheSwitch() async throws {
        let rig = try NotesServiceRig(settings: [:])
        await rig.start()
        #expect(rig.service.board.snapshot.enabled)
        let id = try await rig.addMeeting()
        rig.library.meetingReady(id)
        #expect(await rig.settle())
        #expect(try rig.record(id).status == .ok)
        #expect(rig.harness.settings.value(forKey: "plugins.meetings.notesEnabled") == nil)
    }

    @Test func withoutTheModelTheMeetingIsKeptAndItsNoteSaysItWaitsForTheModel() async throws {
        let rig = try NotesServiceRig(settings: [:])
        rig.file.update { $0 = nil }
        await rig.start()
        let id = try await rig.addMeeting()
        rig.library.meetingReady(id)
        #expect(await rig.settle())

        let document = try rig.document(id)
        #expect(document.status == .ready)
        #expect(!document.segments.isEmpty)
        #expect(document.notesMarkdown == nil)
        #expect(try rig.record(id).status == .none)
        #expect(rig.llm.calls.isEmpty)
        // Nothing is opened or downloaded by itself.
        #expect(rig.modelsOpened.get().isEmpty)
        let entry = try #require(try rig.store.libraryEntries(matching: nil, filter: .all, limit: 5).first)
        #expect(MeetingNoteMapping.summary(entry, board: rig.service.board, appName: { _ in nil }).state == .needsModel)
    }

    /// A download from any screen (here: the file simply appears) is noticed by the watch, without a refresh call.
    @Test func theWaitingMeetingGetsItsNotesOnceTheModelIsOnThisMac() async throws {
        let rig = try NotesServiceRig(settings: [:], modelWatchInterval: .milliseconds(20))
        rig.file.update { $0 = nil }
        await rig.start()
        let first = try await rig.addMeeting()
        let second = try await rig.addMeeting()
        rig.library.meetingReady(first)
        rig.library.meetingReady(second)
        #expect(await rig.settle())
        #expect(rig.service.board.snapshot.awaitingModel == [first, second])

        rig.file.update { $0 = URL(filePath: "/models/llm/notes-test.gguf") }
        #expect(await rig.wait("the waiting notes to be written") { (try? rig.record(second).status) == .ok })
        #expect(try rig.record(first).status == .ok)
        #expect(!rig.service.board.snapshot.needsModel)
        #expect(rig.service.board.snapshot.awaitingModel.isEmpty)
        await rig.service.shutDown()
    }

    @Test func theModelArrivingWhileNotesAreOffWritesNothing() async throws {
        let rig = try NotesServiceRig(settings: [:])
        rig.file.update { $0 = nil }
        await rig.start()
        let id = try await rig.addMeeting()
        rig.library.meetingReady(id)
        #expect(await rig.settle())
        rig.settings.setNotesEnabled(false)
        rig.file.update { $0 = URL(filePath: "/models/llm/notes-test.gguf") }
        await rig.service.refreshAvailability()
        #expect(await rig.settle())
        #expect(rig.llm.calls.isEmpty)
        #expect(try rig.record(id).status == .none)
        #expect(!rig.service.board.snapshot.needsModel)
    }

    /// The watch looks for the model only while notes are on and no provider is chosen: switching notes off ends the
    /// wait, the looking stops, and a model that arrives after notes are back on writes nothing by itself.
    @Test func switchingNotesOffEndsTheWaitAndTheWatch() async throws {
        let rig = try NotesServiceRig(settings: [:], modelWatchInterval: .milliseconds(20))
        rig.file.update { $0 = nil }
        await rig.start()
        let id = try await rig.addMeeting()
        rig.library.meetingReady(id)
        #expect(await rig.settle())
        #expect(rig.service.board.snapshot.awaitingModel == [id])
        // The watch is running: it keeps looking for the file.
        let seen = rig.modelLookups.get()
        #expect(await waitFor("the watch to look for the model") { rig.modelLookups.get() >= seen + 2 })

        // What the switch in Settings or the setup step does.
        rig.settings.setNotesEnabled(false)
        await rig.service.refreshAvailability()
        #expect(rig.service.board.snapshot.awaitingModel.isEmpty)
        #expect(!rig.service.board.snapshot.needsModel(for: id))
        // At most the one look whose wait was already under way, then none (a watch still running would look about
        // ten more times at this interval). One bound, so a slow main actor cannot make it fail.
        let atClear = rig.modelLookups.get()
        try await Task.sleep(for: .milliseconds(250))
        #expect(rig.modelLookups.get() <= atClear + 1)

        rig.settings.setNotesEnabled(true)
        rig.file.update { $0 = URL(filePath: "/models/llm/notes-test.gguf") }
        await rig.service.refreshAvailability()
        #expect(await rig.settle())
        #expect(rig.llm.calls.isEmpty)
        #expect(try rig.record(id).status == .none)
        await rig.service.shutDown()
    }

    @Test func switchingThePluginOffStopsTheWatch() async throws {
        let rig = try NotesServiceRig(settings: [:], modelWatchInterval: .milliseconds(20))
        rig.file.update { $0 = nil }
        await rig.start()
        let id = try await rig.addMeeting()
        rig.library.meetingReady(id)
        #expect(await rig.settle())
        await rig.service.shutDown()
        rig.file.update { $0 = URL(filePath: "/models/llm/notes-test.gguf") }
        try await Task.sleep(for: .milliseconds(120))
        #expect(rig.llm.calls.isEmpty)
        #expect(try rig.record(id).status == .none)
    }
}

/// The "Notes on this Mac" part of the `meetings.setup` step (#252): what it offers in each state.
@MainActor
@Suite struct NotesModelOfferTests {
    private func total(_ rig: NotesSettingsRig) -> Int { rig.model.model.package.totalBytes }

    @Test func aNewInstallIsOfferedTheModelForThisMac() async throws {
        let rig = try NotesSettingsRig(physicalMemory: 16 * NotesServiceRig.gibibyte)
        await rig.model.refresh()
        #expect(rig.model.model.id == LLMModelCatalog.available(physicalMemory: 16 * NotesServiceRig.gibibyte)[0].id)
        #expect(rig.model.offer == .download(totalBytes: total(rig), remainingBytes: nil))
        #expect(rig.model.offer.waitsForModel)
        // Nothing was downloaded to find this out.
        #expect(rig.downloader.callCount == 0)
    }

    @Test func notesSwitchedOffOfferNothing() async throws {
        let rig = try NotesSettingsRig(settings: ["plugins.meetings.notesEnabled": .bool(false)])
        await rig.model.refresh()
        #expect(rig.model.offer == .off)
        #expect(!rig.model.offer.waitsForModel)
    }

    @Test func notEnoughSpaceShowsWhatIsNeededAndWhatIsFreeWithoutADownload() async throws {
        let rig = try NotesSettingsRig(availableSpace: 1_000)
        await rig.model.refresh()
        let needed = total(rig) + total(rig) / 10
        #expect(rig.model.offer == .noSpace(ModelSpaceCheck(needed: needed, available: 1_000)))
        #expect(rig.model.offer.waitsForModel)
    }

    @Test func aStoppedDownloadIsOfferedToContinueWithWhatIsLeft() async throws {
        let rig = try NotesSettingsRig()
        let model = rig.model.model
        let partial = rig.directory.url.appending(path: "llm/\(model.package.id).partial", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
        let piece = partial.appending(path: "piece.part")
        #expect(FileManager.default.createFile(atPath: piece.path, contents: nil))
        let handle = try FileHandle(forWritingTo: piece)
        try handle.truncate(atOffset: 1_000_000)
        try handle.close()
        await rig.model.refresh()
        #expect(rig.model.offer == .download(totalBytes: total(rig), remainingBytes: total(rig) - 1_000_000))
    }

    @Test func aFailedDownloadOffersTryAgainAndAnInstalledModelIsShownAsDownloaded() async throws {
        let rig = try NotesSettingsRig()
        await rig.model.refresh()
        rig.model.download()
        #expect(rig.model.offer == .downloading(ModelProgress(bytesDone: 0, bytesTotal: total(rig))))
        await rig.model.waitForDownload()
        guard case .failed(let message) = rig.model.offer else {
            Issue.record("expected a failed offer, got \(rig.model.offer)")
            return
        }
        #expect(message == rig.model.errorMessage)
        try rig.install(rig.model.model)
        await rig.model.refresh()
        // The message of the earlier attempt does not hide a model that is there now.
        #expect(rig.model.offer == .installed)
        #expect(!rig.model.offer.waitsForModel)
    }

    @Test(arguments: [
        ("missing", "download"), ("partial", "continue"), ("downloading", "downloading"), ("offline", "failed"),
        ("noSpace", "noSpace"), ("installed", "installed"),
    ])
    func theQAKeyForcesEachStateAndDownloadsNothing(_ value: String, _ expected: String) async throws {
        let rig = try NotesSettingsRig(settings: ["plugins.meetings.qaNotesDownload": .string(value)])
        await rig.model.refresh()
        rig.model.download()
        #expect(!rig.model.isDownloading || expected == "downloading")
        let kind: String =
            switch rig.model.offer {
            case .off: "off"
            case .installed: "installed"
            case .downloading: "downloading"
            case .noSpace: "noSpace"
            case .failed: "failed"
            case .download(_, nil): "download"
            case .download: "continue"
            }
        #expect(kind == expected, "\(value)")
        #expect(rig.downloader.callCount == 0)
    }
}

import Foundation
import LintelKit
import LintelSpeech
import LintelTestSupport
import Testing

@testable import MeetingsPlugin

/// What the recorder asks the rest of the plugin: the meeting's Notes key, the meeting's row id, the notes
/// pipeline. Nothing real is stored or written.
@MainActor
private final class RecorderProbe {
    /// Meeting row id → the meeting's `uuid` (its Notes key).
    var keys: [Int64: String] = [:]
    var keyRequests = 0
    var meetingIDRequests = 0
    var regenerated: [Int64] = []
    /// The meetings whose notes job is queued or running.
    var jobs: Set<Int64> = []
    var notesBusy = false
    /// The meeting row id → how its notes stand (`failed` or `partial` are the ones "Try Again" writes again).
    var statuses: [Int64: NotesStatus] = [:]
    var now = Date(timeIntervalSince1970: 1_800_000_000)

    func noteKey(_ id: Int64) -> NoteKey? {
        keyRequests += 1
        guard let uuid = keys[id] else { return nil }
        return NoteKey(pluginID: "meetings", id: uuid)
    }

    func meetingID(_ key: NoteKey) -> Int64? {
        meetingIDRequests += 1
        guard key.pluginID == "meetings" else { return nil }
        return keys.first { $0.value == key.id }?.key
    }
}

/// The HUD state the controller showed, handed to the recorder once it exists.
@MainActor
private final class HUDForwarder {
    var handler: ((MeetingHUDState?) -> Void)?
    var meetingRegistered: ((Int64) -> Void)?
}

/// One step of a status stream.
enum StatusStep: Equatable, Sendable {
    case value(LiveRecordingStatus)
    case ended
}

/// Reads a status stream in order. Each step rings `changes`, so a test waits for the step it needs instead of
/// polling; the shared `ChangeBell` helper's guard bounds the wait and turns a hang into one issue at the
/// caller's line.
@MainActor
final class StatusCollector {
    private(set) var steps: [StatusStep] = []
    let changes = ChangeBell()
    private var task: Task<Void, Never>?

    init(_ stream: AsyncStream<LiveRecordingStatus>) {
        task = Task { @MainActor [weak self] in
            var iterator = stream.makeAsyncIterator()
            while let value = await iterator.next() {
                guard let self else { return }
                self.steps.append(.value(value))
                self.changes.ring()
            }
            self?.steps.append(.ended)
            self?.changes.ring()
        }
    }

    /// Stops reading (the stream of a recording that keeps running has no end).
    func cancel() {
        task?.cancel()
        task = nil
    }
}

/// Waits until the collector's newest step satisfies `condition`. The condition is the assertion; the guard only
/// bounds the wait.
@MainActor
func waitForStep(
    _ collector: StatusCollector, _ what: String = "the status stream to answer",
    sourceLocation: SourceLocation = #_sourceLocation, _ condition: @escaping (StatusStep) -> Bool
) async {
    await collector.changes.wait(what, sourceLocation: sourceLocation) {
        collector.steps.last.map(condition) ?? false
    }
}

/// A controller over scripted sessions with the plugin's live recorder attached to its HUD, as the plugin wires
/// them.
@MainActor
private final class RecorderRig {
    let harness: MeetingsHarness
    let controller: ControllerRig
    let probe = RecorderProbe()
    let recorder: MeetingsLiveRecorder

    var meetingKey: NoteKey? { probe.keys[7].map { NoteKey(pluginID: "meetings", id: $0) } }

    init(
        _ settings: [String: SettingValue] = [:], access: MicrophoneAccess = .granted,
        keychainError: KeychainError? = nil
    ) throws {
        probe.keys = [7: "m-7"]
        probe.statuses = [7: .failed]
        let forwarder = HUDForwarder()
        controller = try ControllerRig(
            settings: settings, access: access, keychainError: keychainError,
            hudObserver: { state in forwarder.handler?(state) },
            meetingRegistered: { id in forwarder.meetingRegistered?(id) })
        harness = controller.harness
        let probe = probe
        let token = UUID()
        let recorder = MeetingsLiveRecorder(
            dependencies: MeetingsLiveRecorder.Dependencies(
                noteKey: { probe.noteKey($0) },
                meetingID: { probe.meetingID($0) },
                regenerateNotes: { probe.regenerated.append($0) },
                hasNotesJob: { probe.jobs.contains($0) },
                notesBusy: { probe.notesBusy },
                notesStatus: { probe.statuses[$0] },
                now: { probe.now }))
        self.recorder = recorder
        forwarder.handler = { state in recorder.hudChanged(state, from: token) }
        forwarder.meetingRegistered = { id in recorder.meetingRegistered(id, from: token) }
        recorder.attach(controller.controller, token: token)
    }

    /// Starts through the recorder and waits until the status names the meeting (one HUD update after the
    /// session returned the meeting's id).
    func startRecording() async throws {
        try await recorder.start()
        await drainEvents()
        await eventually("the recording is named") {
            if case .recording = recorder.currentStatus { return true }
            return false
        }
    }

    /// Sends a marker event and waits until the controller has handled it, which also refreshes the HUD once the
    /// meeting has its id (the recorder reads the key then).
    func drainEvents() async { await controller.drainEvents() }
}

@MainActor
@Suite struct MeetingsLiveRecorderTests {
    // MARK: Status stream

    @Test func aRecorderThatIsNotAttachedReplaysIdleAndEndsTheStream() async throws {
        let probe = RecorderProbe()
        let recorder = MeetingsLiveRecorder(
            dependencies: .init(
                noteKey: { probe.noteKey($0) }, meetingID: { probe.meetingID($0) },
                regenerateNotes: { probe.regenerated.append($0) }, hasNotesJob: { _ in false }, notesBusy: { false }))
        let collector = StatusCollector(recorder.status())
        await waitForStep(collector) { $0 == .ended }
        #expect(collector.steps == [.value(.idle), .ended])
        await #expect(throws: LiveRecordingFailure.other) { try await recorder.start() }
        // A retry has nothing to run and says so.
        await #expect(throws: NoteSourceError.self) {
            try await recorder.retryNotes(NoteKey(pluginID: "meetings", id: "m-7"))
        }
    }

    @Test func everySubscriberGetsTheCurrentValueAndThenTheChanges() async throws {
        let rig = try RecorderRig()
        let first = StatusCollector(rig.recorder.status())
        await waitForStep(first) { $0 == .value(.idle) }
        try await rig.startRecording()
        let recording = LiveRecordingStatus.recording(
            key: rig.meetingKey!, since: rig.probe.now, hearing: .everyone, warning: nil)
        await waitForStep(first) { $0 == .value(recording) }
        // A subscriber that comes later is replayed the current value, not the history.
        let second = StatusCollector(rig.recorder.status())
        await waitForStep(second) { $0 == .value(recording) }
        #expect(second.steps == [.value(recording)])
        first.cancel()
        second.cancel()
    }

    @Test func detachingSendsIdleAndFinishesEveryStream() async throws {
        let rig = try RecorderRig()
        try await rig.startRecording()
        let collector = StatusCollector(rig.recorder.status())
        await waitForStep(collector) { $0 == .value(rig.recorder.currentStatus) }
        rig.recorder.detach()
        await waitForStep(collector) { $0 == .ended }
        #expect(collector.steps.suffix(2) == [.value(.idle), .ended])
        #expect(!rig.recorder.isAttached)
    }

    // MARK: Recording

    @Test func aRecordingIsNamedWithItsMeetingKeyAndLooksUpTheKeyOnce() async throws {
        let rig = try RecorderRig()
        try await rig.startRecording()
        #expect(rig.controller.controller.phase == .recording)
        #expect(rig.probe.keyRequests == 1)
        #expect(
            rig.recorder.currentStatus
                == .recording(key: rig.meetingKey!, since: rig.probe.now, hearing: .everyone, warning: nil))
        // The HUD keeps working exactly as before: the recorder only watches it.
        #expect(rig.controller.hud.states.contains { $0.isRecording })
        // More updates of the same recording do not look the key up again.
        rig.controller.session?.send(.level(.mic, 0.3))
        await rig.drainEvents()
        #expect(rig.probe.keyRequests == 1)
    }

    @Test func theStartingStatusIsShownUntilTheKeyIsKnown() async throws {
        let rig = try RecorderRig()
        rig.probe.keys = [:]  // the library cannot name the meeting yet
        try await rig.recorder.start()
        await eventually("the HUD shows the recording") { rig.controller.controller.phase == .recording }
        #expect(rig.recorder.currentStatus == .starting)
    }

    // MARK: Hearing and warnings

    @Test func theSilenceWarningComesWithTheHUDTimerAndClearsWhenSoundReturns() async throws {
        let rig = try RecorderRig()
        try await rig.startRecording()
        await rig.controller.advance(by: .seconds(20), firing: 2)
        #expect(rig.controller.hud.lastRecording?.noSystemAudio == true)
        #expect(
            rig.recorder.currentStatus
                == .recording(key: rig.meetingKey!, since: rig.probe.now, hearing: .everyone, warning: .silence))
        rig.controller.session?.send(.level(.system, 0.4))
        await rig.drainEvents()
        #expect(
            rig.recorder.currentStatus
                == .recording(key: rig.meetingKey!, since: rig.probe.now, hearing: .everyone, warning: nil))
    }

    @Test func aSystemTrackThatNeverStartedIsMicrophoneOnlyAndNoWarning() async throws {
        let rig = try RecorderRig()
        try await rig.startRecording()
        rig.controller.session?.send(.trackUnavailable(.system))
        await rig.drainEvents()
        #expect(
            rig.recorder.currentStatus
                == .recording(key: rig.meetingKey!, since: rig.probe.now, hearing: .microphoneOnly, warning: nil))
        // The 20 s timer of a system track that was never available is that start problem, not a warning.
        await rig.controller.advance(by: .seconds(20), firing: 2)
        #expect(
            rig.recorder.currentStatus
                == .recording(key: rig.meetingKey!, since: rig.probe.now, hearing: .microphoneOnly, warning: nil))
    }

    @Test func aMicrophoneThatNeverStartedIsCallOnly() async throws {
        let rig = try RecorderRig()
        try await rig.startRecording()
        rig.controller.session?.send(.trackUnavailable(.mic))
        await rig.drainEvents()
        #expect(
            rig.recorder.currentStatus
                == .recording(key: rig.meetingKey!, since: rig.probe.now, hearing: .callOnly, warning: nil))
    }

    @Test func aSystemAudioOnlyRecordingIsCallOnly() async throws {
        // The shortcut's own path: the microphone is denied, the HUD's "record the system audio only" is taken.
        let rig = try RecorderRig(access: .denied)
        rig.controller.controller.start()
        await eventually("the decision") { rig.controller.controller.phase == .awaitingMicrophoneDecision }
        rig.controller.controller.perform(.recordSystemAudioOnly)
        await eventually("recording") { rig.controller.controller.phase == .recording }
        rig.controller.session?.send(.level(.system, 0.3))
        await rig.drainEvents()
        #expect(
            rig.recorder.currentStatus
                == .recording(key: rig.meetingKey!, since: rig.probe.now, hearing: .callOnly, warning: nil))
    }

    @Test func aLostSystemTrackIsCallAudioMissingAndTheHearingStays() async throws {
        let rig = try RecorderRig()
        try await rig.startRecording()
        rig.controller.session?.send(.trackLost(.system))
        await rig.drainEvents()
        let expected: LiveRecordingStatus = .recording(
            key: rig.meetingKey!, since: rig.probe.now, hearing: .everyone, warning: .callAudioMissing)
        #expect(rig.recorder.currentStatus == expected)
    }

    @Test func aMicrophoneThatWentAwayIsMicrophoneLostAndTheHearingStays() async throws {
        let rig = try RecorderRig()
        try await rig.startRecording()
        rig.controller.session?.send(.trackLost(.mic))
        await rig.drainEvents()
        #expect(
            rig.recorder.currentStatus
                == .recording(key: rig.meetingKey!, since: rig.probe.now, hearing: .everyone, warning: .microphoneLost))
    }

    @Test func digitalSilenceOfTheMicrophoneIsAWarningAndSoundClearsIt() async throws {
        let rig = try RecorderRig()
        try await rig.startRecording()
        rig.controller.session?.send(.level(.mic, 0))
        await rig.drainEvents()
        await rig.controller.advanceMicrophoneCheck(by: .seconds(10))
        #expect(rig.controller.hud.lastRecording?.noMicrophoneAudio == true)
        let expected: LiveRecordingStatus = .recording(
            key: rig.meetingKey!, since: rig.probe.now, hearing: .everyone, warning: .microphoneSilent)
        #expect(rig.recorder.currentStatus == expected)
        rig.controller.session?.send(.level(.mic, 0.3))
        await rig.drainEvents()
        #expect(
            rig.recorder.currentStatus
                == .recording(key: rig.meetingKey!, since: rig.probe.now, hearing: .everyone, warning: nil))
    }

    // MARK: Processing and failures of a finished recording

    @Test func stoppingShowsProcessingAndThenIdleWhenTheMeetingIsSaved() async throws {
        let rig = try RecorderRig()
        // The session's finishing waits, so the processing status is observable.
        let release = Latch()
        rig.controller.behaviour.finishLatch = release
        try await rig.startRecording()
        await rig.recorder.stop(writeNotes: true)
        await eventually("processing") {
            rig.recorder.currentStatus == .processing(key: rig.meetingKey!, progress: nil)
        }
        release.open()
        await eventually("idle") { rig.recorder.currentStatus == .idle }
    }

    @Test func aDiscardedRecordingFailsWithItsKeyAndAFailedMeetingWithTheGenericReason() async throws {
        let rig = try RecorderRig()
        rig.controller.behaviour.outcome = MeetingSessionOutcome(result: .discarded, meetingID: 7)
        try await rig.startRecording()
        await rig.recorder.stop(writeNotes: true)
        await eventually("the discarded recording") {
            rig.recorder.currentStatus == .failed(key: rig.meetingKey, reason: .discarded)
        }
    }

    @Test func aMeetingThatCouldNotBeSavedFailsGenerically() async throws {
        let rig = try RecorderRig()
        rig.controller.behaviour.outcome = MeetingSessionOutcome(result: .failed, meetingID: 7)
        try await rig.startRecording()
        await rig.recorder.stop(writeNotes: true)
        await eventually("the failure") {
            rig.recorder.currentStatus == .failed(key: rig.meetingKey, reason: .other)
        }
    }

    // MARK: Why a recording cannot start

    @Test func aLockedLibraryIsReportedAsLibraryUnavailable() async throws {
        let rig = try RecorderRig(keychainError: .accessDenied)
        await #expect(throws: LiveRecordingFailure.libraryUnavailable) { try await rig.recorder.start() }
        #expect(rig.recorder.currentStatus == .idle)
        #expect(rig.controller.controller.phase == .idle)
    }

    @Test func aMissingModelIsReportedAsModelMissing() async throws {
        let rig = try RecorderRig()
        rig.controller.lookup = .missing
        await #expect(throws: LiveRecordingFailure.modelMissing) { try await rig.recorder.start() }
        #expect(rig.recorder.currentStatus == .idle)
    }

    @Test func aGoneModelFolderIsReportedAsModelMissing() async throws {
        let rig = try RecorderRig()
        rig.controller.lookup = .unavailable
        await #expect(throws: LiveRecordingFailure.modelMissing) { try await rig.recorder.start() }
    }

    @Test func aModelThatIsBeingRemovedIsReportedAsModelBusy() async throws {
        let rig = try RecorderRig()
        rig.controller.activity.beginModelRemoval()
        await #expect(throws: LiveRecordingFailure.modelBusy) { try await rig.recorder.start() }
        rig.controller.activity.endModelRemoval()
        #expect(rig.recorder.currentStatus == .idle)
    }

    @Test func aDeniedMicrophoneIsReportedAndTheHUDsDecisionIsDismissed() async throws {
        let rig = try RecorderRig(access: .denied)
        let hidesBefore = rig.controller.hud.hides
        await #expect(throws: LiveRecordingFailure.microphoneDenied) { try await rig.recorder.start() }
        // Nothing is left half started: no pending decision waits for a HUD button nobody will press.
        #expect(rig.controller.controller.phase == .idle)
        #expect(rig.controller.hud.hides > hidesBefore)
        #expect(rig.recorder.currentStatus == .idle)
    }

    @Test func aDeniedMicrophoneWithoutASystemTrackIsReportedTheSame() async throws {
        let rig = try RecorderRig(["plugins.meetings.systemAudio": .bool(false)], access: .denied)
        await #expect(throws: LiveRecordingFailure.microphoneDenied) { try await rig.recorder.start() }
    }

    @Test func aSessionWithoutAnAudioInputIsReported() async throws {
        let rig = try RecorderRig()
        rig.controller.behaviour.startError = MeetingSessionError.noAudioInput
        await #expect(throws: LiveRecordingFailure.noAudioInput) { try await rig.recorder.start() }
    }

    @Test func aFullDiskIsReported() async throws {
        let rig = try RecorderRig()
        rig.controller.behaviour.startError = SpoolError.insufficientDiskSpace(available: 0, required: 1)
        await #expect(throws: LiveRecordingFailure.lowDisk) { try await rig.recorder.start() }
    }

    @Test func anyOtherStartFailureIsReportedAsOther() async throws {
        let rig = try RecorderRig()
        rig.controller.behaviour.startError = NSError(domain: "test", code: 1)
        await #expect(throws: LiveRecordingFailure.other) { try await rig.recorder.start() }
    }

    @Test func aSecondStartIsAlreadyRecording() async throws {
        let rig = try RecorderRig()
        try await rig.startRecording()
        await #expect(throws: LiveRecordingFailure.alreadyRecording) { try await rig.recorder.start() }
    }

    @Test func aStartAfterAnIgnoredMicrophoneDecisionStartsOverInsteadOfRefusing() async throws {
        let rig = try RecorderRig(access: .denied)
        // The shortcut with a denied microphone: the HUD asks whether to record the system audio only.
        rig.controller.controller.toggle()
        await eventually("the decision") { rig.controller.controller.phase == .awaitingMicrophoneDecision }
        // That decision holds nothing and its HUD can be gone (it hides after 20 s): the window's Record starts
        // over, as the shortcut's second press does, and reports the denial instead of `alreadyRecording`.
        await #expect(throws: LiveRecordingFailure.microphoneDenied) { try await rig.recorder.start() }
        #expect(rig.controller.controller.phase == .idle)
    }

    @Test func aStartWhileTheMeetingIsProcessedIsStillProcessing() async throws {
        let rig = try RecorderRig()
        let release = Latch()
        rig.controller.behaviour.finishLatch = release
        try await rig.startRecording()
        await rig.recorder.stop(writeNotes: true)
        await eventually("finishing") { rig.controller.controller.phase == .finishing }
        await #expect(throws: LiveRecordingFailure.stillProcessing) { try await rig.recorder.start() }
        release.open()
    }

    // MARK: Stop with and without notes

    @Test func stoppingWithoutNotesKeepsTheNotesOffForThatMeeting() async throws {
        let rig = try RecorderRig()
        try await rig.startRecording()
        #expect(!rig.recorder.suppressesNotes(7))
        await rig.recorder.stop(writeNotes: false)
        #expect(rig.recorder.suppressesNotes(7))
        // The answer is given once: a later queue for the same meeting is not dropped.
        #expect(!rig.recorder.suppressesNotes(7))
    }

    @Test func stoppingWithNotesLeavesTheAutomaticJobAlone() async throws {
        let rig = try RecorderRig()
        try await rig.startRecording()
        await rig.recorder.stop(writeNotes: true)
        #expect(!rig.recorder.suppressesNotes(7))
    }

    @Test func aStopWhileTheStartStillWaitsEndsTheAttempt() async throws {
        let rig = try RecorderRig(access: .notDetermined)
        let prompt = Latch()
        rig.controller.authorizer.holdAnswers(until: prompt)
        let start = Task { try await rig.recorder.start() }
        await eventually("the prompt") { rig.controller.authorizer.requests == 1 }
        await rig.recorder.stop(writeNotes: true)
        await #expect(throws: LiveRecordingFailure.other) { try await start.value }
        #expect(rig.controller.controller.phase == .idle)
        prompt.open()
    }

    @Test func aStopWhileTheSessionStartsStopsTheRecording() async throws {
        let rig = try RecorderRig()
        let starting = Latch()
        rig.controller.behaviour.startLatch = starting
        let recording = Task { try await rig.recorder.start() }
        await eventually("the session started") { rig.controller.session?.startCount == 1 }
        // The session exists but has no meeting row yet: stopping must end the recording, not only the awaiting
        // `start()`.
        await rig.recorder.stop(writeNotes: true)
        await #expect(throws: LiveRecordingFailure.other) { try await recording.value }
        starting.open()
        await eventually("the session finishes") { rig.controller.session?.finishCount == 1 }
        await eventually("the controller is idle") { rig.controller.controller.phase == .idle }
        #expect(rig.recorder.currentStatus == .idle)
    }

    @Test func cancellingTheStartWhileTheSessionStartsStopsTheRecordingToo() async throws {
        let rig = try RecorderRig()
        let starting = Latch()
        rig.controller.behaviour.startLatch = starting
        let recording = Task { try await rig.recorder.start() }
        await eventually("the session started") { rig.controller.session?.startCount == 1 }
        recording.cancel()
        await eventually("the session finishes") { rig.controller.session?.finishCount == 1 }
        await #expect(throws: LiveRecordingFailure.other) { try await recording.value }
        starting.open()
        await eventually("the controller is idle") { rig.controller.controller.phase == .idle }
        #expect(rig.recorder.currentStatus == .idle)
    }

    @Test func theShortcutDuringAStartThatWaitsForTheMicrophoneEndsItWithAnError() async throws {
        let rig = try RecorderRig(access: .notDetermined)
        let prompt = Latch()
        rig.controller.authorizer.holdAnswers(until: prompt)
        let recording = Task { try await rig.recorder.start() }
        await eventually("the prompt") { rig.controller.authorizer.requests == 1 }
        // ⌃⌥M while the window's start waits: the attempt is cancelled and the window gets an error, not a
        // success for a recording that never ran.
        rig.controller.controller.toggle()
        await #expect(throws: LiveRecordingFailure.other) { try await recording.value }
        #expect(rig.controller.controller.phase == .idle)
        prompt.open()
    }

    @Test func theShortcutDuringAStartWithASessionStopsTheRecording() async throws {
        let rig = try RecorderRig()
        let starting = Latch()
        rig.controller.behaviour.startLatch = starting
        let recording = Task { try await rig.recorder.start() }
        await eventually("the session started") { rig.controller.session?.startCount == 1 }
        rig.controller.controller.toggle()
        await #expect(throws: LiveRecordingFailure.other) { try await recording.value }
        starting.open()
        await eventually("the session finishes") { rig.controller.session?.finishCount == 1 }
        await eventually("the controller is idle") { rig.controller.controller.phase == .idle }
        #expect(rig.recorder.currentStatus == .idle)
    }

    @Test func stoppingWithoutNotesWhileTheSessionStartsKeepsThemOffForTheMeetingItMakes() async throws {
        let rig = try RecorderRig()
        let starting = Latch()
        rig.controller.behaviour.startLatch = starting
        let recording = Task { try await rig.recorder.start() }
        await eventually("the session started") { rig.controller.session?.startCount == 1 }
        // The meeting has no row yet, so the stop cannot name it: the answer is kept for the meeting it makes.
        await rig.recorder.stop(writeNotes: false)
        await #expect(throws: LiveRecordingFailure.other) { try await recording.value }
        starting.open()
        await eventually("the meeting is over") { rig.controller.controller.phase == .idle }
        #expect(rig.recorder.suppressesNotes(7))
        // And once, like any other: the next queue for that meeting is not dropped.
        #expect(!rig.recorder.suppressesNotes(7))
    }

    @Test func eventsOfAnEarlierAttachmentAreIgnored() async throws {
        let rig = try RecorderRig()
        try await rig.startRecording()
        // A controller whose shutdown passed its timeout keeps sending HUD events after the plugin was activated
        // again: they must not change the status of the attachment that replaced it.
        rig.recorder.hudChanged(.saved, from: UUID())
        #expect(
            rig.recorder.currentStatus
                == .recording(key: rig.meetingKey!, since: rig.probe.now, hearing: .everyone, warning: nil))
    }

    // MARK: Retrying the notes

    @Test func retryingTheNotesQueuesTheExistingPipeline() async throws {
        let rig = try RecorderRig()
        try await rig.recorder.retryNotes(NoteKey(pluginID: "meetings", id: "m-7"))
        #expect(rig.probe.regenerated == [7])
        #expect(rig.probe.meetingIDRequests == 1)
    }

    @Test func retryingNotesThatAreNotFailedOrPartialWritesNothing() async throws {
        let rig = try RecorderRig()
        let key = NoteKey(pluginID: "meetings", id: "m-7")
        // The contract: a retry is for notes that are `failed` or `partial`. `ok` has nothing to write again.
        rig.probe.statuses[7] = .ok
        try await rig.recorder.retryNotes(key)
        #expect(rig.probe.regenerated.isEmpty)
        rig.probe.statuses[7] = .partial
        try await rig.recorder.retryNotes(key)
        #expect(rig.probe.regenerated == [7])
        // A meeting whose notes are nowhere (the library is closed) is left alone too.
        rig.probe.statuses = [:]
        try await rig.recorder.retryNotes(key)
        #expect(rig.probe.regenerated == [7])
    }

    @Test func retryingWhileAnotherJobsRunsIsBusyUnlessItIsThisMeetingsOwn() async throws {
        let rig = try RecorderRig()
        let key = NoteKey(pluginID: "meetings", id: "m-7")
        rig.probe.notesBusy = true
        rig.probe.jobs = [9]
        await #expect(throws: NoteSourceError.busy) { try await rig.recorder.retryNotes(key) }
        #expect(rig.probe.regenerated.isEmpty)
        // This meeting's own job is not "another job".
        rig.probe.jobs = [7]
        try await rig.recorder.retryNotes(key)
        #expect(rig.probe.regenerated == [7])
    }

    @Test func retryingAMeetingThatIsNotThereIsNotFound() async throws {
        let rig = try RecorderRig()
        await #expect(throws: NoteSourceError.notFound) {
            try await rig.recorder.retryNotes(NoteKey(pluginID: "meetings", id: "stranger"))
        }
        await #expect(throws: NoteSourceError.notFound) {
            try await rig.recorder.retryNotes(NoteKey(pluginID: "dictation", id: "m-7"))
        }
        #expect(rig.probe.regenerated.isEmpty)
    }
}

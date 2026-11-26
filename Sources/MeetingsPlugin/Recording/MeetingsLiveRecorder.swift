import Foundation
import LintelKit

/// The meetings' `LiveRecorder` (notes explorer spec, step 2.3): the recording the Notes window's Record button
/// drives, read from the HUD's own states, so the window and the HUD never disagree and the shortcut keeps its
/// behaviour. It is an adapter over `MeetingController`; `start` and `stop` call the same paths as
/// `meetings.record`.
///
/// - `start()` waits until the recording really runs (`meetingRegistered`: the session is up and the meeting has
///   its row; the HUD shows `recording` before that, and a session whose start fails gets there too) or the HUD
///   shows why it cannot, then returns or throws the contract's `LiveRecordingFailure`; nothing is left half
///   started. A denied microphone that the HUD would offer "record the system audio only" for is dismissed: the
///   window has its own sentence and its own button. A recording that ends before that (the shortcut, a stop, a
///   shutdown) answers the waiting `start()` with `LiveRecordingFailure.other`, never with a success for nothing.
/// - `stop(writeNotes: false)` keeps the notes off for the meeting it stops (the automatic job after a saved
///   meeting is dropped for that id); `writeNotes: true` changes nothing, so the automatic job follows
///   `plugins.meetings.notesEnabled` exactly as the shortcut does. A stop while the recording is still starting
///   (the meeting has no row yet) asks the session to finish and switches the notes off when the meeting
///   registers. The answer lives in memory only: a meeting stopped without notes that is still `processing` when
///   the app quits is finished by `RecoveryJob` on the next launch and its notes are written then.
/// - `status()` mirrors the HUD (`LiveRecordingStatus` documents the row of every notice); the warnings come from
///   the same timers, so they go on and off with the HUD's.
/// - It lives as long as the plugin's activation: `attach` and `detach` are `MeetingsPlugin`'s, and `detach`
///   emits `.idle` and finishes every stream. Every HUD and registration event carries the attachment's token, so
///   a controller left over from an earlier activation never changes the status of the one that replaced it.
///
/// Nothing here logs a title, a transcript or a note, and nothing touches `ranking.sqlite`.
@MainActor
final class MeetingsLiveRecorder: LiveRecorder {
    /// What the adapter needs from the plugin. Tests pass their own.
    struct Dependencies {
        /// The Notes key of a meeting (`meetings:<uuid>`), read once per recording; `nil` while the library
        /// cannot say (closed, the meeting not written yet).
        var noteKey: @MainActor (Int64) -> NoteKey?
        /// The row id of a meeting from its Notes key; `nil` when there is no such meeting.
        var meetingID: @MainActor (NoteKey) -> Int64?
        /// Queues the notes of a meeting again ("Try Again").
        var regenerateNotes: @MainActor (Int64) -> Void
        /// Whether the notes pipeline has a job (queued or running) for this meeting.
        var hasNotesJob: @MainActor (Int64) -> Bool
        /// Whether the notes pipeline is busy with any job.
        var notesBusy: @MainActor () -> Bool
        /// How the meeting's notes stand; `nil` while the library is closed or the meeting is not there.
        var notesStatus: @MainActor (Int64) -> NotesStatus? = { _ in nil }

        /// The date `LiveRecordingStatus.recording.since` carries.
        var now: @MainActor () -> Date = { Date() }
    }

    let pluginID: PluginID = MeetingLibraryPresentation.pluginID

    private let deps: Dependencies
    private var controller: MeetingController?
    /// The token of the current attachment; `MeetingsPlugin` hands the controller's HUD and registration hooks the
    /// same one, so a lingering controller of an earlier activation cannot change this attachment's status.
    private var attachment = UUID()
    private var value: LiveRecordingStatus = .idle
    private var continuations: [UUID: AsyncStream<LiveRecordingStatus>.Continuation] = [:]
    /// A `start()` that waits for the recording to be registered or for the HUD to say why it cannot start.
    private var pendingStart: CheckedContinuation<Void, any Error>?
    /// When the recording showed itself to the HUD (`since`).
    private var startedAt: Date?
    /// The Notes key of the recording that runs, once the library can say it.
    private var recordingKey: NoteKey?
    /// The last recording state the HUD showed (the source of `hearing` and `warning`).
    private var lastRecording: MeetingHUDState.Recording?
    /// Meetings whose notes must not be written after they were saved (`stop(writeNotes: false)`). The set lives
    /// in memory only; `meeting.id` is `AUTOINCREMENT`, so an id is never reused.
    private var suppressedNotes: Set<Int64> = []
    /// A `stop(writeNotes: false)` while the meeting had no row yet: the next meeting this recorder hears about
    /// (registered, or saved) gets its notes switched off. Whatever ends the attempt without a meeting drops it.
    private var suppressesNextMeeting = false

    init(dependencies: Dependencies) {
        deps = dependencies
    }

    /// True between `attach` and `detach`: the recorder is the active plugin's.
    var isAttached: Bool { controller != nil }

    /// What a new `status()` subscriber would be sent first (tests read it instead of waiting on a stream).
    var currentStatus: LiveRecordingStatus { value }

    // MARK: Attach

    /// The plugin is active: the recorder follows this controller, under `token`.
    func attach(_ controller: MeetingController, token: UUID) {
        self.controller = controller
        attachment = token
        suppressesNextMeeting = false
        clearRecording()
        set(.idle)
    }

    /// The plugin is switched off: `.idle` to every subscriber, every stream finished, and any `start()` that is
    /// still waiting gets `LiveRecordingFailure.other` (nothing was left running by it).
    func detach() {
        guard controller != nil else { return }
        controller = nil
        suppressesNextMeeting = false
        cancelPendingStart()
        clearRecording()
        set(.idle)
        let all = continuations
        continuations = [:]
        for continuation in all.values { continuation.finish() }
    }

    // MARK: The HUD

    /// The HUD's state as `MeetingController` showed it, or `nil` when the HUD was hidden (the controller's
    /// `hudObserver`). A `recording` state alone does not settle a `start()`: the HUD shows it before the session
    /// starts, and a session whose start fails gets there too — `meetingRegistered` says the recording really runs.
    /// Events of a controller of an earlier attachment are ignored.
    func hudChanged(_ state: MeetingHUDState?, from token: UUID) {
        guard isAttached, token == attachment else { return }
        guard let state else {
            // The HUD was hidden: the attempt is over (the shortcut's cancel, the shutdown) and no meeting comes.
            suppressesNextMeeting = false
            return recordingEnded()
        }
        switch state {
        case .allowMicrophone:
            // The prompt is on screen; `start()` keeps waiting.
            break
        case .recording(let recording):
            lastRecording = recording
            startedAt = startedAt ?? deps.now()
            updateRecording()
        case .finishing, .processing:
            // A recording that moves on without `meetingRegistered` never ran for the waiting window.
            failPendingStart()
            lastRecording = nil
            if let key = resolvedKey() { set(.processing(key: key, progress: nil)) }
        case .saved, .savedIncomplete:
            // A saved meeting still becomes `ready` and asks `suppressesNotes`, so a pending stop-without-notes
            // keeps its answer until then.
            recordingEnded()
        case .problem(let problem):
            // No meeting of this attempt will have notes: the problem ends it.
            suppressesNextMeeting = false
            if pendingStart != nil { return failStart(problem) }
            switch value {
            case .recording, .processing, .starting:
                let key = resolvedKey()
                set(.failed(key: key, reason: Self.failure(problem)))
                clearRecording()
            default:
                break
            }
        }
    }

    /// The recording really started: the meeting has a row, so it has a Notes key.
    func meetingRegistered(_ meetingID: Int64, from token: UUID) {
        guard isAttached, token == attachment else { return }
        if suppressesNextMeeting {
            suppressesNextMeeting = false
            suppressedNotes.insert(meetingID)
        }
        if let key = deps.noteKey(meetingID) { recordingKey = key }
        startedAt = startedAt ?? deps.now()
        settleStart()
        if controller?.phase == .finishing {
            // The window stopped the recording while it was starting: the meeting exists but is being finished.
            if let key = recordingKey { set(.processing(key: key, progress: nil)) }
        } else {
            updateRecording()
        }
    }

    /// Whether the automatic notes job of a meeting was switched off with `stop(writeNotes: false)`, and forgets
    /// the answer: the plugin asks this before it queues the notes of a meeting that just became `ready`. A stop
    /// that came before the meeting had a row is matched to the first meeting the recorder hears about.
    func suppressesNotes(_ meetingID: Int64) -> Bool {
        if suppressesNextMeeting {
            suppressesNextMeeting = false
            suppressedNotes.insert(meetingID)
        }
        return suppressedNotes.remove(meetingID) != nil
    }

    // MARK: LiveRecorder

    func status() -> AsyncStream<LiveRecordingStatus> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: LiveRecordingStatus.self, bufferingPolicy: .bufferingNewest(1))
        guard isAttached else {
            continuation.yield(.idle)
            continuation.finish()
            return stream
        }
        let id = UUID()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in _ = self?.continuations.removeValue(forKey: id) }
        }
        continuation.yield(value)
        return stream
    }

    func start() async throws {
        guard let controller else { throw LiveRecordingFailure.other }
        switch controller.phase {
        case .idle: break
        case .recording, .preparing: throw LiveRecordingFailure.alreadyRecording
        // An ignored microphone decision holds nothing (no audio, no activity) and its HUD hides after 20 s:
        // starting over is what the shortcut's second press does too.
        case .awaitingMicrophoneDecision: controller.perform(.dismiss)
        case .finishing: throw LiveRecordingFailure.stillProcessing
        }
        suppressesNextMeeting = false
        clearRecording()
        set(.starting)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                guard isAttached else {
                    set(.idle)
                    return continuation.resume(throwing: LiveRecordingFailure.other)
                }
                pendingStart = continuation
                controller.start()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancelPendingStart() }
        }
    }

    func stop(writeNotes: Bool) async {
        guard let controller else { return }
        if !writeNotes {
            if let id = controller.meetingID {
                suppressedNotes.insert(id)
            } else if pendingStart != nil || controller.phase == .preparing {
                // The meeting has no row yet (its session is still starting): the answer is applied when the
                // meeting registers, or when it is saved.
                suppressesNextMeeting = true
            }
        }
        // A recording that is still being prepared, waiting for the microphone prompt or starting its session is
        // not registered yet: the window's Stop ends the attempt instead of waiting for a HUD that may never
        // show. The session is asked to finish when it exists; without one nothing was recorded.
        if pendingStart != nil { return cancelPendingStart() }
        controller.stop()
    }

    func retryNotes(_ key: NoteKey) async throws {
        guard key.pluginID == pluginID else { throw NoteSourceError.notFound }
        guard let id = deps.meetingID(key) else { throw NoteSourceError.notFound }
        // One job at a time: the meeting's own job is fine (it gets the request through `regenerate`), another
        // meeting's is not.
        if deps.notesBusy(), !deps.hasNotesJob(id) { throw NoteSourceError.busy }
        // The contract: a retry is for notes that are `failed` or `partial`. Anything else (`none`, `ok`, `stale`)
        // has nothing to write again, so the press does nothing and writes nothing.
        guard let status = deps.notesStatus(id), status == .failed || status == .partial else { return }
        deps.regenerateNotes(id)
    }

    // MARK: The HUD's mapping

    /// How well the recording hears the call. A microphone that was never part of it (system audio only, or one
    /// that did not start) wins over the system track's own start problem.
    static func hearing(_ recording: MeetingHUDState.Recording) -> LiveRecordingStatus.Hearing {
        if !recording.recordsMicrophone || recording.unavailable.contains(.mic) { return .callOnly }
        if recording.unavailable.contains(.system) { return .microphoneOnly }
        return .everyone
    }

    /// The recording's warning, in the HUD's own order of the notices that have one. `noSystemAudio` of a system
    /// track that was never available is that start problem's `hearing`, not a warning.
    static func warning(_ recording: MeetingHUDState.Recording) -> LiveRecordingStatus.Warning? {
        if recording.lost.contains(.mic) { return .microphoneLost }
        if recording.lost.contains(.system) { return .callAudioMissing }
        if recording.noMicrophoneAudio, recording.recordsMicrophone { return .microphoneSilent }
        if recording.noSystemAudio, recording.recordsSystem, !recording.unavailable.contains(.system) {
            return .silence
        }
        return nil
    }

    /// The contract's reason for a HUD problem. `nothingHeard` is the discarded recording: the window keeps the
    /// user's own writing as a manual note.
    static func failure(_ problem: MeetingHUDState.Problem) -> LiveRecordingFailure {
        switch problem {
        case .modelMissing, .modelUnavailable: .modelMissing
        case .libraryUnavailable: .libraryUnavailable
        case .microphoneDenied: .microphoneDenied
        case .noAudioInput: .noAudioInput
        case .lowDiskAtStart: .lowDisk
        case .stillProcessing: .stillProcessing
        case .modelBeingRemoved: .modelBusy
        case .nothingHeard: .discarded
        case .couldNotStart, .failed: .other
        }
    }

    // MARK: State

    private func set(_ new: LiveRecordingStatus) {
        guard new != value else { return }
        value = new
        for continuation in continuations.values { continuation.yield(new) }
    }

    /// The recording's status from the last HUD state; `.starting` while the meeting has no Notes key yet.
    private func updateRecording() {
        guard let key = recordingKey, let since = startedAt, let recording = lastRecording else {
            return set(.starting)
        }
        set(.recording(key: key, since: since, hearing: Self.hearing(recording), warning: Self.warning(recording)))
    }

    /// The recording's key, looked up once per recording (a database read).
    private func resolvedKey() -> NoteKey? {
        if let recordingKey { return recordingKey }
        guard let id = controller?.meetingID, let key = deps.noteKey(id) else { return nil }
        recordingKey = key
        return key
    }

    private func recordingEnded() {
        failPendingStart()
        clearRecording()
        set(.idle)
    }

    private func clearRecording() {
        startedAt = nil
        recordingKey = nil
        lastRecording = nil
    }

    /// The recording really ran: the only way a waiting `start()` succeeds (`meetingRegistered`).
    private func settleStart() {
        guard let continuation = pendingStart else { return }
        pendingStart = nil
        continuation.resume()
    }

    /// Ends a `start()` that waits when the attempt is over without `meetingRegistered`: the HUD was hidden or
    /// the recording went on to finishing, so nothing runs for it. The window gets an error, not a success.
    private func failPendingStart() {
        guard let continuation = pendingStart else { return }
        pendingStart = nil
        continuation.resume(throwing: LiveRecordingFailure.other)
    }

    private func failStart(_ problem: MeetingHUDState.Problem) {
        guard let continuation = pendingStart else { return }
        pendingStart = nil
        suppressesNextMeeting = false
        // The HUD would ask whether to record the system audio only; the window says "Allow Microphone" instead,
        // so the attempt ends here rather than staying half started behind a HUD nobody sees.
        if case .microphoneDenied(offersSystemOnly: true) = problem,
            controller?.phase == .awaitingMicrophoneDecision
        {
            controller?.perform(.dismiss)
        }
        clearRecording()
        set(.idle)
        continuation.resume(throwing: Self.failure(problem))
    }

    /// Ends the attempt a waiting `start()` belongs to (the window's Stop, a cancelled task): a session that is
    /// already up is asked to finish — a session still starting finishes as soon as its start is done — and
    /// without one the attempt is cancelled. The waiting window gets `LiveRecordingFailure.other`.
    private func cancelPendingStart() {
        guard let continuation = pendingStart else { return }
        pendingStart = nil
        if let controller {
            switch controller.phase {
            case .preparing: controller.stop()
            case .awaitingMicrophoneDecision: controller.perform(.dismiss)
            default: break
            }
            // Nothing was recorded and no meeting will be made: the stop's answer must not reach a later one.
            if controller.phase == .idle { suppressesNextMeeting = false }
        }
        clearRecording()
        set(.idle)
        continuation.resume(throwing: LiveRecordingFailure.other)
    }
}

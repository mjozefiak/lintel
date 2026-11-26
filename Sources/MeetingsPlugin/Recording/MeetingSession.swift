import Foundation
import LintelKit
import LintelSpeech
import Synchronization
import os

/// One recording (spec: `MeetingSession`): two tracks (`mic`, `system`), each with its own voice activity
/// detector, cut into segments of at most 15 s that go to the speech engine through `SpeechEngineLease`
/// (priority `.background`) and into the library as they are transcribed. Every sample also goes to an
/// encrypted spool per track. The loop VAD to engine is a copy of `DictationSession`'s, not shared.
///
/// - The tracks must arrive aligned on one timeline (`SystemAudioSource` pads the track that starts later,
///   `TimelineAlignment`), so a track's sample index is its time since the common start.
/// - A segment that the track's own backlog (a minute of audio) refuses, that the lease hands back as `.spool`,
///   that fails to transcribe or that cannot be transcribed because the model is unavailable stays in the
///   spool and is transcribed after the meeting (the replay), while the state is `processing`.
/// - Audio is never deleted unless the whole transcript was transcribed and written (spec Q7): a segment that
///   still fails after the replay, or a failed database write, ends the meeting `incomplete` with the spool
///   kept; `failed` only when nothing is left that a later run could finish.
/// - Microphone segments wait until the system track is known up to their end (at most `micHoldLimit`), then
///   `EchoSuppressor` decides whether they are echoes of what the speakers played.
/// - Transcript text and audio never reach a log: only counts and durations.
actor MeetingSession {
    typealias Event = MeetingSessionEvent
    typealias Outcome = MeetingSessionOutcome

    /// A speech segment is cut at this length (the model's window is 15 s); never longer.
    static let longestSegment = 15 * AudioFormat.sampleRate
    /// What the detector can lag behind the store's end before it reports the start of speech: one pending
    /// partial chunk, the chunk that crossed the threshold and its padding.
    private static let detectorLookback = AudioFormat.sampleRate * 3 / 4
    /// A microphone segment is judged once the system track is known this long past its end (voice activity
    /// detection reports speech late).
    private static let echoSlackMs = 1_500
    /// System text older than this before the earliest possible microphone segment cannot echo into it.
    private static let echoWindowMs = 30_000
    private static let maxHeld = 50
    private static let maxSystemSegments = 500

    nonisolated let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation

    private let store: MeetingsStore
    private let keys: MeetingKeys
    private let spoolStorage: SpoolStorage
    /// Read when the meeting becomes `ready`: `plugins.meetings.keepAudio` at that moment decides.
    private let keepAudio: @Sendable () -> Bool
    private let engine: any SpeechEngine
    private let modelID: String
    private let modelFolder: URL
    private let lease: SpeechEngineLease
    private let keepWarm: @Sendable () -> Duration
    private let sleepAssertion: any SleepAssertion
    private let gate: MeetingSessionGate
    private let limits: MeetingSessionLimits
    private let freeSpace: SpoolWriter.FreeSpaceProvider
    private let echo: EchoSuppressor
    private let now: @Sendable () -> Date
    private let beforeReady: (@Sendable (Int64, UUID) async -> Void)?
    private let logger: Logger
    private let inputs: [(channel: AudioChannel, audio: any AudioInput)]
    private let makeVAD: @Sendable () -> any VoiceActivityDetector
    /// The shared language setting and this meeting's profile; every segment is sent with its options.
    private let language: MeetingLanguage
    let meetingUUID: UUID

    private(set) var state = MeetingSessionState.idle
    private(set) var meetingID: Int64?
    /// A `finish()` arrived while `start()` was still running (tests wait for it).
    var isFinishPending: Bool { pendingFinish }

    /// `meeting.source_bundle_id`: the app of the accepted suggestion, `nil` otherwise.
    private let sourceBundleID: String?
    private var tracks: [AudioChannel: TrackState] = [:]
    private var loadTask: Task<SpeechLease?, Never>?
    private var leaseHandle: SpeechLease?
    private var started = false
    private var finishTask: Task<Outcome, Never>?
    private var nextSegmentID = 0
    /// Microphone text waiting for the system track, sorted by start.
    private var held: [TrackSegment] = []
    private var systemSegments: [TrackSegment] = []
    private var pruneFloor = 0
    private var savedCount = 0
    private var failedSegments = 0
    private var replayedSegments = 0
    private var echoesDropped = 0
    private var echoesUnchecked = 0
    private var echoWarned = false
    private var writeFailures = 0
    private var databaseFailed = false
    /// Segments whose audio is intact in the spool but whose text is not in the library.
    private var keptSegments = 0
    private var lastSecond = 0
    private var limitSignalled = false
    private var lastDiskCheck = 0
    private var lastDiskCheckAt = Date.distantPast
    private var startedAt = Date.distantPast
    private var replayUnavailable = false
    /// Numbers only (see `CaptureCounters`); written by the actor, never from an audio callback.
    private var counters = CaptureCounters()
    private var audioGapWritten = false
    private let recordCounters: @Sendable (CaptureCounters) -> Void
    private var pendingFinish = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var heartbeatTask: Task<Void, Never>?
    private let sleep: @Sendable (Duration) async throws -> Void
    /// Whether a microphone that does not start is started again (false for a system-audio-only recording,
    /// whose microphone is `UnavailableAudioInput`).
    private let retriesMicrophone: Bool
    /// The default input as a log line (name, UID, sample rate, channels); read when the microphone fails.
    private let inputDiagnostics: @Sendable () -> String
    private let defaultInputChanges: (@Sendable () -> AsyncStream<Void>)?
    /// The microphone that has not recorded a sample yet: its start failed, its spool stays open and it
    /// becomes a track when a later attempt works.
    private var pendingMic: PendingMicrophone?
    private var reviving = false
    private var micUnavailableAnnounced = false
    private var micRetryTask: Task<Void, Never>?
    private var inputWatchTask: Task<Void, Never>?

    private let limitSamples: Int
    private let warningSamples: Int
    private let preRollSamples: Int
    private let postRollSamples: Int

    /// - Parameters:
    ///   - mic: the microphone; `system` the system audio (`nil` records the microphone only).
    ///   - makeVAD: called once per track.
    ///   - now, sleep: the wall clock and the wait of the heartbeat that enforces the limits when no audio
    ///     arrives; tests drive both.
    ///   - beforeReady: runs while the state is `processing`, after the transcript is complete and before the
    ///     meeting becomes `ready` and its spool is deleted (diarization plugs in here).
    init(
        store: MeetingsStore, keys: MeetingKeys, spool: SpoolStorage, mic: any AudioInput,
        system: (any AudioInput)?, makeVAD: @escaping @Sendable () -> any VoiceActivityDetector,
        engine: any SpeechEngine, modelID: String, modelFolder: URL, lease: SpeechEngineLease = .shared,
        keepWarm: @escaping @Sendable () -> Duration = { .seconds(600) }, sleepAssertion: any SleepAssertion,
        gate: MeetingSessionGate, limits: MeetingSessionLimits = MeetingSessionLimits(),
        freeSpace: @escaping SpoolWriter.FreeSpaceProvider = { try SpoolStorage.systemFreeSpace(at: $0) },
        echo: EchoSuppressor = EchoSuppressor(), uuid: UUID = UUID(), now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        beforeReady: (@Sendable (Int64, UUID) async -> Void)? = nil,
        sourceBundleID: String? = nil, keepAudio: @escaping @Sendable () -> Bool = { false },
        recordCounters: @escaping @Sendable (CaptureCounters) -> Void = { _ in },
        retriesMicrophone: Bool = true, inputDiagnostics: @escaping @Sendable () -> String = { "" },
        defaultInputChanges: (@Sendable () -> AsyncStream<Void>)? = nil,
        language: MeetingLanguage = MeetingLanguage(settings: FixedSpeechLanguageSettings()),
        logger: Logger = Logger(subsystem: "com.lintelapp", category: "meetings")
    ) {
        self.language = language
        self.retriesMicrophone = retriesMicrophone
        self.inputDiagnostics = inputDiagnostics
        self.defaultInputChanges = defaultInputChanges
        self.recordCounters = recordCounters
        self.keepAudio = keepAudio
        self.sourceBundleID = sourceBundleID
        (events, continuation) = AsyncStream.makeStream(of: Event.self, bufferingPolicy: .unbounded)
        self.store = store
        self.keys = keys
        spoolStorage = spool
        self.engine = engine
        self.modelID = modelID
        self.modelFolder = modelFolder
        self.lease = lease
        self.keepWarm = keepWarm
        self.sleepAssertion = sleepAssertion
        self.gate = gate
        self.limits = limits
        self.freeSpace = freeSpace
        self.echo = echo
        meetingUUID = uuid
        self.now = now
        self.sleep = sleep
        self.beforeReady = beforeReady
        self.logger = logger
        self.makeVAD = makeVAD
        var list: [(AudioChannel, any AudioInput)] = [(.mic, mic)]
        if let system { list.append((.system, system)) }
        inputs = list
        preRollSamples = MeetingSessionLimits.samples(in: limits.segmentPreRoll)
        postRollSamples = MeetingSessionLimits.samples(in: limits.segmentPostRoll)
        limitSamples = MeetingSessionLimits.samples(in: limits.maximumDuration)
        warningSamples = max(
            0,
            MeetingSessionLimits.samples(in: limits.maximumDuration)
                - MeetingSessionLimits.samples(in: limits.warningBefore))
    }

    // MARK: Start

    /// Creates the library entry and the spool, takes the speech model in the background and starts the
    /// audio. Throws (leaving nothing behind) when another session is active, the disk has too little space or
    /// no audio source starts; a failed start can be retried on the same session and its events keep flowing.
    @discardableResult
    func start() async throws -> Int64 {
        guard !started else { throw MeetingSessionError.alreadyStarted }
        guard gate.tryAcquire() else { throw MeetingSessionError.anotherSessionActive }
        started = true
        do {
            let writers = try createSpool()
            let id = try insertMeeting(cleaningUp: writers)
            meetingID = id
            sleepAssertion.hold(reason: "Lintel is recording a meeting")
            startModelLoad()
            try await startAudio(writers: writers)
        } catch {
            await abortStart()
            wakeStartWaiters()
            throw error
        }
        setState(.recording)
        startHeartbeat()
        startMicrophoneRecovery()
        // A finish requested while starting, or the only track having ended meanwhile, takes effect now.
        if pendingFinish || !tracks.values.contains(where: \.alive) { _ = beginFinish() }
        wakeStartWaiters()
        return meetingID ?? 0
    }

    private func wakeStartWaiters() {
        let waiters = startWaiters
        startWaiters = []
        for waiter in waiters { waiter.resume() }
    }

    private func createSpool() throws -> [AudioChannel: SpoolWriter] {
        if inputs.count == 2 {
            let pair = try SpoolWriter.createPair(
                in: spoolStorage, meeting: meetingUUID, keys: keys, minimumFreeBytes: limits.startFreeBytes,
                freeSpace: freeSpace)
            return [.mic: pair.mic, .system: pair.system]
        }
        let mic = try SpoolWriter.create(
            in: spoolStorage, meeting: meetingUUID, track: .mic, keys: keys, minimumFreeBytes: limits.startFreeBytes,
            freeSpace: freeSpace)
        return [.mic: mic]
    }

    private func insertMeeting(cleaningUp writers: [AudioChannel: SpoolWriter]) throws -> Int64 {
        do {
            return try store.insertMeeting(
                uuid: SpoolStorage.name(of: meetingUUID), startedAt: now(), speechModelID: modelID,
                sourceBundleID: sourceBundleID)
        } catch {
            for writer in writers.values { try? writer.abandon() }
            _ = spoolStorage.removeSpools(forMeetings: [SpoolStorage.name(of: meetingUUID)])
            throw MeetingSessionError.database
        }
    }

    /// Takes the lease, telling the HUD when the model has to be loaded.
    private func acquireLease() async throws -> SpeechLease {
        let loading = LoadFlag()
        let continuation = continuation
        let handle = try await lease.acquire(
            modelID: modelID, folder: modelFolder, engine: engine, priority: .background, keepWarm: keepWarm,
            onLoading: {
                loading.set()
                continuation.yield(.loadingModel)
            })
        if loading.value { continuation.yield(.modelLoaded) }
        return handle
    }

    private func noteModelUnavailable(busy: Bool) {
        if busy { counters.modelBusy += 1 } else { counters.modelUnavailable += 1 }
    }

    private func startModelLoad() {
        let continuation = continuation
        let logger = logger
        loadTask = Task { [weak self] in
            do {
                guard let self else { return nil }
                return try await self.acquireLease()
            } catch {
                let busy = (error as? ModelLeaseError) == .busy
                await self?.noteModelUnavailable(busy: busy)
                logger.error("Meeting speech model unavailable (busy: \(busy, privacy: .public))")
                if !Task.isCancelled { continuation.yield(.modelUnavailable(busy: busy)) }
                return nil
            }
        }
    }

    private func startAudio(writers: [AudioChannel: SpoolWriter]) async throws {
        let attemptedAt = now()
        for input in inputs {
            let channel = input.channel
            let continuation = continuation
            let levelGate = LevelGate()
            let onLevel = { @Sendable (level: Float) in
                if levelGate.isOpen { _ = continuation.yield(.level(channel, level)) }
            }
            observeFallback(of: input.audio, channel: channel)
            do {
                let stream = try await input.audio.start(onLevel: onLevel)
                let track = TrackState(channel: channel, audio: input.audio, vad: makeVAD())
                track.levelGate = levelGate
                track.onLevel = onLevel
                track.spool = writers[channel]
                track.lastAudioAt = now()
                tracks[channel] = track
                consume(track, stream)
                reportFallback(of: input.audio, channel: channel)
            } catch {
                logStartFailure(channel, error, attempt: nil)
                if channel == .mic, retriesMicrophone {
                    // Kept for a later attempt (`startMicrophoneRecovery`); the HUD hears about it only when
                    // those fail, so a start that works on the second try shows no warning.
                    pendingMic = PendingMicrophone(
                        audio: input.audio, spool: writers[channel], levelGate: levelGate, onLevel: onLevel,
                        attemptedAt: attemptedAt)
                } else {
                    continuation.yield(.trackUnavailable(channel))
                    if let writer = writers[channel] { try? writer.abandon() }
                }
            }
        }
        if tracks.isEmpty {
            pendingMic = nil
            throw MeetingSessionError.noAudioInput
        }
        startedAt = now()
        lastDiskCheckAt = startedAt
    }

    private func consume(_ track: TrackState, _ stream: AsyncStream<[Float]>) {
        track.generation += 1
        let generation = track.generation
        track.consume = Task { [weak self] in
            for await chunk in stream { await self?.receive(track, chunk) }
            await self?.streamEnded(track, generation: generation)
        }
    }

    /// Undoes a start that failed: nothing stays in the library or in the spool. The event stream stays open
    /// so that a retried start reports on it; it ends with the session's `finish`.
    private func abortStart() async {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        pendingMic = nil
        for track in tracks.values {
            track.consume?.cancel()
            await track.audio.stop()
        }
        tracks = [:]
        let load = loadTask
        loadTask = nil
        load?.cancel()
        await load?.value?.release()
        if let id = meetingID {
            do {
                try store.deleteMeetings([id])
            } catch {
                logger.error("An aborted meeting could not be removed from the library")
            }
        }
        meetingID = nil
        _ = spoolStorage.removeSpools(forMeetings: [SpoolStorage.name(of: meetingUUID)])
        sleepAssertion.release()
        gate.release()
        started = false
        pendingFinish = false
        nextSegmentID = 0
    }

    // MARK: Microphone recovery

    /// Tells the HUD when the microphone the user chose was not there and the system's input is used instead.
    /// The choice itself stays in Settings (the next recording tries it again).
    private func reportFallback(of audio: any AudioInput, channel: AudioChannel) {
        guard channel == .mic, let fallback = (audio as? any InputFallbackReporting)?.fallback else { return }
        let input = inputDiagnostics()
        logger.notice(
            "The chosen microphone is not available; recording from the default input: \(input, privacy: .public)")
        continuation.yield(.microphoneFallback(requested: fallback.requestedName, using: fallback.usingName))
    }

    /// The capture can move to the default input (or back) by itself while it records, when the chosen device is
    /// unplugged (or plugged in again) during an audio configuration change: the HUD hears about it.
    private func observeFallback(of audio: any AudioInput, channel: AudioChannel) {
        guard channel == .mic else { return }
        let continuation = continuation
        (audio as? any InputFallbackReporting)?.setFallbackHandler { fallback in
            if let fallback {
                continuation.yield(
                    .microphoneFallback(requested: fallback.requestedName, using: fallback.usingName))
            } else {
                continuation.yield(.microphoneFallbackEnded)
            }
        }
    }

    private func logStartFailure(_ channel: AudioChannel, _ error: any Error, attempt: Int?) {
        let kind = String(describing: error)
        let input = inputDiagnostics()
        let suffix = attempt.map { " (retry \($0) of \(limits.startRetryAttempts))" } ?? ""
        logger.error(
            "Audio track \(channel.rawValue, privacy: .public) did not start\(suffix, privacy: .public): \(kind, privacy: .public); default input: \(input, privacy: .public)"
        )
    }

    /// The microphone track that is not recording and could be started: the one that never started, or one
    /// that was lost.
    private func microphoneToRevive() -> MicrophoneRevival? {
        if let pendingMic { return .pending(pendingMic) }
        if let track = tracks[.mic], !track.alive, !track.resuming { return .lost(track) }
        return nil
    }

    /// A microphone that did not start is tried again a few times in the first seconds, and again whenever the
    /// system's default input changes (a Bluetooth headset connecting or switching profile).
    private func startMicrophoneRecovery() {
        guard retriesMicrophone else { return }
        if pendingMic != nil {
            micRetryTask = Task { [weak self] in
                // The first retry also waits: a Bluetooth headset that is switching profile needs a moment.
                _ = await self?.reviveMicrophone(attempts: self?.limits.startRetryAttempts ?? 0, waitFirst: true)
            }
        }
        if let makeChanges = defaultInputChanges {
            let changes = makeChanges()
            inputWatchTask = Task { [weak self] in
                for await _ in changes {
                    guard let self, !Task.isCancelled else { return }
                    await self.defaultInputChanged()
                }
            }
        }
    }

    private func defaultInputChanged() async {
        guard state == .recording, finishTask == nil else { return }
        let input = inputDiagnostics()
        logger.notice("The default input changed: \(input, privacy: .public)")
        guard microphoneToRevive() != nil else { return }
        // The new device needs a moment before it answers.
        do { try await sleep(limits.startRetryDelay) } catch { return }
        _ = await reviveMicrophone(attempts: limits.startRetryAttempts)
    }

    /// "Spróbuj ponownie": starts a microphone that is not recording. Returns whether it records now.
    @discardableResult
    func retryMicrophone() async -> Bool {
        await reviveMicrophone(attempts: limits.startRetryAttempts)
    }

    /// Starts the microphone that is not recording, up to `attempts` times with `startRetryDelay` between
    /// them. A late microphone lands at its real place on the timeline: the time it was missing is filled
    /// with silence in full (not capped like an interruption's gap), so it stays aligned with the system
    /// track for the echo check and the order of the transcript. Returns whether it records now.
    private func reviveMicrophone(attempts: Int, waitFirst: Bool = false) async -> Bool {
        guard retriesMicrophone, !reviving, state == .recording, finishTask == nil,
            let target = microphoneToRevive()
        else { return false }
        reviving = true
        defer { reviving = false }
        for attempt in 1...max(1, attempts) {
            if attempt > 1 || waitFirst {
                do { try await sleep(limits.startRetryDelay) } catch { return false }
            }
            guard state == .recording, finishTask == nil, microphoneToRevive()?.identity == target.identity else {
                return false
            }
            observeFallback(of: target.audio, channel: .mic)
            do {
                let stream = try await target.audio.start(onLevel: target.onLevel ?? { _ in })
                guard state == .recording, finishTask == nil else {
                    await target.audio.stop()
                    return false
                }
                await adopt(target, stream: stream)
                let input = inputDiagnostics()
                logger.notice(
                    "Audio track mic started after retry \(attempt, privacy: .public); default input: \(input, privacy: .public)"
                )
                return true
            } catch {
                logStartFailure(.mic, error, attempt: attempt)
            }
        }
        if pendingMic != nil, !micUnavailableAnnounced {
            micUnavailableAnnounced = true
            continuation.yield(.trackUnavailable(.mic))
        }
        return false
    }

    /// Puts a started microphone into the recording, silence first for the time it was missing.
    private func adopt(_ target: MicrophoneRevival, stream: AsyncStream<[Float]>) async {
        let channel = AudioChannel.mic
        let track: TrackState
        switch target {
        case .lost(let lost):
            track = lost
        case .pending(let pending):
            track = TrackState(channel: channel, audio: pending.audio, vad: makeVAD())
            track.levelGate = pending.levelGate
            track.onLevel = pending.onLevel
            track.spool = pending.spool
            track.lastAudioAt = pending.attemptedAt
            pendingMic = nil
        }
        micUnavailableAnnounced = false
        track.alive = true
        // Blocks a stall check and `streamEnded` while the silence goes in.
        track.resuming = true
        tracks[channel] = track
        var remaining = Int(max(0, now().timeIntervalSince(track.lastAudioAt)) * Double(AudioFormat.sampleRate))
        track.lastAudioAt = now()
        if remaining > 0 {
            counters[channel].gapFillSamples += remaining
            noteAudioGap()
        }
        while remaining > 0, finishTask == nil, state == .recording {
            let count = min(remaining, 10 * AudioFormat.sampleRate)
            remaining -= count
            await receive(track, [Float](repeating: 0, count: count))
        }
        track.resuming = false
        guard finishTask == nil, state == .recording else {
            await track.audio.stop()
            return
        }
        track.lastAudioAt = now()
        track.levelGate.open()
        consume(track, stream)
        counters[channel].resumes += 1
        continuation.yield(.trackResumed(channel))
        // After `trackResumed`, which clears an earlier fallback notice: this input may be the chosen one again.
        reportFallback(of: track.audio, channel: channel)
    }

    // MARK: Heartbeat

    /// The limits and the stalled-stream check are normally driven by arriving audio; this wall-clock beat makes
    /// them work when the audio stops arriving without the stream ending.
    private func startHeartbeat() {
        let interval = limits.heartbeat
        let sleep = sleep
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await sleep(interval) } catch { return }
                guard let self, !Task.isCancelled else { return }
                await self.heartbeatTick()
            }
        }
    }

    private func heartbeatTick() async {
        guard state == .recording, finishTask == nil else { return }
        let current = now()
        if current.timeIntervalSince(startedAt) >= MeetingSessionLimits.seconds(limits.maximumDuration),
            !limitSignalled
        {
            limitSignalled = true
            continuation.yield(.limitReached)
            requestFinish()
            return
        }
        refreshCaptureStats()
        let stall = MeetingSessionLimits.seconds(limits.stallTimeout)
        for track in tracks.values where track.alive && current.timeIntervalSince(track.lastAudioAt) >= stall {
            await recoverOrLose(track, reason: "no audio for \(Int(stall)) s")
        }
        if finishTask == nil,
            current.timeIntervalSince(lastDiskCheckAt) >= MeetingSessionLimits.seconds(limits.diskCheckEvery)
        {
            lastDiskCheckAt = current
            checkDisk()
        }
    }

    // MARK: Audio

    private func receive(_ track: TrackState, _ chunk: [Float]) async {
        let channel = track.channel
        guard tracks[channel] === track, track.alive, !chunk.isEmpty else { return }
        track.store.append(chunk)
        track.received = track.store.count
        counters[channel].recordedSamples += chunk.count
        track.lastAudioAt = now()
        if let writer = track.spool, !track.spoolFailed {
            do {
                try writer.append(chunk.map(Self.int16))
            } catch {
                track.spoolFailed = true
                logger.error("Spool of \(channel.rawValue, privacy: .public) failed")
                continuation.yield(.spoolFailed(channel))
            }
        }
        do {
            let wasOpen = track.speechStart != nil
            let events = try await track.vad.process(chunk)
            let opened = events.contains { $0.kind == .speechStart }
            recordProbabilities(await track.vad.drainProbabilities(), of: track, open: wasOpen || opened)
            for event in events {
                switch event.kind {
                case .speechStart:
                    if track.speechStart == nil {
                        track.speechStart = event.sampleIndex
                        counters[channel].vadSegmentsOpened += 1
                    }
                case .speechEnd:
                    if track.speechStart != nil {
                        counters[channel].vadSegmentsClosed += 1
                        // A range that outgrew the window (the end is reported late) is cut first.
                        cutWhileTooLong(track, upTo: event.sampleIndex)
                        if let start = track.speechStart {
                            closeSegment(track, start..<max(start, event.sampleIndex))
                        }
                        track.speechStart = nil
                    } else {
                        counters[channel].vadUnmatchedEnds += 1
                    }
                }
            }
        } catch {
            logger.error("Voice activity detection failed on \(channel.rawValue, privacy: .public)")
        }
        // Never a segment longer than the model's window.
        cutWhileTooLong(track, upTo: track.store.count)
        // Keep what a later range can still be widened into: the pre-roll before its start, and when no speech is
        // open the stretch the detector reports late.
        track.store.discard(before: (track.speechStart ?? track.store.count - Self.detectorLookback) - preRollSamples)
        progress()
        commitReady(force: false)
    }

    /// Cuts the open speech at the model's window while it reaches more than that far (up to `end`), so no segment
    /// is longer than the window.
    private func cutWhileTooLong(_ track: TrackState, upTo end: Int) {
        while let start = track.speechStart, end - start > Self.longestSegment {
            counters[track.channel].hardCuts += 1
            let cut = SegmentWindow.cutEnd(start: start, notBefore: track.sentUntil, preRoll: preRollSamples)
            closeSegment(track, start..<cut, endsInCut: true)
            track.speechStart = cut
        }
    }

    /// Counts the chunks the detector judged since the last batch. `open` is whether speech was open while the
    /// batch was processed; a chunk that came close to the threshold without opening speech is a near miss.
    private func recordProbabilities(_ probabilities: [Float], of track: TrackState, open: Bool) {
        guard !probabilities.isEmpty else { return }
        var stats = counters[track.channel].segmentingStats
        for probability in probabilities where probability.isFinite {
            stats.add(probability)
            let nearMiss =
                !open && probability >= SegmentingStats.nearMissFloor && probability < limits.vadEntryThreshold
            if nearMiss {
                stats.nearMissChunks += 1
                track.nearMissRun += 1
                if track.nearMissRun == 1 { stats.nearMissRuns += 1 }
                stats.longestNearMissRun = max(stats.longestNearMissRun, track.nearMissRun)
            } else {
                track.nearMissRun = 0
            }
        }
        counters[track.channel].segmentingStats = stats
    }

    private static func int16(_ sample: Float) -> Int16 {
        Int16(max(-1, min(1, sample)) * 32_767)
    }

    private func streamEnded(_ track: TrackState, generation: Int) async {
        guard tracks[track.channel] === track, track.alive, track.generation == generation, !track.resuming
        else { return }
        guard finishTask == nil, state == .recording || state == .idle else {
            track.alive = false
            return
        }
        await recoverOrLose(track, reason: "stream ended")
    }

    /// The stream of a track ended or stalled while recording (the input device or its format changed, the
    /// Mac slept, the permission went). The input is started again a few times; only when that fails does
    /// the track count as lost. The gap is filled with silence so the track stays on the common timeline.
    private func recoverOrLose(_ track: TrackState, reason: String) async {
        let channel = track.channel
        guard track.alive, !track.resuming else { return }
        logger.notice(
            "Audio track \(channel.rawValue, privacy: .public) interrupted: \(reason, privacy: .public)")
        counters[channel].interruptions += 1
        let attempts = limits.resumeAttempts
        guard attempts > 0, state == .recording else {
            await track.audio.stop()
            lose(track, reason: reason)
            return
        }
        track.resuming = true
        track.levelGate.close()
        continuation.yield(.trackInterrupted(channel))
        track.consume?.cancel()
        await track.audio.stop()
        for attempt in 1...attempts {
            if limits.resumeDelay > .zero {
                // Unstructured on purpose: when the stream ended, this runs inside the track's own consume
                // task, which was just cancelled, and a cancelled sleep would return at once.
                let delay = limits.resumeDelay
                await Task { try? await Task.sleep(for: delay) }.value
            }
            guard tracks[channel] === track, track.alive, finishTask == nil, state == .recording else {
                track.resuming = false
                return
            }
            observeFallback(of: track.audio, channel: channel)
            do {
                let stream = try await track.audio.start(onLevel: track.onLevel ?? { _ in })
                guard tracks[channel] === track, finishTask == nil, state == .recording else {
                    await track.audio.stop()
                    track.resuming = false
                    return
                }
                let gap = min(
                    max(0, now().timeIntervalSince(track.lastAudioAt)),
                    MeetingSessionLimits.seconds(limits.longestGapFill))
                let silence = Int(gap * Double(AudioFormat.sampleRate))
                track.resuming = false
                if silence > 0 {
                    counters[channel].gapFillSamples += silence
                    noteAudioGap()
                    await receive(track, [Float](repeating: 0, count: silence))
                }
                guard finishTask == nil, state == .recording else {
                    await track.audio.stop()
                    return
                }
                track.lastAudioAt = now()
                track.levelGate.open()
                consume(track, stream)
                logger.notice(
                    "Audio track \(channel.rawValue, privacy: .public) resumed after attempt \(attempt, privacy: .public)"
                )
                counters[channel].resumes += 1
                continuation.yield(.trackResumed(channel))
                reportFallback(of: track.audio, channel: channel)
                return
            } catch {
                logger.error(
                    "Audio track \(channel.rawValue, privacy: .public) restart \(attempt, privacy: .public) of \(attempts, privacy: .public) failed"
                )
            }
        }
        track.resuming = false
        lose(track, reason: "\(reason); \(attempts) restarts failed")
    }

    /// A track is gone while recording (or while starting): its open speech is closed, the other track carries
    /// on, and when none is left the meeting ends.
    private func lose(_ track: TrackState, reason: String) {
        logger.error(
            "Audio track \(track.channel.rawValue, privacy: .public) lost: \(reason, privacy: .public)")
        track.alive = false
        track.levelGate.close()
        counters[track.channel].lost += 1
        continuation.yield(.trackLost(track.channel))
        if let start = track.speechStart {
            counters[track.channel].forcedCloses += 1
            closeSegment(track, start..<track.store.count)
            track.speechStart = nil
        }
        // While starting, `start()` finishes the session once it knows no track is left.
        if state == .recording, !tracks.values.contains(where: \.alive) { requestFinish() }
        commitReady(force: false)
    }

    /// Elapsed time, the 3 h limit and the free-space check, driven by the audio that arrives.
    private func progress() {
        let samples = tracks.values.map(\.received).max() ?? 0
        let second = samples / AudioFormat.sampleRate
        if second > lastSecond {
            lastSecond = second
            continuation.yield(.elapsed(seconds: second))
            if warningSamples > 0, samples >= warningSamples {
                continuation.yield(
                    .limitApproaching(secondsLeft: max(0, (limitSamples - samples) / AudioFormat.sampleRate)))
            }
        }
        if samples >= limitSamples, !limitSignalled {
            limitSignalled = true
            continuation.yield(.limitReached)
            requestFinish()
        }
        let interval = max(1, MeetingSessionLimits.samples(in: limits.diskCheckEvery))
        if finishTask == nil, samples - lastDiskCheck >= interval {
            lastDiskCheck = samples
            checkDisk()
        }
    }

    private func checkDisk() {
        do {
            if try freeSpace(spoolStorage.root) < limits.stopFreeBytes {
                logger.error("Low disk space while recording")
                continuation.yield(.lowDisk)
                requestFinish()
            }
        } catch {
            // The check could not be made; the spool's own write errors still stop a full disk.
            logger.error("The free space could not be read")
        }
    }

    // MARK: Segments

    private enum SegmentOutcome: Sendable {
        case text(String)
        /// No speech model to take the segment.
        case deferred
        /// The background queue was full (`.spool` result).
        case spool
        case failed
    }

    fileprivate struct Job {
        let id: Int
        let range: Range<Int>
        let samples: [Float]
    }

    /// Hands a closed segment to the track's worker. A track has one worker, so segments reach the lease in the
    /// order they were spoken; when the worker's backlog already holds a minute of audio the segment waits in
    /// the spool instead (the replay transcribes it after the meeting), which keeps memory bounded.
    ///
    /// The range the detector reports is widened by the pre- and post-roll (`SegmentWindow`) before anything is
    /// sliced, timed, deferred or replayed, so the transcript, the spool replay and the timeline agree.
    /// `endsInCut`: the range ends because the model's window is full and speech goes on; the next piece starts
    /// right there, so nothing is added after it.
    private func closeSegment(_ track: TrackState, _ detected: Range<Int>, endsInCut: Bool = false) {
        let range = SegmentWindow.widened(
            detected, notBefore: track.sentUntil, received: track.store.count, preRoll: preRollSamples,
            postRoll: endsInCut ? 0 : postRollSamples)
        track.sentUntil = max(track.sentUntil, range.upperBound)
        if !detected.isEmpty {
            counters[track.channel].segmentingStats.paddedSamples += range.count - detected.count
        }
        let samples = track.store.slice(range)
        guard !samples.isEmpty else {
            counters[track.channel].emptyRanges += 1
            return
        }
        if track.backlogSamples > 0, track.backlogSamples + samples.count > SpeechEngineLease.backgroundLimit {
            counters[track.channel].backlogDeferred += 1
            track.deferred.append(range)
            return
        }
        counters[track.channel].segmentsSent += 1
        counters[track.channel].speechSamplesSent += samples.count
        if samples.count < AudioFormat.sampleRate / 2 { counters[track.channel].shortSegments += 1 }
        let id = nextSegmentID
        nextSegmentID += 1
        track.backlogSamples += samples.count
        track.inflight[id] = Self.milliseconds(range.lowerBound)
        track.queue.append(Job(id: id, range: range, samples: samples))
        guard track.worker == nil else { return }
        let load = loadTask
        let logger = logger
        let language = language
        track.worker = Task { [weak self] in
            while let self, let job = await self.nextJob(track) {
                let outcome = await Self.transcribe(job.samples, load: load, language: language, logger: logger)
                await self.resolved(track, job, outcome)
            }
        }
    }

    private func nextJob(_ track: TrackState) -> Job? {
        guard !track.queue.isEmpty else {
            track.worker = nil
            return nil
        }
        return track.queue.removeFirst()
    }

    /// The options are read when the segment is sent, not when it was cut: a profile that settled meanwhile (or a
    /// list changed in Settings) applies to it.
    private static func transcribe(
        _ samples: [Float], load: Task<SpeechLease?, Never>?, language: MeetingLanguage, logger: Logger
    ) async -> SegmentOutcome {
        guard let handle = await load?.value else { return .deferred }
        do {
            switch try await handle.transcribe(
                samples, options: language.options(duration: Self.seconds(samples.count)))
            {
            case .transcript(let segment): return .text(segment.text)
            case .spool: return .spool
            }
        } catch {
            logger.error("A segment failed to transcribe")
            return .failed
        }
    }

    private func resolved(_ track: TrackState, _ job: Job, _ outcome: SegmentOutcome) {
        track.inflight[job.id] = nil
        track.backlogSamples -= job.samples.count
        switch outcome {
        case .text(let text):
            if Self.isBlank(text) {
                counters[track.channel].emptyResults += 1
            } else {
                counters[track.channel].textResults += 1
            }
            accept(track.channel, job.range, text)
        // A failed segment gets one more try from the spool after the meeting, like a deferred one.
        case .deferred:
            counters[track.channel].deferredNoModel += 1
            track.deferred.append(job.range)
        case .spool:
            counters[track.channel].spoolResults += 1
            track.deferred.append(job.range)
        case .failed:
            counters[track.channel].failedResults += 1
            track.deferred.append(job.range)
        }
        commitReady(force: false)
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func accept(_ channel: AudioChannel, _ range: Range<Int>, _ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        language.observe(trimmed, duration: Double(range.count) / Double(AudioFormat.sampleRate))
        let start = Int64(Self.milliseconds(range.lowerBound))
        let end = Int64(Self.milliseconds(range.upperBound))
        switch channel {
        case .system:
            let segment = TrackSegment(track: .system, startMs: start, endMs: end, text: trimmed)
            systemSegments.append(segment)
            save(segment)
        case .mic:
            let segment = TrackSegment(track: .microphone, startMs: start, endMs: end, text: trimmed)
            let index = held.firstIndex { $0.startMs > start } ?? held.endIndex
            held.insert(segment, at: index)
        }
    }

    private static func milliseconds(_ sample: Int) -> Int { sample * 1_000 / AudioFormat.sampleRate }

    /// A sample count as seconds (the length a request's options look at).
    private static func seconds(_ samples: Int) -> TimeInterval { Double(samples) / Double(AudioFormat.sampleRate) }

    /// Until when a track's text is final: the start of its earliest unfinished speech or deferred segment, the
    /// end of what it received while it lives, and for ever once it is dead and finished.
    private func horizonMs(_ channel: AudioChannel) -> Int {
        guard let track = tracks[channel] else { return .max }
        var horizon = track.alive ? Self.milliseconds(track.received) : .max
        if let start = track.speechStart { horizon = min(horizon, Self.milliseconds(start)) }
        for start in track.inflight.values { horizon = min(horizon, start) }
        for range in track.deferred { horizon = min(horizon, Self.milliseconds(range.lowerBound)) }
        return horizon
    }

    /// Writes the microphone segments the system track can no longer contradict, or that waited too long.
    /// `force` writes all of them (the end of the meeting); the echo check still uses every system segment
    /// there is, and a segment written without the system track known up to its end is counted and flagged.
    private func commitReady(force: Bool) {
        let horizon = horizonMs(.system)
        let mediaNow = Self.milliseconds(tracks.values.map(\.received).max() ?? 0)
        let holdLimit = Int(MeetingSessionLimits.seconds(limits.micHoldLimit) * 1_000)
        pruneSystemSegments()
        while let first = held.first {
            let complete = horizon == .max || horizon >= Int(first.endMs) + Self.echoSlackMs
            let aged = mediaNow - Int(first.endMs) >= holdLimit || held.count > Self.maxHeld
            guard force || complete || aged else { break }
            held.removeFirst()
            if !complete {
                echoesUnchecked += 1
                if !echoWarned {
                    echoWarned = true
                    continuation.yield(.echoMayRemain)
                }
            }
            if echo.isEcho(first, of: systemSegments) {
                echoesDropped += 1
            } else {
                save(first)
            }
        }
        pruneSystemSegments()
    }

    /// Drops system text no future microphone segment can overlap. The bound only moves forward: it follows
    /// the earliest microphone work still open (or waiting), never the segment last written.
    private func pruneSystemSegments() {
        var earliest = horizonMs(.mic)
        if let first = held.first { earliest = min(earliest, Int(first.startMs)) }
        if earliest == .max {
            systemSegments.removeAll()
            return
        }
        pruneFloor = max(pruneFloor, earliest - Self.echoWindowMs)
        systemSegments.removeAll { Int($0.endMs) < pruneFloor }
        if systemSegments.count > Self.maxSystemSegments {
            systemSegments.removeFirst(systemSegments.count - Self.maxSystemSegments)
        }
    }

    private func save(_ segment: TrackSegment) {
        guard let id = meetingID else { return }
        let channel: AudioChannel = segment.track == .system ? .system : .mic
        do {
            try store.insertSegment(
                meetingID: id, channel: channel, startMs: Int(segment.startMs), endMs: Int(segment.endMs),
                text: segment.text)
            savedCount += 1
            continuation.yield(.segmentSaved(channel, total: savedCount))
        } catch {
            logger.error("A segment could not be saved")
            writeFailures += 1
            // The audio is still in the spool, so a later run can write the text again.
            if let track = tracks[channel], !track.spoolFailed { keptSegments += 1 }
            if !databaseFailed {
                databaseFailed = true
                continuation.yield(.databaseWriteFailed)
            }
        }
    }

    // MARK: Finish

    private func requestFinish() {
        if state == .recording {
            _ = beginFinish()
        } else if started, state == .idle {
            pendingFinish = true
        }
    }

    private func beginFinish() -> Task<Outcome, Never> {
        if let task = finishTask { return task }
        let task = Task { await self.runFinish() }
        finishTask = task
        return task
    }

    /// Stops the audio, transcribes what is left (including what waited in the spool) and ends the meeting.
    /// Safe to call again, and from the limit, the disk check or the plugin being switched off: the first call
    /// does the work, the others get its result. Called while `start()` is still running, it waits for the start
    /// and then finishes.
    func finish() async -> Outcome {
        if let task = finishTask { return await task.value }
        if started, state == .idle {
            pendingFinish = true
            await withCheckedContinuation { startWaiters.append($0) }
            if let task = finishTask { return await task.value }
            return Outcome(result: .notStarted)
        }
        guard state == .recording else { return Outcome(result: .notStarted) }
        return await beginFinish().value
    }

    /// Asks a finish that is already running to stop at its next cancellation point (the app is quitting).
    /// Nothing is thrown away: the meeting ends `incomplete` and its spool stays for a later run. No effect
    /// before `finish()` has begun or after it is over.
    func cancelProcessing() {
        finishTask?.cancel()
    }

    private func runFinish() async -> Outcome {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        micRetryTask?.cancel()
        micRetryTask = nil
        inputWatchTask?.cancel()
        inputWatchTask = nil
        if let pending = pendingMic {
            // A microphone that never recorded has nothing to keep.
            try? pending.spool?.abandon()
            pendingMic = nil
        }
        setState(.finishing)
        if let id = meetingID {
            do {
                try store.setStatus(id, status: .processing)
            } catch {
                logger.error("The meeting could not be marked as processing")
            }
        }
        for track in tracks.values { await track.audio.stop() }
        for track in tracks.values { await track.consume?.value }
        refreshCaptureStats()
        for track in tracks.values {
            if let start = track.speechStart {
                counters[track.channel].forcedCloses += 1
                closeSegment(track, start..<track.store.count)
                track.speechStart = nil
            }
            track.alive = false
        }
        for track in tracks.values {
            while let worker = track.worker { await worker.value }
        }
        commitReady(force: false)
        for track in tracks.values { closeSpool(track) }
        sleepAssertion.release()

        setState(.processing)
        leaseHandle = await loadTask?.value
        await replayDeferred()
        commitReady(force: true)
        await releaseLease()

        let outcome = await conclude()
        gate.release()
        continuation.yield(.finished(outcome))
        continuation.finish()
        return outcome
    }

    private func closeSpool(_ track: TrackState) {
        guard let writer = track.spool else { return }
        do {
            try writer.close()
        } catch {
            if !track.spoolFailed { continuation.yield(.spoolFailed(track.channel)) }
            track.spoolFailed = true
        }
    }

    private func releaseLease() async {
        loadTask = nil
        let handle = leaseHandle
        leaseHandle = nil
        await handle?.release()
    }

    private var deferredCount: Int { tracks.values.reduce(0) { $0 + $1.deferred.count } }

    // MARK: Replay

    /// Transcribes, from the spool, the segments the backlog, the background queue or the missing model left
    /// waiting, and retries the ones that failed.
    private func replayDeferred() async {
        guard deferredCount > 0 else { return }
        if leaseHandle == nil {
            // The model was not available during the meeting: try once more now.
            do {
                leaseHandle = try await acquireLease()
            } catch {
                replayUnavailable = true
                logger.error("Speech model unavailable for the deferred segments")
                // What cannot be replayed later either (its spool is damaged) is lost; the rest stays deferred.
                for track in tracks.values where track.spoolFailed && !track.deferred.isEmpty {
                    failReplay(track, track.deferred[...])
                }
                return
            }
        }
        guard let handle = leaseHandle else { return }
        for channel in [AudioChannel.mic, .system] {
            guard let track = tracks[channel], !track.deferred.isEmpty else { continue }
            await replay(track, handle: handle)
        }
    }

    private func replay(_ track: TrackState, handle: SpeechLease) async {
        let ranges = track.deferred.sorted { $0.lowerBound < $1.lowerBound }
        guard !track.spoolFailed,
            let spoolTrack = SpoolTrack(rawValue: track.channel.rawValue),
            let reader = try? SpoolReader(
                file: spoolStorage.file(for: meetingUUID, track: spoolTrack), meeting: meetingUUID, track: spoolTrack,
                keys: keys)
        else {
            failReplay(track, ranges[...])
            return
        }
        var index = 0
        var position = 0
        var window: [Float] = []
        do {
            while index < ranges.count, let chunk = try reader.nextChunk() {
                window += chunk
                position += chunk.count
                while index < ranges.count, ranges[index].upperBound <= position {
                    await replayRange(
                        track, ranges[index], window: window, windowStart: position - window.count, handle)
                    index += 1
                }
                if index < ranges.count {
                    let drop = min(max(0, ranges[index].lowerBound - (position - window.count)), window.count)
                    window.removeFirst(drop)
                } else {
                    window = []
                }
            }
        } catch {
            logger.error("The spool of \(track.channel.rawValue, privacy: .public) could not be read")
            failReplay(track, ranges[index...])
            return
        }
        // The stream ended before the last ranges did (a damaged tail): transcribe what exists.
        while index < ranges.count {
            await replayRange(track, ranges[index], window: window, windowStart: position - window.count, handle)
            index += 1
        }
    }

    /// Audio that cannot be read back from the spool: lost for good, and counted as failed.
    private func failReplay(_ track: TrackState, _ remaining: ArraySlice<Range<Int>>) {
        failedSegments += remaining.count
        counters[track.channel].replayUnreadable += remaining.count
        let lost = Array(remaining)
        track.deferred.removeAll { lost.contains($0) }
        commitReady(force: false)
    }

    private func replayRange(
        _ track: TrackState, _ range: Range<Int>, window: [Float], windowStart: Int, _ handle: SpeechLease
    ) async {
        let from = max(0, range.lowerBound - windowStart)
        let to = min(window.count, range.upperBound - windowStart)
        guard from < to else {
            failReplay(track, [range][...])
            return
        }
        await replayOne(track, range, Array(window[from..<to]), handle: handle)
    }

    private func replayOne(_ track: TrackState, _ range: Range<Int>, _ samples: [Float], handle: SpeechLease) async {
        continuation.yield(.replaying(remaining: deferredCount))
        let outcome: SegmentOutcome
        do {
            switch try await handle.transcribe(
                samples, options: language.options(duration: Self.seconds(samples.count)))
            {
            case .transcript(let segment): outcome = .text(segment.text)
            case .spool: outcome = .failed
            }
        } catch {
            outcome = .failed
        }
        track.deferred.removeAll { $0 == range }
        switch outcome {
        case .text(let text):
            replayedSegments += 1
            if Self.isBlank(text) {
                counters[track.channel].replayedEmpty += 1
            } else {
                counters[track.channel].replayedText += 1
            }
            accept(track.channel, range, text)
        case .deferred, .spool, .failed:
            // Readable but not transcribable: stays in the spool for a later run.
            counters[track.channel].replayedFailed += 1
            failedSegments += 1
            keptSegments += 1
        }
        commitReady(force: false)
    }

    // MARK: Conclusion

    private func conclude() async -> Outcome {
        let samples = tracks.values.map(\.received).max() ?? 0
        let durationMs = Self.milliseconds(samples)
        var outcome = Outcome(
            result: .ready, meetingID: meetingID, segmentCount: savedCount, durationMs: durationMs,
            failedSegments: failedSegments, replayedSegments: replayedSegments, echoesDropped: echoesDropped,
            writeFailures: writeFailures, unfinishedSegments: deferredCount + keptSegments,
            echoesUnchecked: echoesUnchecked)
        let silent =
            savedCount == 0 && deferredCount == 0 && failedSegments == 0 && echoesDropped == 0 && writeFailures == 0
        let shortest = Int(limits.discardBelow.components.seconds) * 1_000
        let discardedID = meetingID
        if silent, durationMs < shortest, discardMeeting() {
            // The counters of a meeting thrown away as quiet are what tells whether something was lost.
            if let discardedID { publishCounters(id: discardedID, durationMs: durationMs, discarded: true) }
            outcome.result = .discarded
            outcome.meetingID = nil
            setState(.idle)
            return outcome
        }
        guard let id = meetingID else {
            outcome.result = .failed
            setState(.failed)
            return outcome
        }
        // Saved while the meeting is still `processing`, so no delete can run between this and `ready` and leave
        // an entry for a meeting that is gone.
        publishCounters(id: id, durationMs: durationMs)
        let endedAt = now()
        let unresolved = deferredCount + failedSegments + writeFailures
        if unresolved == 0 {
            await beforeReady?(id, meetingUUID)
            if Task.isCancelled {
                // The hook was cut short (e.g. diarization on quit): the audio stays for a later run.
                outcome.result = settleUnfinished(id, endedAt: endedAt, durationMs: durationMs, recoverable: true)
            } else if markReady(id, endedAt: endedAt, durationMs: durationMs) {
                setState(.ready)
            } else {
                // The meeting could not be marked ready, so the audio stays: it is not finished.
                outcome.result = settleUnfinished(id, endedAt: endedAt, durationMs: durationMs, recoverable: true)
            }
        } else {
            let recoverable = deferredCount + keptSegments > 0
            outcome.result = settleUnfinished(id, endedAt: endedAt, durationMs: durationMs, recoverable: recoverable)
        }
        logger.notice(
            "Meeting finished: \(self.savedCount, privacy: .public) segments, \(durationMs / 1_000, privacy: .public) s"
        )
        return outcome
    }

    // MARK: Capture counters

    /// Pulls the system source's statistics (numbers only) into the counters and, the first time the audio is
    /// known to have a hole, writes `meeting.audio_gap`.
    private func refreshCaptureStats() {
        for (channel, track) in tracks {
            guard let provider = track.audio as? any CaptureStatsProviding else { continue }
            let stats = provider.captureStats
            counters[channel].apply(stats)
            if stats.hasGap { noteAudioGap() }
        }
    }

    /// `audio_gap` on the live meeting: the column already exists, so nothing migrates. Seconds of gap would need
    /// a new column (#145).
    private func noteAudioGap() {
        guard !audioGapWritten, let id = meetingID else { return }
        do {
            try store.setAudioGap(id)
            audioGapWritten = true
        } catch {
            logger.error("The audio gap could not be written")
        }
    }

    private func publishCounters(id: Int64, durationMs: Int, discarded: Bool = false) {
        // A discarded meeting has no row any more: nothing to write `audio_gap` into.
        if !discarded { refreshCaptureStats() }
        counters.meetingID = id
        counters.durationMs = durationMs
        counters.audioGapWritten = audioGapWritten
        counters.discarded = discarded
        for line in CaptureDiagnostics.section(counters) where !line.isEmpty {
            logger.notice("Capture counters \(line, privacy: .public)")
        }
        recordCounters(counters)
    }

    /// Removes a silent short meeting. False (and nothing announced) when the row could not be removed.
    private func discardMeeting() -> Bool {
        if let id = meetingID {
            do {
                try store.deleteMeetings([id])
            } catch {
                logger.error("A silent meeting could not be removed from the library")
                return false
            }
        }
        _ = spoolStorage.removeSpools(forMeetings: [SpoolStorage.name(of: meetingUUID)])
        meetingID = nil
        logger.notice("Meeting discarded: nothing heard")
        continuation.yield(.nothingHeard)
        return true
    }

    /// The audio is deleted only after the status really is `ready` (spec Q7).
    private func markReady(_ id: Int64, endedAt: Date, durationMs: Int) -> Bool {
        do {
            try store.setStatus(id, status: .ready, endedAt: endedAt, durationMs: durationMs)
        } catch {
            logger.error("The meeting could not be marked ready; the audio is kept")
            return false
        }
        if keepAudio() {
            do {
                try store.setAudioState(id, state: .kept)
            } catch {
                logger.error("The audio state could not be updated after keeping the spool")
            }
            return true
        }
        _ = spoolStorage.removeSpools(forMeetings: [SpoolStorage.name(of: meetingUUID)])
        do {
            try store.setAudioState(id, state: .deleted)
        } catch {
            logger.error("The audio state could not be updated after deleting the spool")
        }
        return true
    }

    /// `incomplete` when a later run could still finish the meeting (something is saved, or audio waits in a
    /// readable spool); `failed` when nothing is left to build on, or the status cannot be written. The spool
    /// is kept either way.
    private func settleUnfinished(_ id: Int64, endedAt: Date, durationMs: Int, recoverable: Bool) -> Outcome.Result {
        let incomplete = savedCount > 0 || recoverable
        do {
            try store.setStatus(
                id, status: incomplete ? .incomplete : .failed, endedAt: endedAt, durationMs: durationMs)
        } catch {
            logger.error("The final status of the meeting could not be written")
            setState(.failed)
            return .failed
        }
        setState(incomplete ? .incomplete : .failed)
        return incomplete ? .incomplete : .failed
    }

    private func setState(_ new: MeetingSessionState) {
        state = new
        continuation.yield(.stateChanged(new))
    }
}

/// One audio track of a session; only the session's actor touches it.
private final class TrackState: @unchecked Sendable {
    let channel: AudioChannel
    let audio: any AudioInput
    let vad: any VoiceActivityDetector
    var spool: SpoolWriter?
    var spoolFailed = false
    var store = SampleStore()
    var speechStart: Int?
    var received = 0
    /// End of the audio already handed out as segments; a later range is never widened back into it.
    var sentUntil = 0
    var nearMissRun = 0
    var alive = true
    var lastAudioAt = Date.distantPast
    var inflight: [Int: Int] = [:]
    var deferred: [Range<Int>] = []
    var queue: [MeetingSession.Job] = []
    var backlogSamples = 0
    var worker: Task<Void, Never>?
    var consume: Task<Void, Never>?
    /// Bumped on every (re)start; a stream that ends after a newer one began is ignored.
    var generation = 0
    var resuming = false
    var levelGate = LevelGate()
    var onLevel: (@Sendable (Float) -> Void)?

    init(channel: AudioChannel, audio: any AudioInput, vad: any VoiceActivityDetector) {
        self.channel = channel
        self.audio = audio
        self.vad = vad
    }
}

/// A microphone whose first start failed: what a track needs, kept until a later attempt works.
private final class PendingMicrophone: @unchecked Sendable {
    let audio: any AudioInput
    let spool: SpoolWriter?
    let levelGate: LevelGate
    let onLevel: @Sendable (Float) -> Void
    let attemptedAt: Date

    init(
        audio: any AudioInput, spool: SpoolWriter?, levelGate: LevelGate,
        onLevel: @escaping @Sendable (Float) -> Void, attemptedAt: Date
    ) {
        self.audio = audio
        self.spool = spool
        self.levelGate = levelGate
        self.onLevel = onLevel
        self.attemptedAt = attemptedAt
    }
}

/// The microphone that `reviveMicrophone` starts: one that never started, or one that was lost.
private enum MicrophoneRevival {
    case pending(PendingMicrophone)
    case lost(TrackState)

    var audio: any AudioInput {
        switch self {
        case .pending(let pending): pending.audio
        case .lost(let track): track.audio
        }
    }

    var onLevel: (@Sendable (Float) -> Void)? {
        switch self {
        case .pending(let pending): pending.onLevel
        case .lost(let track): track.onLevel
        }
    }

    var identity: ObjectIdentifier {
        switch self {
        case .pending(let pending): ObjectIdentifier(pending)
        case .lost(let track): ObjectIdentifier(track)
        }
    }
}

/// Lets the meter of a track go dark while the track is interrupted or lost, even when the old capture still
/// delivers a last level.
private final class LevelGate: Sendable {
    private let flag = Mutex(true)
    var isOpen: Bool { flag.withLock { $0 } }
    func open() { flag.withLock { $0 = true } }
    func close() { flag.withLock { $0 = false } }
}

private final class LoadFlag: Sendable {
    private let flag = Mutex(false)
    var value: Bool { flag.withLock { $0 } }
    func set() { flag.withLock { $0 = true } }
}

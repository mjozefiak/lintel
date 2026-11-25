import Foundation
import LintelSpeech

/// The session's state in memory (spec: Phasing, "Stany"). `idle` has no row in the database; the others map
/// to `meeting.status` through `meetingStatus`.
enum MeetingSessionState: Equatable, Sendable {
    case idle
    case recording
    case finishing
    case processing
    case ready
    /// The recording could not be finished (the speech model was unavailable for the deferred segments); the
    /// spool is kept and a later run can complete it.
    case incomplete
    case failed

    var meetingStatus: MeetingStatus? {
        switch self {
        case .idle: nil
        case .recording: .recording
        case .finishing, .processing: .processing
        case .ready: .ready
        case .incomplete: .incomplete
        case .failed: .failed
        }
    }

    var isTerminal: Bool { self == .ready || self == .incomplete || self == .failed }
}

/// Everything the HUD wants to know while a meeting runs. Carries counts and durations, never text or audio.
enum MeetingSessionEvent: Equatable, Sendable {
    case stateChanged(MeetingSessionState)
    /// A 0...1 loudness of one track's latest chunk.
    case level(AudioChannel, Float)
    /// Whole seconds recorded so far.
    case elapsed(seconds: Int)
    /// The speech model is not in memory yet and is being loaded; recording already runs.
    case loadingModel
    case modelLoaded
    /// The speech model could not be taken; `busy` when another model is in use. Segments wait in the spool.
    case modelUnavailable(busy: Bool)
    /// The microphone the user chose is not available (unplugged), so the recording uses the system's input
    /// (`InputFallback`): at the start, or after the device went away during the recording. The names are for the
    /// HUD only; either can be unknown.
    case microphoneFallback(requested: String?, using: String?)
    /// The chosen microphone is recording again (it was plugged in during an audio configuration change).
    case microphoneFallbackEnded
    /// A track could not be started at the beginning (the session continues with the other one).
    case trackUnavailable(AudioChannel)
    /// A track ended while recording (device unplugged, permission revoked); the other one carries on.
    case trackLost(AudioChannel)
    /// A track's stream ended or stalled (input device or format changed, sleep); the session is trying to
    /// start it again. The track's meter goes dark. It ends in `trackResumed` or, when every attempt fails,
    /// `trackLost`.
    case trackInterrupted(AudioChannel)
    /// An interrupted track is recording again; the gap was filled with silence so the timeline holds.
    case trackResumed(AudioChannel)
    /// A segment was written to the library; `total` is the number of segments saved so far.
    case segmentSaved(AudioChannel, total: Int)
    /// The spool of a track failed; the transcript is still being written.
    case spoolFailed(AudioChannel)
    case databaseWriteFailed
    case lowDisk
    case limitApproaching(secondsLeft: Int)
    case limitReached
    /// A microphone segment was written without the system track being known up to its end (the system
    /// transcription was late or missing), so an echo of the speakers may remain in the transcript.
    case echoMayRemain
    /// Segments are being transcribed from the spool after the meeting; `remaining` is how many are left.
    case replaying(remaining: Int)
    /// The meeting was too short and silent: nothing was stored (message "Nic nie usłyszano").
    case nothingHeard
    case finished(MeetingSessionOutcome)
}

struct MeetingSessionOutcome: Equatable, Sendable {
    enum Result: Equatable, Sendable {
        case ready
        case incomplete
        case failed
        /// Shorter than the minimum and without speech: no database row remains.
        case discarded
        /// `finish()` was called on a session that never started.
        case notStarted
    }

    var result: Result
    var meetingID: Int64?
    var segmentCount = 0
    var durationMs = 0
    /// Segments that could not be transcribed.
    var failedSegments = 0
    /// Segments that went through the spool after the meeting (the background queue was full).
    var replayedSegments = 0
    /// Microphone segments dropped as echoes of the system track.
    var echoesDropped = 0
    /// Segments that could not be written to the library (the spool is kept, the meeting is `incomplete`).
    var writeFailures = 0
    /// Segments still waiting in the spool for a later run ("Dokończ"): refused, failed or not yet transcribed.
    var unfinishedSegments = 0
    /// Microphone segments written without the echo check having the whole system track (possible duplicates).
    var echoesUnchecked = 0
}

enum MeetingSessionError: Error, Equatable {
    case alreadyStarted
    /// Another session holds the gate.
    case anotherSessionActive
    /// No audio source could be started.
    case noAudioInput
    case database
}

/// Limits and thresholds of a session. The defaults are the spec's; tests shorten them.
struct MeetingSessionLimits: Sendable {
    /// The recording ends by itself after this long (spec: 3 h).
    var maximumDuration: Duration = .seconds(3 * 3600)
    /// The countdown starts this long before the end (spec: from 2 h 50 min).
    var warningBefore: Duration = .seconds(10 * 60)
    /// A meeting shorter than this without any speech is discarded (spec: 15 s).
    var discardBelow: Duration = .seconds(15)
    /// Free space needed to start (spec: 1.5 GB).
    var startFreeBytes: Int64 = SpoolFormat.minimumFreeBytes
    /// Below this the recording ends gracefully (spec: 300 MB).
    var stopFreeBytes: Int64 = 300 * 1_024 * 1_024
    /// The free space is read after every this much recorded audio.
    var diskCheckEvery: Duration = .seconds(5)
    /// A microphone segment waits for the system track at most this long (media time) before it is written
    /// without the echo check, so a crash loses only the last seconds of the microphone.
    var micHoldLimit: Duration = .seconds(30)
    /// The wall-clock heartbeat that enforces the limits and notices a stalled stream.
    var heartbeat: Duration = .seconds(1)
    /// A track that delivers no audio for this long (wall clock) is treated as lost.
    var stallTimeout: Duration = .seconds(10)
    /// How many times a track whose stream ended or stalled is started again before it counts as lost
    /// (0 loses it at once).
    var resumeAttempts = 5
    /// The wait before each of those attempts, so a device change has time to settle.
    var resumeDelay: Duration = .seconds(2)
    /// How many times a microphone that did not start is started again (the first seconds of the recording,
    /// a change of the default input, "Spróbuj ponownie"): three attempts 1.5 s apart, the first of them 1.5 s
    /// after the start (about 5 s in all).
    var startRetryAttempts = 3
    /// The wait before each attempt of the automatic retry, between the attempts of "Try again", and before the
    /// first one after the default input changed.
    var startRetryDelay: Duration = .milliseconds(1_500)
    /// A gap longer than this is filled with only this much silence; the rest shifts the track on the timeline.
    var longestGapFill: Duration = .seconds(120)
    /// Audio sent to the engine before the start of the speech range the voice activity detector reports. The
    /// detector opens a range at the 256 ms chunk that first reaches its threshold, so the first syllables of a
    /// quiet word can lie before it (issue #135). Never reaches into the previous segment.
    var segmentPreRoll: Duration = SegmentWindow.preRoll
    /// Audio sent after the end of the range: the detector closes it at the start of the first quiet chunk,
    /// so a soft ending can lie after it. Not added where a segment is cut at the model window.
    var segmentPostRoll: Duration = SegmentWindow.postRoll
    /// The detector's entry threshold: chunks from `SegmentingStats.nearMissFloor` up to it, while no speech is
    /// open, are counted as near misses.
    var vadEntryThreshold: Float = MeetingVAD.tuning.entryThreshold

    static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }

    static func samples(in duration: Duration) -> Int {
        let parts = duration.components
        return Int(parts.seconds) * SpoolFormat.sampleRate
            + Int(Double(parts.attoseconds) / 1e18 * Double(SpoolFormat.sampleRate))
    }
}

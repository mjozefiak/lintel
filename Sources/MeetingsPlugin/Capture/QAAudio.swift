#if DEBUG
import Foundation
import LintelSpeech
import Synchronization

/// DEBUG only: what a `--qa` run records instead of the microphone and the system audio (issue: QA mode must never
/// open the tester's microphone). `MeetingsRuntime` and `MeetingsSystem` use these as soon as
/// `MeetingsSettings.qaAudio` is set, which `AppEnvironment.qa` always does; `RealAudioGuard` backs it up where the
/// real audio objects are created. Not a contract.

/// A track that plays a 16 kHz mono WAV file (`--qa-meeting-mic-wav`, `--qa-meeting-system-wav`) a little faster
/// than real time and then silence in real time until `stop()`, or just silence when there is no file. The stream
/// never ends by itself: `MeetingSession` takes a stream that ends while recording for a lost track and starts it
/// again, which would replay the file. An unreadable file makes `start` throw, so the recording says it could not
/// start instead of silently recording nothing.
final class QAAudioSource: AudioInput, Sendable {
    private let file: URL?
    private let chunkSamples: Int
    private let fileChunkDelay: Duration
    private let silenceChunkDelay: Duration
    private let task = Mutex<Task<Void, Never>?>(nil)

    init(
        file: URL?, chunkSamples: Int = AudioFormat.sampleRate / 10, fileChunkDelay: Duration = .milliseconds(20),
        silenceChunkDelay: Duration = .milliseconds(100)
    ) {
        self.file = file
        self.chunkSamples = max(1, chunkSamples)
        self.fileChunkDelay = fileChunkDelay
        self.silenceChunkDelay = silenceChunkDelay
    }

    /// The file this track plays, `nil` for a silent one (tests read it).
    var playedFile: URL? { file }

    func start(onLevel: @escaping @Sendable (Float) -> Void) async throws -> AsyncStream<[Float]> {
        let samples = try file.map { try WAVFile.samples(from: Data(contentsOf: $0)) } ?? []
        let (stream, continuation) = AsyncStream<[Float]>.makeStream(bufferingPolicy: .unbounded)
        let size = chunkSamples
        let fileDelay = fileChunkDelay
        let silenceDelay = silenceChunkDelay
        let running = Task {
            var index = 0
            while index < samples.count, !Task.isCancelled {
                let chunk = Array(samples[index..<min(index + size, samples.count)])
                onLevel(MicrophoneCapture.level(of: chunk))
                continuation.yield(chunk)
                index += size
                try? await Task.sleep(for: fileDelay)
            }
            let silence = [Float](repeating: 0, count: size)
            while !Task.isCancelled {
                onLevel(0)
                continuation.yield(silence)
                try? await Task.sleep(for: silenceDelay)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in running.cancel() }
        task.withLock {
            $0?.cancel()
            $0 = running
        }
        return stream
    }

    func stop() async {
        task.withLock {
            $0?.cancel()
            $0 = nil
        }
    }
}

/// The microphone permission as a QA run sees it: granted, never asked, so the QA bundle shows no system prompt.
struct QAGrantedAuthorizer: MicrophoneAuthorizer {
    func status() -> MicrophoneAccess { .granted }
    func requestAccess() async -> Bool { true }
}

/// A tap that delivers one audible buffer and nothing real: the system-audio test of a QA run says "works" without
/// touching Core Audio.
struct QAProcessTapBackend: ProcessTapBackend {
    private struct Session: ProcessTapSession {
        func stop() {}
    }

    private struct Observation: OutputChangeObservation {
        func cancel() {}
    }

    func startTap(
        excludingOwnProcess: Bool, onBuffer: @escaping @Sendable (TapBuffer) -> Void
    ) throws(SystemAudioError) -> any ProcessTapSession {
        onBuffer(TapBuffer(samples: [0.5, -0.5, 0.5, -0.5], channels: 2, sampleRate: 48_000, hostTime: 0))
        return Session()
    }

    func observeOutputDeviceChanges(
        _ handler: @escaping @Sendable () -> Void
    ) throws(SystemAudioError) -> any OutputChangeObservation {
        Observation()
    }
}

/// The self-test's tone, silent: a QA run never plays a sound on the speakers.
struct QASilentTonePlayer: TonePlayer {
    func play(duration: TimeInterval) async throws {}
}

extension MeetingsSystem {
    /// This system with the microphone permission granted and a self-test over `QAProcessTapBackend`; the
    /// microphone and the tracks of a session come from `MeetingsRuntime`, which reads the same QA settings.
    func forQAAudio() -> MeetingsSystem {
        var system = self
        system.microphoneAuthorizer = { QAGrantedAuthorizer() }
        system.makeSelfTest = { SystemAudioSelfTest(backend: QAProcessTapBackend(), player: QASilentTonePlayer()) }
        return system
    }
}
#endif

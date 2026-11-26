#if DEBUG
import Foundation
import LintelSpeech
import Testing

@testable import MeetingsPlugin

/// A `--qa` run never records the tester's microphone or taps the system audio: with `plugins.meetings.qaAudio` set
/// (`AppEnvironment.qa` always sets it), every source the runtime and the plugin build is a WAV file or silence.
@MainActor
@Suite struct QAAudioTests {
    private static func fixture(_ directory: TemporaryDirectory, _ name: String, frames: Int) throws -> URL {
        let url = directory.url.appending(path: name)
        try Synth.wav16(Synth.sine(frequency: 220, rate: 16_000, frames: frames, channels: 1)).write(to: url)
        return url
    }

    private func request(_ harness: MeetingsHarness, mic: Bool = true, system: Bool = true) throws
        -> MeetingSessionRequest
    {
        let keys = try testKeys()
        let store = try MeetingsStore.open(in: harness.pluginDirectory, keys: keys)
        return MeetingSessionRequest(
            store: store, keys: keys, spool: SpoolStorage(pluginDirectory: harness.pluginDirectory), modelID: "m",
            modelFolder: harness.directory.url, recordsMicrophone: mic, recordsSystemAudio: system)
    }

    @Test func aQARunBuildsOnlyQASources() throws {
        let files = try TemporaryDirectory()
        let mic = try Self.fixture(files, "mic.wav", frames: 1_600)
        let harness = try MeetingsHarness(settings: [
            "plugins.meetings.qaAudio": .bool(true), "plugins.meetings.qaMicWAV": .string(mic.path),
        ])
        let runtime = MeetingsRuntime(context: harness.context, settings: harness.meetingsSettings)
        let sources = runtime.makeSources(try request(harness))
        let microphone = try #require(sources.microphone as? QAAudioSource)
        #expect(microphone.playedFile == mic)
        // No system file: a silent track, never the Core Audio tap.
        let system = try #require(sources.system as? QAAudioSource)
        #expect(system.playedFile == nil)
        #expect(!(sources.microphone is MicrophoneCapture))
        #expect(!(sources.system is SystemAudioSource))
        #expect(runtime.defaultInputChanges == nil)
        #expect(!runtime.retriesMicrophone)
        #expect(runtime.inputDiagnostics().isEmpty)
        #expect(MeetingsSystem.liveUses.isEmpty, "\(MeetingsSystem.liveUses.sorted())")
    }

    @Test func aRecordingOfOneTrackStillGetsNoRealSource() throws {
        let harness = try MeetingsHarness(settings: ["plugins.meetings.qaAudio": .bool(true)])
        let runtime = MeetingsRuntime(context: harness.context, settings: harness.meetingsSettings)
        let systemOnly = runtime.makeSources(try request(harness, mic: false))
        #expect(systemOnly.microphone is UnavailableAudioInput)
        #expect(systemOnly.system is QAAudioSource)
        let micOnly = runtime.makeSources(try request(harness, system: false))
        #expect(micOnly.microphone is QAAudioSource)
        #expect(micOnly.system == nil)
    }

    /// The counterpart: without the QA switch the runtime builds the real sources (so the test above can fail).
    @Test func withoutTheSwitchTheRuntimeBuildsTheRealSources() throws {
        let harness = try MeetingsHarness()
        let runtime = MeetingsRuntime(context: harness.context, settings: harness.meetingsSettings)
        #expect(runtime.makeMicrophone(nil, nil) is MicrophoneCapture)
        #expect(runtime.makeSystemAudio() is SystemAudioSource)
        #expect(runtime.retriesMicrophone)
    }

    @Test func theFilesOfTheFlagsReachTheSession() async throws {
        let files = try TemporaryDirectory()
        let mic = try Self.fixture(files, "mic.wav", frames: 3_200)
        let system = try Self.fixture(files, "system.wav", frames: 1_600)
        let harness = try MeetingsHarness(settings: [
            "plugins.meetings.qaAudio": .bool(true), "plugins.meetings.qaMicWAV": .string(mic.path),
            "plugins.meetings.qaSystemWAV": .string(system.path),
        ])
        let runtime = MeetingsRuntime(context: harness.context, settings: harness.meetingsSettings)
        let sources = runtime.makeSources(try request(harness))
        let micSamples = try WAVFile.samples(from: Data(contentsOf: mic))
        let systemSamples = try WAVFile.samples(from: Data(contentsOf: system))

        let micHeard = try await Self.heard(sources.microphone, count: micSamples.count)
        #expect(micHeard == micSamples)
        let systemHeard = try await Self.heard(try #require(sources.system), count: systemSamples.count)
        #expect(systemHeard == systemSamples)
    }

    @Test func aQAPluginUsesTheGrantedAuthorizerAndAQuietSelfTest() async throws {
        let harness = try MeetingsHarness(settings: ["plugins.meetings.qaAudio": .bool(true)])
        let plugin = MeetingsPlugin(context: harness.context)
        let authorizer = plugin.system.microphoneAuthorizer()
        #expect(authorizer is QAGrantedAuthorizer)
        #expect(authorizer.status() == .granted)
        let test = plugin.system.makeSelfTest()
        #expect(test.backend is QAProcessTapBackend)
        #expect(test.player is QASilentTonePlayer)
        #expect(await test.run() == .works)
        // The permission and the tone of a plugin without the switch stay the fakes of the test system.
        let other = MeetingsPlugin(context: try MeetingsHarness().context)
        #expect(other.system.microphoneAuthorizer() is FakeAuthorizer)
        #expect(MeetingsSystem.liveUses.isEmpty, "\(MeetingsSystem.liveUses.sorted())")
    }

    @Test func theSpoolFolderOfTheFlagIsUsed() throws {
        let folder = try TemporaryDirectory()
        let harness = try MeetingsHarness(settings: [
            "plugins.meetings.qaAudio": .bool(true), "plugins.meetings.qaSpoolDir": .string(folder.url.path),
        ])
        let spool = MeetingsPlugin.spoolStorage(context: harness.context, settings: harness.meetingsSettings)
        #expect(spool.root.path == folder.url.path)
        let plain = try MeetingsHarness()
        #expect(
            MeetingsPlugin.spoolStorage(context: plain.context, settings: plain.meetingsSettings).root
                == plain.pluginDirectory.appending(path: "Spool", directoryHint: .isDirectory))
    }

    // MARK: The source itself

    @Test func theSourceEndsInSilenceAndNeverFinishesByItself() async throws {
        let files = try TemporaryDirectory()
        let file = try Self.fixture(files, "mic.wav", frames: 800)
        let source = QAAudioSource(
            file: file, chunkSamples: 400, fileChunkDelay: .milliseconds(1), silenceChunkDelay: .milliseconds(1))
        let stream = try await source.start { _ in }
        var chunks: [[Float]] = []
        for await chunk in stream {
            chunks.append(chunk)
            if chunks.count == 6 { break }
        }
        #expect(chunks.count == 6)
        #expect(chunks[0].contains { $0 != 0 } && chunks[1].contains { $0 != 0 })
        #expect(chunks[2...].allSatisfy { $0.allSatisfy { $0 == 0 } })
        await source.stop()
    }

    /// The loop below ends only when the stream finishes; without that the time limit fails the test.
    @Test(.timeLimit(.minutes(1))) func stopEndsTheStream() async throws {
        let source = QAAudioSource(file: nil, chunkSamples: 400, silenceChunkDelay: .milliseconds(10))
        let stream = try await source.start { _ in }
        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first != nil)
        await source.stop()
        // Chunks already buffered may still arrive; after them the stream finishes instead of running forever.
        while await iterator.next() != nil {}
    }

    /// An empty path (what `AppEnvironment.qaAudioSettings` writes without a flag) is silence, not a file named "".
    @Test func anEmptyPathIsNoFile() throws {
        let harness = try MeetingsHarness(settings: [
            "plugins.meetings.qaAudio": .bool(true), "plugins.meetings.qaMicWAV": .string(""),
            "plugins.meetings.qaSystemWAV": .string(""), "plugins.meetings.qaSpoolDir": .string(""),
        ])
        #expect(harness.meetingsSettings.qaAudio == QAAudioSettings())
    }

    @Test func anUnreadableFileMakesTheStartFailInsteadOfRecordingSilence() async throws {
        let source = QAAudioSource(file: URL(filePath: "/nonexistent/qa-mic.wav"))
        await #expect(throws: (any Error).self) { _ = try await source.start { _ in } }
    }

    /// The first `count` samples of a source, then stops it.
    private static func heard(_ source: any AudioInput, count: Int) async throws -> [Float] {
        let stream = try await source.start { _ in }
        var samples: [Float] = []
        for await chunk in stream {
            samples += chunk
            if samples.count >= count { break }
        }
        await source.stop()
        return Array(samples.prefix(count))
    }
}
#endif

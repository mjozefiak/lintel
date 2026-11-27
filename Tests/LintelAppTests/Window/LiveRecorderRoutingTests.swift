import Foundation
import LintelKit
import Testing

@testable import LintelApp

/// A live recording whose status is idle; only its id matters here.
@MainActor
private final class IdleLiveRecorder: LiveRecorder {
    let pluginID: PluginID

    init(_ id: PluginID) { pluginID = id }

    func status() -> AsyncStream<LiveRecordingStatus> {
        AsyncStream {
            $0.yield(.idle)
            $0.finish()
        }
    }

    func start() async throws {}
    func stop(writeNotes: Bool) async {}
    func retryNotes(_ key: NoteKey) async throws {}
}

/// A plugin that contributes one recorder, under its own id or a stranger's.
private final class LiveRecorderPlugin: LintelPlugin {
    static let manifest = PluginManifest(
        id: "recorder", displayName: "Recorder", symbolName: "record.circle", order: 1)
    private let recorder: IdleLiveRecorder

    init(context: PluginContext) { recorder = IdleLiveRecorder("recorder") }

    var liveRecorder: (any LiveRecorder)? { recorder }
}

/// A second plugin that contributes one too: the shell keeps the first and logs this one once.
private final class SecondLiveRecorderPlugin: LintelPlugin {
    static let manifest = PluginManifest(
        id: "second-recorder", displayName: "Second Recorder", symbolName: "record.circle", order: 2)

    init(context: PluginContext) {}

    var liveRecorder: (any LiveRecorder)? { IdleLiveRecorder("second-recorder") }
}

/// A plugin whose recorder claims a stranger's id.
private final class StrangerLiveRecorderPlugin: LintelPlugin {
    static let manifest = PluginManifest(
        id: "stranger-recorder", displayName: "Stranger", symbolName: "record.circle", order: 3)

    init(context: PluginContext) {}

    var liveRecorder: (any LiveRecorder)? { IdleLiveRecorder("somebody-else") }
}

/// Spec `2026-11-24-notes-explorer-main-window`, step 2.3: what the shell hands the Notes section through
/// `PluginContext.liveRecorder` (the first active plugin's recorder).
@MainActor @Suite struct LiveRecorderRoutingTests {
    @Test func theFirstActivePluginsRecorderIsHandedOverAndTheOthersAreReported() async throws {
        let rig = try TestEnvironment()
        defer { rig.tearDown() }
        let host = rig.makeHost([LiveRecorderPlugin.self, SecondLiveRecorderPlugin.self])
        await host.start()
        var reports: [String] = []
        let recorder = AppCoordinator.activeLiveRecorder(host) { reports.append($0) }
        #expect(recorder?.pluginID == "recorder")
        #expect(reports.count == 1)
        #expect(reports.first?.contains("is taken already") == true)
        // A switched-off plugin hands out nothing.
        await host.setEnabled(false, for: "recorder")
        #expect(AppCoordinator.activeLiveRecorder(host)?.pluginID == "second-recorder")
        await host.setEnabled(false, for: "second-recorder")
        #expect(AppCoordinator.activeLiveRecorder(host) == nil)
        await host.stop()
    }

    @Test func aSecondRecorderIsReportedOnceHoweverOftenTheShellLooks() async throws {
        let rig = try TestEnvironment()
        defer { rig.tearDown() }
        let host = rig.makeHost([LiveRecorderPlugin.self, SecondLiveRecorderPlugin.self])
        await host.start()
        var messages: [String] = []
        let once = OnceReported { messages.append($0) }
        // The shell reads the recorder on every status read and every recording of the window.
        for _ in 0..<3 {
            #expect(AppCoordinator.activeLiveRecorder(host) { once.report($0) }?.pluginID == "recorder")
        }
        #expect(messages.count == 1)
        #expect(messages.first?.contains("is taken already") == true)
        await host.stop()
    }

    @Test func theContextsLiveRecorderIsWhatTheRelayHas() throws {
        let rig = try TestEnvironment()
        defer { rig.tearDown() }
        let relay = NoteSourcesRelay()
        let context = rig.environment.makeContext(
            for: LiveRecorderPlugin.manifest, liveRecorder: { relay.liveRecorder() })
        #expect(context.liveRecorder() == nil)
        let recorder = IdleLiveRecorder("recorder")
        relay.liveRecorder = { recorder }
        #expect(context.liveRecorder()?.pluginID == "recorder")
    }

    @Test func aRecorderUnderAStrangersIdIsDropped() async throws {
        let rig = try TestEnvironment()
        defer { rig.tearDown() }
        let host = rig.makeHost([StrangerLiveRecorderPlugin.self])
        await host.start()
        var reports: [String] = []
        #expect(AppCoordinator.activeLiveRecorder(host) { reports.append($0) } == nil)
        #expect(reports.count == 1)
        #expect(reports.first?.contains("does not match") == true)
        await host.stop()
    }

    @Test func theContextAnswersNothingUntilTheShellSetsTheRecorder() {
        // A plugin built without a shell (tests, the gallery) gets no recorder.
        let relay = NoteSourcesRelay()
        #expect(relay.liveRecorder() == nil)
        let recorder = IdleLiveRecorder("recorder")
        relay.liveRecorder = { recorder }
        #expect(relay.liveRecorder()?.pluginID == "recorder")
    }
}

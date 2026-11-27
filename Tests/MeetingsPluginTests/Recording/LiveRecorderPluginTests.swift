import Foundation
import LintelKit
import Testing

@testable import MeetingsPlugin

/// The plugin's part of the notes explorer's live recording (step 2.3): `LintelPlugin.liveRecorder` exists
/// while the plugin is active, records through the same controller as the shortcut, and its lifecycle follows
/// the plugin's. Nothing real is captured, shown or stored.
@MainActor
@Suite struct LiveRecorderPluginTests {
    /// A plugin whose controller records with a scripted session and a manual clock.
    private func scriptedPlugin(
        _ harness: MeetingsHarness, behaviour: ScriptedSession.Behaviour = ScriptedSession.Behaviour()
    ) -> MeetingsPlugin {
        let plugin = MeetingsPlugin(context: harness.context)
        let clock = ManualClock()
        plugin.adjustControllerDependencies = { dependencies in
            dependencies.authorizer = FakeAuthorizer(.granted)
            dependencies.speechModel = { .ready(modelID: "parakeet-ultra", folder: URL(filePath: "/tmp/lintel-model")) }
            dependencies.makeSession = { _ in ScriptedSession(behaviour) }
            dependencies.clock = clock
            dependencies.shutdownTimeout = .seconds(5)
            dependencies.stateChanged = { ChangeSignal.shared.fire() }
        }
        return plugin
    }

    @Test func theLiveRecorderExistsOnlyWhileThePluginIsActive() async throws {
        let harness = try MeetingsHarness()
        let plugin = MeetingsPlugin(context: harness.context)
        #expect(plugin.liveRecorder == nil)
        try await plugin.activate()
        #expect(plugin.liveRecorder != nil)
        #expect(plugin.liveRecorder?.pluginID == "meetings")
        await plugin.deactivate()
        #expect(plugin.liveRecorder == nil)
    }

    @Test func aRecordingFromTheWindowRunsInTheControllerAndDeactivatingEndsTheStatusStream() async throws {
        let harness = try MeetingsHarness()
        let plugin = scriptedPlugin(harness)
        try await plugin.activate()
        let recorder = try #require(plugin.liveRecorder)
        let collector = StatusCollector(recorder.status())
        await waitForStep(collector) { $0 == .value(.idle) }
        try await recorder.start()
        #expect(plugin.controller?.phase == .recording)
        await plugin.deactivate()
        // `.idle` is the last value before every stream ends.
        await waitForStep(collector) { $0 == .ended }
        #expect(collector.steps.dropLast().last == .value(.idle))
    }

    @Test func theShortcutsRecordingReachesTheWindowStatus() async throws {
        let harness = try MeetingsHarness()
        let plugin = scriptedPlugin(harness)
        try await plugin.activate()
        let recorder = try #require(plugin.liveRecorder)
        // The command (`meetings.record`) starts the same controller; the window's status follows it instead of
        // starting a second recording.
        plugin.controller?.toggle()
        await eventually("the recording runs") { plugin.controller?.phase == .recording }
        #expect(plugin.liveRecorderAdapter.currentStatus != .idle)
        await #expect(throws: LiveRecordingFailure.alreadyRecording) { try await recorder.start() }
        await plugin.deactivate()
    }

    @Test func stoppingWithoutNotesKeepsTheAutomaticNotesOffForThatMeeting() async throws {
        let harness = try MeetingsHarness()
        // The notes are on for a new install, so a saved meeting would queue its job by itself.
        #expect(harness.meetingsSettings.notesEnabled)
        let plugin = scriptedPlugin(harness)
        try await plugin.activate()
        let recorder = try #require(plugin.liveRecorder)
        try await recorder.start()
        await recorder.stop(writeNotes: false)
        // The meeting is saved without a notes job; the same call for another meeting does queue one.
        await eventually("the meeting was saved") { plugin.controller?.phase == .idle }
        #expect(plugin.notes.board.phase(of: 7) == nil)
        plugin.library.meetingReady(8)
        #expect(plugin.notes.board.phase(of: 8) == .queued)
        await plugin.deactivate()
    }

    @Test func deactivatingDuringAPendingStartAnswersItWithAnError() async throws {
        let harness = try MeetingsHarness()
        let authorizer = FakeAuthorizer(.notDetermined)
        let prompt = Latch()
        authorizer.holdAnswers(until: prompt)
        let plugin = MeetingsPlugin(context: harness.context)
        plugin.adjustControllerDependencies = { dependencies in
            dependencies.authorizer = authorizer
            dependencies.speechModel = {
                .ready(modelID: "parakeet-ultra", folder: URL(filePath: "/tmp/lintel-model"))
            }
            dependencies.makeSession = { _ in ScriptedSession() }
            dependencies.clock = ManualClock()
            dependencies.stateChanged = { ChangeSignal.shared.fire() }
        }
        try await plugin.activate()
        let recorder = try #require(plugin.liveRecorder)
        let recording = Task { try await recorder.start() }
        await eventually("the prompt") { authorizer.requests == 1 }
        // The plugin is switched off while the window's start waits: it gets an error, not a success for nothing.
        await plugin.deactivate()
        await #expect(throws: LiveRecordingFailure.other) { try await recording.value }
        prompt.open()
    }

    @Test func stoppingWithNotesLeavesTheAutomaticNotesOn() async throws {
        let harness = try MeetingsHarness()
        let plugin = scriptedPlugin(harness)
        try await plugin.activate()
        let recorder = try #require(plugin.liveRecorder)
        try await recorder.start()
        // The recorder's own stop is the same path as the shortcut's "Stop and Write Notes".
        await recorder.stop(writeNotes: true)
        await eventually("the meeting was saved") { plugin.controller?.phase == .idle }
        #expect(plugin.notes.board.phase(of: 7) == .queued)
        await plugin.deactivate()
    }
}

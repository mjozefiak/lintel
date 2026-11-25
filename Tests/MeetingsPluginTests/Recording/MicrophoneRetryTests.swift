import Foundation
import LintelSpeech
import Testing

@testable import MeetingsPlugin

/// A microphone that does not start is started again (the first seconds, a change of the default input, "Try
/// again"), keeps its place on the timeline and its spool, and the HUD hears about it only when that fails.
/// Nothing here touches a real device.
@Suite struct MicrophoneRetryTests {
    private func limits(_ rig: SessionRig, attempts: Int = 3) -> MeetingSessionLimits {
        var limits = rig.shortLimits
        limits.startRetryAttempts = attempts
        limits.startRetryDelay = .milliseconds(1)
        // The test clock jumps; no track may count as stalled.
        limits.stallTimeout = .seconds(100_000)
        return limits
    }

    /// Moves the test clock (which also releases every sleep that waits for it) until `condition` holds.
    private func drive(_ clock: TestClock, until condition: () -> Bool) async -> Bool {
        for _ in 0..<2_000 {
            if condition() { return true }
            clock.tick(advancing: 0)
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
        return condition()
    }

    private func systemScript() -> TrackScript {
        var system = TrackScript()
        system.silence(2)
        return system
    }

    @Test func aMicrophoneThatStartsOnTheSecondTryIsNeverReportedAsMissing() async throws {
        let rig = try SessionRig(texts: [81: "Mic after a retry"])
        var mic = TrackScript()
        mic.silence(1)
        mic.say(81, seconds: 2)
        mic.silence(14)
        let flaky = ControlledInput(failFirstStarts: 1)
        let clock = TestClock()
        let session = rig.session(
            mic: mic, system: systemScript(), limits: limits(rig), clock: clock, micAudio: flaky,
            micStartsLate: true)
        let log = SessionEventLog(session)
        let id = try await session.start()
        #expect(await drive(clock) { log.contains { $0 == .trackResumed(.mic) } })
        #expect(flaky.attempts == 2)
        #expect(!log.contains { $0 == .trackUnavailable(.mic) })
        flaky.push(mic.samples)
        let outcome = await session.finish()
        #expect(outcome.result == .ready)
        #expect(try rig.rows(id).map(\.text) == ["Mic after a retry"])
    }

    @Test func aMicrophoneThatFailsEveryAttemptIsReportedOnceAndTheSystemTrackCarriesOn() async throws {
        let rig = try SessionRig(texts: [:])
        let broken = ControlledInput(failStart: true)
        let clock = TestClock()
        let session = rig.session(
            mic: TrackScript(), system: systemScript(), limits: limits(rig), clock: clock, micAudio: broken)
        let log = SessionEventLog(session)
        _ = try await session.start()
        #expect(await drive(clock) { log.contains { $0 == .trackUnavailable(.mic) } })
        // The start itself and the three retries.
        #expect(broken.attempts == 4)
        #expect(await session.state == .recording)
        // The meeting still ends cleanly with the microphone's spool given up.
        let outcome = await session.finish()
        #expect(outcome.result != .failed)
        #expect(log.all.filter { $0 == .trackUnavailable(.mic) }.count == 1)
    }

    @Test func tryAgainStartsAMicrophoneThatWorksNowAndTheWarningGoesAway() async throws {
        let rig = try SessionRig(texts: [82: "Mic after Try again"])
        var mic = TrackScript()
        mic.silence(1)
        mic.say(82, seconds: 2)
        mic.silence(14)
        let device = ControlledInput(failStart: true)
        let clock = TestClock()
        let session = rig.session(
            mic: mic, system: systemScript(), limits: limits(rig, attempts: 1), clock: clock, micAudio: device,
            micStartsLate: true)
        let log = SessionEventLog(session)
        let id = try await session.start()
        #expect(await drive(clock) { log.contains { $0 == .trackUnavailable(.mic) } })
        #expect(await session.retryMicrophone() == false)
        device.setFailStart(false)
        #expect(await session.retryMicrophone())
        #expect(await log.wait { $0 == .trackResumed(.mic) })
        device.push(mic.samples)
        let outcome = await session.finish()
        #expect(outcome.result == .ready)
        #expect(try rig.rows(id).map(\.text) == ["Mic after Try again"])
    }

    @Test func anUnpluggedStoredMicrophoneRecordsFromTheDefaultInputAndSaysSo() async throws {
        let rig = try SessionRig(texts: [84: "Spoken on the default input"])
        var mic = TrackScript()
        mic.silence(1)
        mic.say(84, seconds: 2)
        mic.silence(14)
        let device = ControlledInput()
        device.setFallback(InputFallback(requestedName: "USB MICROPHONE", usingName: "MacBook Pro Microphone"))
        let session = rig.session(mic: mic, system: systemScript(), limits: limits(rig), micAudio: device)
        let log = SessionEventLog(session)
        let id = try await session.start()
        #expect(
            await log.wait { $0 == .microphoneFallback(requested: "USB MICROPHONE", using: "MacBook Pro Microphone") })
        // The microphone is recording (it is not reported missing) and its words are in the transcript.
        #expect(!log.contains { $0 == .trackUnavailable(.mic) })
        device.push(mic.samples)
        let outcome = await session.finish()
        #expect(outcome.result == .ready)
        #expect(try rig.rows(id).map(\.text) == ["Spoken on the default input"])
        #expect(log.all.filter { if case .microphoneFallback = $0 { true } else { false } }.count == 1)
    }

    @Test func aMicrophoneOnTheChosenDeviceReportsNoFallback() async throws {
        let rig = try SessionRig(texts: [:])
        let device = ControlledInput()
        let session = rig.session(mic: TrackScript(), system: systemScript(), limits: limits(rig), micAudio: device)
        let log = SessionEventLog(session)
        _ = try await session.start()
        _ = await session.finish()
        #expect(!log.contains { if case .microphoneFallback = $0 { true } else { false } })
    }

    @Test func aMicrophoneThatMovesToTheDefaultInputWhileRecordingSaysSoAndSaysWhenItIsBack() async throws {
        let rig = try SessionRig(texts: [:])
        let device = ControlledInput()
        let session = rig.session(mic: TrackScript(), system: systemScript(), limits: limits(rig), micAudio: device)
        let log = SessionEventLog(session)
        _ = try await session.start()
        // The chosen microphone is unplugged during an audio configuration change; the capture carries on.
        device.moveToFallback(InputFallback(requestedName: "USB MICROPHONE", usingName: nil))
        #expect(await log.wait { $0 == .microphoneFallback(requested: "USB MICROPHONE", using: nil) })
        device.moveToFallback(nil)
        #expect(await log.wait { $0 == .microphoneFallbackEnded })
        #expect(!log.contains { $0 == .trackLost(.mic) || $0 == .trackUnavailable(.mic) })
        _ = await session.finish()
    }

    @Test func aMicrophoneThatStartsLateOnTheDefaultInputSaysSoWhenItResumes() async throws {
        let rig = try SessionRig(texts: [:])
        let device = ControlledInput(failFirstStarts: 1)
        device.setFallback(InputFallback(requestedName: nil, usingName: "Built-in"))
        let clock = TestClock()
        let session = rig.session(
            mic: TrackScript(), system: systemScript(), limits: limits(rig), clock: clock, micAudio: device,
            micStartsLate: true)
        let log = SessionEventLog(session)
        _ = try await session.start()
        #expect(await drive(clock) { log.contains { $0 == .trackResumed(.mic) } })
        #expect(log.contains { $0 == .microphoneFallback(requested: nil, using: "Built-in") })
        _ = await session.finish()
    }

    @Test func aMicrophoneThatStartsLongAfterTheBeginningLandsAtItsRealPlaceOnTheTimeline() async throws {
        let rig = try SessionRig(texts: [83: "Spoken after the long wait"])
        // 200 s of wall clock pass before the microphone works: more than the 120 s an interruption fills.
        var mic = TrackScript()
        mic.silence(200)
        mic.say(83, seconds: 2)
        mic.silence(14)
        let device = ControlledInput(failStart: true)
        let clock = TestClock()
        let session = rig.session(
            mic: mic, system: systemScript(), limits: limits(rig, attempts: 1), clock: clock, micAudio: device,
            micStartsLate: true)
        let log = SessionEventLog(session)
        let id = try await session.start()
        #expect(await drive(clock) { log.contains { $0 == .trackUnavailable(.mic) } })
        clock.tick(advancing: 200)
        device.setFailStart(false)
        #expect(await session.retryMicrophone())
        device.push(Array(mic.samples.dropFirst(200 * rate)))
        let outcome = await session.finish()
        #expect(outcome.result == .ready)
        let rows = try rig.rows(id)
        #expect(rows.map(\.text) == ["Spoken after the long wait"])
        #expect(abs((rows.first?.startMs ?? 0) - 200_000) < 500)
    }

    @Test func aChangeOfTheDefaultInputStartsAMicrophoneThatDidNotStart() async throws {
        let rig = try SessionRig(texts: [:])
        let device = ControlledInput(failStart: true)
        let (changes, trigger) = AsyncStream<Void>.makeStream()
        let clock = TestClock()
        let session = rig.session(
            mic: TrackScript(), system: systemScript(), limits: limits(rig, attempts: 1), clock: clock,
            micAudio: device, defaultInputChanges: { changes })
        let log = SessionEventLog(session)
        _ = try await session.start()
        #expect(await drive(clock) { log.contains { $0 == .trackUnavailable(.mic) } })
        device.setFailStart(false)
        trigger.yield()
        #expect(await drive(clock) { log.contains { $0 == .trackResumed(.mic) } })
        trigger.finish()
        _ = await session.finish()
    }

    @Test func aMicrophoneThatRecordsIsLeftAloneWhenTheDefaultInputChanges() async throws {
        let rig = try SessionRig(texts: [:])
        let (changes, trigger) = AsyncStream<Void>.makeStream()
        let session = rig.session(
            mic: TrackScript(), system: systemScript(), limits: limits(rig), defaultInputChanges: { changes })
        _ = try await session.start()
        trigger.yield()
        try await Task.sleep(for: .milliseconds(30))
        #expect(rig.mic.attempts == 1)
        trigger.finish()
        _ = await session.finish()
    }

    @Test func aRecordingOfTheSystemAudioOnlyNeverRetriesItsMissingMicrophone() async throws {
        let rig = try SessionRig(texts: [:])
        let none = ControlledInput(failStart: true)
        let session = rig.session(
            mic: TrackScript(), system: systemScript(), limits: limits(rig), micAudio: none, retriesMicrophone: false)
        let log = SessionEventLog(session)
        _ = try await session.start()
        // Reported at once, as before, and never tried again.
        #expect(await log.wait { $0 == .trackUnavailable(.mic) })
        #expect(await session.retryMicrophone() == false)
        #expect(none.attempts == 1)
        _ = await session.finish()
    }

    @Test func finishingWhileTheMicrophoneIsStillMissingLeavesNoMicrophoneSpool() async throws {
        let rig = try SessionRig(texts: [:])
        let broken = ControlledInput(failStart: true)
        let uuid = UUID()
        var system = TrackScript()
        system.silence(20)
        let session = rig.session(
            mic: TrackScript(), system: system, limits: limits(rig, attempts: 1), uuid: uuid, micAudio: broken,
            keepAudio: true)
        _ = try await session.start()
        rig.system.push(system.samples)
        let outcome = await session.finish()
        #expect(outcome.result == .ready)
        #expect(FileManager.default.fileExists(atPath: rig.spool.file(for: uuid, track: .system).path))
        #expect(!FileManager.default.fileExists(atPath: rig.spool.file(for: uuid, track: .mic).path))
    }
}

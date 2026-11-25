import AVFoundation
import Foundation
import Synchronization
import Testing

@testable import LintelSpeech

/// An engine the test drives: it can post the configuration-change notification, give a different format and
/// refuse to start. Nothing real is opened.
private final class FakeCaptureEngine: CaptureEngine, @unchecked Sendable {
    let source = NSObject()
    let format: AVAudioFormat
    let startFails: Bool
    private let state = Mutex<State>(State())
    private struct State {
        var tap: (@Sendable (AVAudioPCMBuffer) -> Void)?
        var selected: String?
        var started = false
        var stopped = false
    }

    init(sampleRate: Double = 48_000, startFails: Bool = false) {
        format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        self.startFails = startFails
    }

    var notificationSource: AnyObject { source }
    var inputFormat: AVAudioFormat { format }
    var selected: String? { state.withLock { $0.selected } }
    var started: Bool { state.withLock { $0.started } }
    var stopped: Bool { state.withLock { $0.stopped } }

    func select(deviceUID: String) throws { state.withLock { $0.selected = deviceUID } }
    func installTap(format: AVAudioFormat, _ block: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        state.withLock { $0.tap = block }
    }
    func removeTap() { state.withLock { $0.tap = nil } }
    func start() throws {
        if startFails { throw CaptureError.engineFailed("fake") }
        state.withLock { $0.started = true }
    }
    func stop() { state.withLock { $0.stopped = true } }

    /// What the microphone delivers: `seconds` of a constant 0.1.
    func deliver(seconds: Double = 0.1) {
        let frames = AVAudioFrameCount(seconds * format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
            let tap = state.withLock({ $0.tap })
        else { return }
        buffer.frameLength = frames
        for index in 0..<Int(frames) { buffer.floatChannelData![0][index] = 0.1 }
        tap(buffer)
    }
}

/// Hands out the engines in order and remembers them.
private final class Engines: @unchecked Sendable {
    private let state = Mutex<[FakeCaptureEngine]>([])
    private let script: @Sendable (Int) -> FakeCaptureEngine

    init(_ script: @escaping @Sendable (Int) -> FakeCaptureEngine = { _ in FakeCaptureEngine() }) {
        self.script = script
    }

    var all: [FakeCaptureEngine] { state.withLock { $0 } }
    func make() -> FakeCaptureEngine {
        state.withLock { engines in
            let engine = script(engines.count)
            engines.append(engine)
            return engine
        }
    }
}

private final class Received: @unchecked Sendable {
    private let state = Mutex<(samples: [Float], finished: Bool)>(([], false))
    var count: Int { state.withLock { $0.samples.count } }
    var finished: Bool { state.withLock { $0.finished } }
    var loud: Int { state.withLock { $0.samples.filter { $0 != 0 }.count } }
    func consume(_ stream: AsyncStream<[Float]>) {
        Task {
            for await chunk in stream { state.withLock { $0.samples += chunk } }
            state.withLock { $0.finished = true }
        }
    }
}

@Suite struct MicrophoneCaptureReconfigurationTests {
    private let builtIn = MicrophoneCapture.InputDevice(uid: "builtin", name: "MacBook Pro Microphone")
    private let usb = MicrophoneCapture.InputDevice(uid: "usb-1", name: "USB MICROPHONE")

    private func capture(
        uid: String? = nil, devices: @escaping @Sendable () -> [MicrophoneCapture.InputDevice], engines: Engines,
        center: NotificationCenter
    ) -> MicrophoneCapture {
        MicrophoneCapture(
            deviceUID: uid, deviceName: uid == nil ? nil : "USB MICROPHONE", devices: devices,
            defaultInputName: { "MacBook Pro Microphone" }, makeEngine: { engines.make() }, notifications: center,
            restartDelays: [.milliseconds(1), .milliseconds(1), .milliseconds(1)], sleep: { _ in })
    }

    private func wait(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<2_000 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
        return condition()
    }

    @Test func aNewDefaultOutputRestartsTheEngineAndTheStreamGoesOn() async throws {
        let engines = Engines()
        let center = NotificationCenter()
        let capture = capture(devices: { [builtIn] }, engines: engines, center: center)
        let stream = try await capture.start(onLevel: { _ in })
        let received = Received()
        received.consume(stream)
        engines.all[0].deliver()
        #expect(await wait { received.loud > 0 })
        let before = received.loud

        // The default output changes (a monitor disappears): the engine stops and says so.
        center.post(name: .AVAudioEngineConfigurationChange, object: engines.all[0].source)
        #expect(await wait { engines.all.count == 2 && engines.all[1].started })
        #expect(engines.all[0].stopped)
        engines.all[1].deliver()
        #expect(await wait { received.loud > before })
        #expect(!received.finished)
        #expect(capture.fallback == nil)
        await capture.stop()
        #expect(await wait { received.finished })
    }

    @Test func aChangedSampleRateIsConvertedFromTheNewFormat() async throws {
        let engines = Engines {
            $0 == 0 ? FakeCaptureEngine(sampleRate: 48_000) : FakeCaptureEngine(sampleRate: 44_100)
        }
        let center = NotificationCenter()
        let capture = capture(devices: { [builtIn] }, engines: engines, center: center)
        let stream = try await capture.start(onLevel: { _ in })
        let received = Received()
        received.consume(stream)
        center.post(name: .AVAudioEngineConfigurationChange, object: engines.all[0].source)
        #expect(await wait { engines.all.count == 2 && engines.all[1].started })
        let before = received.count
        engines.all[1].deliver(seconds: 0.5)
        #expect(await wait { received.count >= before + 7_000 })
        // 0.5 s of 44.1 kHz audio comes out as about 8000 samples at 16 kHz.
        #expect(received.count - before <= 8_100)
        await capture.stop()
    }

    @Test func theChosenDeviceIsSelectedAgainWhenItIsStillThere() async throws {
        let engines = Engines()
        let center = NotificationCenter()
        let capture = capture(uid: usb.uid, devices: { [builtIn, usb] }, engines: engines, center: center)
        _ = try await capture.start(onLevel: { _ in })
        center.post(name: .AVAudioEngineConfigurationChange, object: engines.all[0].source)
        #expect(await wait { engines.all.count == 2 && engines.all[1].started })
        #expect(engines.all[0].selected == usb.uid)
        #expect(engines.all[1].selected == usb.uid)
        #expect(capture.fallback == nil)
        await capture.stop()
    }

    @Test func aChosenDeviceThatWentAwayContinuesOnTheDefaultInputAndTellsTheHandler() async throws {
        let engines = Engines()
        let center = NotificationCenter()
        let present = Mutex([builtIn, usb])
        let capture = capture(uid: usb.uid, devices: { present.withLock { $0 } }, engines: engines, center: center)
        let told = Mutex<[InputFallback?]>([])
        capture.setFallbackHandler { fallback in told.withLock { $0.append(fallback) } }
        let stream = try await capture.start(onLevel: { _ in })
        let received = Received()
        received.consume(stream)
        #expect(capture.fallback == nil)

        present.withLock { $0 = [builtIn] }
        center.post(name: .AVAudioEngineConfigurationChange, object: engines.all[0].source)
        #expect(await wait { engines.all.count == 2 && engines.all[1].started })
        // No selection of the missing device; the system's input is used and the preference is untouched.
        #expect(engines.all[1].selected == nil)
        let expected = InputFallback(requestedName: "USB MICROPHONE", usingName: "MacBook Pro Microphone")
        #expect(await wait { told.withLock { $0 } == [expected] })
        #expect(capture.fallback == expected)
        engines.all[1].deliver()
        #expect(await wait { received.loud > 0 })
        #expect(!received.finished)

        // Plugged in again during the next change: the chosen device is back and the handler hears it.
        present.withLock { $0 = [builtIn, usb] }
        center.post(name: .AVAudioEngineConfigurationChange, object: engines.all[1].source)
        #expect(await wait { engines.all.count == 3 && engines.all[2].started })
        #expect(engines.all[2].selected == usb.uid)
        #expect(await wait { told.withLock { $0 } == [expected, nil] })
        #expect(capture.fallback == nil)
        await capture.stop()
    }

    @Test func theStreamEndsOnlyWhenNoInputCanBeStartedAgain() async throws {
        let engines = Engines { $0 == 0 ? FakeCaptureEngine() : FakeCaptureEngine(startFails: true) }
        let center = NotificationCenter()
        let capture = capture(devices: { [builtIn] }, engines: engines, center: center)
        let stream = try await capture.start(onLevel: { _ in })
        let received = Received()
        received.consume(stream)
        center.post(name: .AVAudioEngineConfigurationChange, object: engines.all[0].source)
        #expect(await wait { received.finished })
        // The first engine and one try per delay.
        #expect(engines.all.count == 4)
        #expect(engines.all.dropFirst().allSatisfy { $0.stopped })
    }

    @Test func aNotificationAfterStopStartsNothing() async throws {
        let engines = Engines()
        let center = NotificationCenter()
        let capture = capture(devices: { [builtIn] }, engines: engines, center: center)
        let stream = try await capture.start(onLevel: { _ in })
        let received = Received()
        received.consume(stream)
        await capture.stop()
        center.post(name: .AVAudioEngineConfigurationChange, object: engines.all[0].source)
        try await Task.sleep(for: .milliseconds(100))
        #expect(engines.all.count == 1)
        #expect(await wait { received.finished })
    }

    @Test func aNotificationForAnEngineThatIsNotCurrentIsIgnored() async throws {
        let engines = Engines()
        let center = NotificationCenter()
        let capture = capture(devices: { [builtIn] }, engines: engines, center: center)
        _ = try await capture.start(onLevel: { _ in })
        center.post(name: .AVAudioEngineConfigurationChange, object: NSObject())
        try await Task.sleep(for: .milliseconds(100))
        #expect(engines.all.count == 1)
        await capture.stop()
    }
}

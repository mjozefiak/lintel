import AVFoundation
import CoreAudio
import CryptoKit
import Foundation
import os

/// The microphone permission, read without a prompt and asked for only on request.
public struct SystemMicrophoneAuthorizer: MicrophoneAuthorizer {
    public init() {}

    public func status() -> MicrophoneAccess {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    public func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
}

public enum CaptureError: Error, CustomStringConvertible {
    case noInputDevice
    case converterUnavailable
    case engineFailed(String)

    /// The case only (and the system's error text for `engineFailed`), for a log line: never audio.
    public var description: String {
        switch self {
        case .noInputDevice: "noInputDevice"
        case .converterUnavailable: "converterUnavailable"
        case .engineFailed(let message): "engineFailed(\(message))"
        }
    }
}

/// What Core Audio says about an input device, for a diagnostic log line when the microphone does not start:
/// the device's name and UID, its nominal sample rate and its input channel count. No audio.
public struct InputDeviceInfo: Equatable, Sendable {
    public let name: String
    public let uid: String
    public let sampleRate: Double
    public let channels: Int

    public init(name: String, uid: String, sampleRate: Double, channels: Int) {
        self.name = name
        self.uid = uid
        self.sampleRate = sampleRate
        self.channels = channels
    }

    /// `name=#<hash>, uid=#<hash>, sampleRate=<rate>, channels=<count>` (issue #269). A device's name often
    /// carries a person's name ("Anna's AirPods Pro") and a Bluetooth device's UID its hardware address, so both
    /// are hashed the way `NotesLog.hashedKey` does it (the first 4 bytes of SHA-256, in hex): two lines about
    /// one device still match, neither the name nor the address is readable. The two numbers stay readable.
    /// Safe to write with `privacy: .public`; the format is pinned by `InputDeviceInfoTests`.
    public var logDescription: String {
        "name=#\(Self.hashed(name)), uid=#\(Self.hashed(uid)), sampleRate=\(Int(sampleRate)), channels=\(channels)"
    }

    /// A value as it may appear in a log: the first 4 bytes of its SHA-256, in hex.
    static func hashed(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}

/// The audio engine `MicrophoneCapture` drives, as a seam: the real one wraps `AVAudioEngine`, tests give a fake
/// that can post the configuration-change notification and change the format.
protocol CaptureEngine: AnyObject, Sendable {
    /// The object `.AVAudioEngineConfigurationChange` is posted for.
    var notificationSource: AnyObject { get }
    func select(deviceUID: String) throws
    var inputFormat: AVAudioFormat { get }
    func installTap(format: AVAudioFormat, _ block: @escaping @Sendable (AVAudioPCMBuffer) -> Void)
    func removeTap()
    func start() throws
    func stop()
}

final class SystemCaptureEngine: CaptureEngine, @unchecked Sendable {
    private let engine = AVAudioEngine()

    var notificationSource: AnyObject { engine }
    var inputFormat: AVAudioFormat { engine.inputNode.outputFormat(forBus: 0) }

    func select(deviceUID: String) throws {
        guard let device = MicrophoneCapture.deviceID(forUID: deviceUID), let unit = engine.inputNode.audioUnit else {
            throw CaptureError.noInputDevice
        }
        var id = device
        let status = AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id,
            UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else { throw CaptureError.noInputDevice }
    }

    func installTap(format: AVAudioFormat, _ block: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in block(buffer) }
    }

    func removeTap() { engine.inputNode.removeTap(onBus: 0) }

    func start() throws {
        #if DEBUG
        try RealAudioGuard.check("microphone")
        #endif
        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw CaptureError.engineFailed(error.localizedDescription)
        }
    }

    func stop() { engine.stop() }
}

/// `AVAudioEngine` on the chosen input (or the system's), converted to 16 kHz mono `Float32` and handed out
/// in memory; nothing is written to disk.
///
/// A change of the audio configuration (a new default *output*, a monitor that is plugged or unplugged, a
/// sample-rate change, sleep) stops the engine and posts `.AVAudioEngineConfigurationChange`, even though the
/// input did not go anywhere. The capture then builds a new engine on the same device (or, when the chosen
/// device is gone, on the default input, reported as a `fallback`) and the stream goes on, with the short gap
/// filled with silence so a timeline stays right. The stream ends only when no input can be started again.
public final class MicrophoneCapture: InputFallbackReporting, @unchecked Sendable {
    private let deviceUID: String?
    private let deviceName: String?
    private let devices: @Sendable () -> [InputDevice]
    private let defaultInputName: @Sendable () -> String?
    private let makeEngine: @Sendable () -> any CaptureEngine
    private let notifications: NotificationCenter
    private let restartDelays: [Duration]
    private let sleep: @Sendable (Duration) async -> Void
    private let logger = Logger(subsystem: "com.lintelapp", category: "capture")
    private let lock = NSLock()
    private var activeFallback: InputFallback?
    private var fallbackHandler: (@Sendable (InputFallback?) -> Void)?
    private var engine: (any CaptureEngine)?
    private var observer: (any NSObjectProtocol)?
    private var continuation: AsyncStream<[Float]>.Continuation?
    private var onLevel: (@Sendable (Float) -> Void)?
    /// Counts engines: a notification or a restart that belongs to an older one is ignored.
    private var generation = 0

    /// - Parameters:
    ///   - deviceUID: the input device's UID from Settings, or `nil` for the system's input. A device that is
    ///     not there at the moment of `start` (unplugged) does not fail the capture: it records from the
    ///     system's input and `fallback` says so.
    ///   - deviceName: the name stored with that choice, for the message; read from a USB UID when `nil`.
    ///   - devices, defaultInputName: where the devices come from (Core Audio; tests give lists).
    public convenience init(
        deviceUID: String? = nil, deviceName: String? = nil,
        devices: @escaping @Sendable () -> [InputDevice] = { MicrophoneCapture.inputDevices() },
        defaultInputName: @escaping @Sendable () -> String? = { MicrophoneCapture.defaultInputInfo()?.name }
    ) {
        self.init(
            deviceUID: deviceUID, deviceName: deviceName, devices: devices, defaultInputName: defaultInputName,
            makeEngine: { SystemCaptureEngine() }, notifications: .default,
            restartDelays: [.milliseconds(100), .milliseconds(250), .milliseconds(500)],
            sleep: { try? await Task.sleep(for: $0) })
    }

    init(
        deviceUID: String?, deviceName: String?, devices: @escaping @Sendable () -> [InputDevice],
        defaultInputName: @escaping @Sendable () -> String?, makeEngine: @escaping @Sendable () -> any CaptureEngine,
        notifications: NotificationCenter, restartDelays: [Duration],
        sleep: @escaping @Sendable (Duration) async -> Void
    ) {
        self.deviceUID = deviceUID
        self.deviceName = deviceName
        self.devices = devices
        self.defaultInputName = defaultInputName
        self.makeEngine = makeEngine
        self.notifications = notifications
        self.restartDelays = restartDelays
        self.sleep = sleep
    }

    public var fallback: InputFallback? { lock.withLock { activeFallback } }

    public func setFallbackHandler(_ handler: (@Sendable (InputFallback?) -> Void)?) {
        lock.withLock { fallbackHandler = handler }
    }

    public func start(onLevel: @escaping @Sendable (Float) -> Void) async throws -> AsyncStream<[Float]> {
        #if DEBUG
        // Before the engine exists: a QA run never builds the input node or selects a device (`RealAudioGuard`).
        try RealAudioGuard.check("microphone")
        #endif
        let (stream, continuation) = AsyncStream<[Float]>.makeStream(bufferingPolicy: .unbounded)
        let engine = makeEngine()
        let used = try attach(engine, continuation: continuation, onLevel: onLevel)
        let token = installObserver(for: engine)
        // The engine is current before it starts, so a configuration change during the start is not lost.
        lock.withLock {
            generation += 1
            activeFallback = used
            self.engine = engine
            self.observer = token
            self.continuation = continuation
            self.onLevel = onLevel
        }
        do {
            try engine.start()
        } catch {
            lock.withLock {
                // Also turns away a restart that a notification during the start began.
                generation += 1
                if self.engine === engine {
                    self.engine = nil
                    self.observer = nil
                }
                self.continuation = nil
                self.onLevel = nil
                activeFallback = nil
            }
            engine.removeTap()
            notifications.removeObserver(token)
            throw error
        }
        return stream
    }

    public func stop() async {
        let (engine, observer, continuation) = lock.withLock {
            () -> ((any CaptureEngine)?, (any NSObjectProtocol)?, AsyncStream<[Float]>.Continuation?) in
            defer {
                self.engine = nil
                self.observer = nil
                self.continuation = nil
                self.onLevel = nil
                // A restart that is under way notices and gives its new engine back.
                self.generation += 1
            }
            return (self.engine, self.observer, self.continuation)
        }
        if let observer { notifications.removeObserver(observer) }
        engine?.removeTap()
        engine?.stop()
        continuation?.finish()
    }

    // MARK: Engine setup

    /// Picks the device, reads its format and puts the tap on `engine`. Returns the fallback in use, if any.
    private func attach(
        _ engine: any CaptureEngine, continuation: AsyncStream<[Float]>.Continuation,
        onLevel: @escaping @Sendable (Float) -> Void
    ) throws -> InputFallback? {
        let resolution = InputDeviceResolution.resolve(
            requestedUID: deviceUID, requestedName: deviceName, available: devices(),
            defaultInputName: defaultInputName())
        var used: InputFallback?
        switch resolution {
        case .systemDefault:
            break
        case .chosen(let uid):
            // The device was listed a moment ago; if selecting it still fails, the system's input is used.
            do {
                try engine.select(deviceUID: uid)
            } catch {
                used = InputFallback(
                    requestedName: deviceName ?? InputDeviceResolution.displayName(ofUID: uid),
                    usingName: defaultInputName())
            }
        case .fallback(let fallback):
            used = fallback
        }
        let format = engine.inputFormat
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CaptureError.noInputDevice }
        guard
            let target = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: Double(AudioFormat.sampleRate), channels: 1,
                interleaved: false),
            let converter = AVAudioConverter(from: format, to: target)
        else { throw CaptureError.converterUnavailable }

        engine.installTap(format: format) { buffer in
            let ratio = target.sampleRate / format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
            guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                if supplied {
                    status.pointee = .noDataNow
                    return nil
                }
                supplied = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, let channel = converted.floatChannelData?[0], converted.frameLength > 0 else { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
            onLevel(Self.level(of: samples))
            continuation.yield(samples)
        }
        return used
    }

    private func installObserver(for engine: any CaptureEngine) -> any NSObjectProtocol {
        notifications.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine.notificationSource, queue: nil
        ) { [weak self] _ in
            self?.configurationChanged(of: engine)
        }
    }

    // MARK: Configuration change

    /// The engine stopped because the configuration changed. Not a lost microphone by itself: start a new engine.
    private func configurationChanged(of changed: any CaptureEngine) {
        let work = lock.withLock { () -> (Int, AsyncStream<[Float]>.Continuation, @Sendable (Float) -> Void)? in
            guard let current = engine, current === changed, let continuation, let onLevel else { return nil }
            generation += 1
            return (generation, continuation, onLevel)
        }
        guard let (token, continuation, onLevel) = work else { return }
        logger.notice("Audio configuration changed while recording; restarting the capture")
        Task.detached { [self] in await restart(token, continuation: continuation, onLevel: onLevel) }
    }

    private func restart(
        _ token: Int, continuation: AsyncStream<[Float]>.Continuation, onLevel: @escaping @Sendable (Float) -> Void
    ) async {
        let began = ContinuousClock.now
        let old = lock.withLock { () -> ((any CaptureEngine)?, (any NSObjectProtocol)?) in
            defer {
                engine = nil
                observer = nil
            }
            return (engine, observer)
        }
        if let observer = old.1 { notifications.removeObserver(observer) }
        old.0?.removeTap()
        old.0?.stop()
        // Silence already put into the stream for the gap, so an attempt that fails does not count it twice.
        var filled = 0
        for (index, delay) in restartDelays.enumerated() {
            // The device list is inconsistent for a moment while hardware comes and goes.
            await sleep(delay)
            guard lock.withLock({ generation == token && self.continuation != nil }) else { return }
            let fresh = makeEngine()
            do {
                let used = try attach(fresh, continuation: continuation, onLevel: onLevel)
                let observerToken = installObserver(for: fresh)
                // The engine is current before it starts, so a notification during the start is not lost.
                let adopted = lock.withLock { () -> Bool in
                    guard generation == token, self.continuation != nil else { return false }
                    engine = fresh
                    observer = observerToken
                    return true
                }
                guard adopted else {
                    notifications.removeObserver(observerToken)
                    fresh.removeTap()
                    fresh.stop()
                    return
                }
                // The gap is silence, so a timeline that counts samples stays in step with the clock. It goes in
                // before the engine starts: the tap's first buffer may arrive before `start()` returns.
                let gap = began.duration(to: .now)
                let seconds = min(max(0, Double(gap.components.seconds) + Double(gap.components.attoseconds) / 1e18), 2)
                let silent = Int(seconds * Double(AudioFormat.sampleRate)) - filled
                if silent > 0 {
                    continuation.yield([Float](repeating: 0, count: silent))
                    filled += silent
                }
                do {
                    try fresh.start()
                } catch {
                    lock.withLock {
                        if engine === fresh {
                            engine = nil
                            observer = nil
                        }
                    }
                    notifications.removeObserver(observerToken)
                    throw error
                }
                // `stop()` (or another configuration change) may have come while the engine was starting: an
                // engine that is no longer current must not keep the microphone open.
                let current = lock.withLock { () -> (handler: (@Sendable (InputFallback?) -> Void)?, changed: Bool)? in
                    guard generation == token, engine === fresh else { return nil }
                    let changed = activeFallback != used
                    activeFallback = used
                    return (fallbackHandler, changed)
                }
                guard let (handler, changed) = current else {
                    notifications.removeObserver(observerToken)
                    fresh.removeTap()
                    fresh.stop()
                    return
                }
                logger.notice(
                    "Audio capture restarted after attempt \(index + 1, privacy: .public), fallback \(used != nil, privacy: .public)"
                )
                if changed { handler?(used) }
                return
            } catch {
                logger.error(
                    "Audio capture restart failed, attempt \(index + 1, privacy: .public): \(String(describing: error), privacy: .public)"
                )
                fresh.removeTap()
                fresh.stop()
            }
        }
        let ended = lock.withLock { () -> Bool in
            guard generation == token else { return false }
            self.continuation = nil
            return true
        }
        guard ended else { return }
        logger.error("Audio capture lost: no input could be started after the configuration change")
        continuation.finish()
    }

    /// The lowest level of a chunk that holds any sound at all: a working microphone's quietest room noise
    /// (below -60 dBFS) still reports this, so a level of exactly 0 means digital silence.
    public static let quietestSoundLevel: Float = 1e-6

    /// A 0...1 loudness for the HUD from the RMS, on a log scale so quiet speech still moves it. It is 0 only
    /// for digital silence (no chunk, or every sample zero, which is what a blocked microphone delivers);
    /// anything else is at least `quietestSoundLevel`.
    public static func level(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let meanSquare = samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(samples.count)
        guard meanSquare > 0 else { return 0 }
        let decibels = 10 * log10(meanSquare)
        return min(1, max(quietestSoundLevel, (decibels + 60) / 60))
    }

    // MARK: Input devices

    public struct InputDevice: Identifiable, Equatable, Sendable {
        public let uid: String
        public let name: String
        public var id: String { uid }

        public init(uid: String, name: String) {
            self.uid = uid
            self.name = name
        }
    }

    /// Every device that can record.
    public static func inputDevices() -> [InputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr
        else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
        else { return [] }
        return ids.compactMap { id in
            guard hasInput(id), let uid = string(kAudioDevicePropertyDeviceUID, of: id),
                let name = string(kAudioObjectPropertyName, of: id)
            else { return nil }
            return InputDevice(uid: uid, name: name)
        }
    }

    private static func hasInput(_ device: AudioDeviceID) -> Bool {
        inputChannelCount(device) > 0
    }

    private static func inputChannelCount(_ device: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    /// The system's default input right now, or `nil` when there is none (or Core Audio does not answer). It
    /// reads properties only and never opens the device.
    public static func defaultInputInfo() -> InputDeviceInfo? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
                == noErr, device != 0
        else { return nil }
        var rateAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var rate = Float64(0)
        var rateSize = UInt32(MemoryLayout<Float64>.size)
        _ = AudioObjectGetPropertyData(device, &rateAddress, 0, nil, &rateSize, &rate)
        return InputDeviceInfo(
            name: string(kAudioObjectPropertyName, of: device) ?? "unknown",
            uid: string(kAudioDevicePropertyDeviceUID, of: device) ?? "unknown", sampleRate: rate,
            channels: inputChannelCount(device))
    }

    private static func string(_ selector: AudioObjectPropertySelector, of device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr, let value else {
            return nil
        }
        return value.takeRetainedValue() as String
    }

    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var cfUID = uid as CFString
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { pointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<CFString>.size), pointer, &size,
                &device)
        }
        return status == noErr && device != 0 ? device : nil
    }
}

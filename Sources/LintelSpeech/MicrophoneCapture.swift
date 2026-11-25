import AVFoundation
import CoreAudio
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

    /// `name=..., uid=..., sampleRate=..., channels=...`
    public var logDescription: String {
        "name=\(name), uid=\(uid), sampleRate=\(Int(sampleRate)), channels=\(channels)"
    }
}

/// `AVAudioEngine` on the chosen input (or the system's), converted to 16 kHz mono `Float32` and handed out
/// in memory; nothing is written to disk. The stream ends when the device goes away or the Mac sleeps.
public final class MicrophoneCapture: InputFallbackReporting, @unchecked Sendable {
    private let deviceUID: String?
    private let deviceName: String?
    private let devices: @Sendable () -> [InputDevice]
    private let defaultInputName: @Sendable () -> String?
    private let lock = NSLock()
    private var activeFallback: InputFallback?
    private var engine: AVAudioEngine?
    private var observer: (any NSObjectProtocol)?
    private var continuation: AsyncStream<[Float]>.Continuation?

    /// - Parameters:
    ///   - deviceUID: the input device's UID from Settings, or `nil` for the system's input. A device that is
    ///     not there at the moment of `start` (unplugged) does not fail the capture: it records from the
    ///     system's input and `fallback` says so.
    ///   - deviceName: the name stored with that choice, for the message; read from a USB UID when `nil`.
    ///   - devices, defaultInputName: where the devices come from (Core Audio; tests give lists).
    public init(
        deviceUID: String? = nil, deviceName: String? = nil,
        devices: @escaping @Sendable () -> [InputDevice] = { MicrophoneCapture.inputDevices() },
        defaultInputName: @escaping @Sendable () -> String? = { MicrophoneCapture.defaultInputInfo()?.name }
    ) {
        self.deviceUID = deviceUID
        self.deviceName = deviceName
        self.devices = devices
        self.defaultInputName = defaultInputName
    }

    public var fallback: InputFallback? { lock.withLock { activeFallback } }

    public func start(onLevel: @escaping @Sendable (Float) -> Void) async throws -> AsyncStream<[Float]> {
        let engine = AVAudioEngine()
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
                try Self.select(deviceUID: uid, on: engine)
            } catch {
                used = InputFallback(
                    requestedName: deviceName ?? InputDeviceResolution.displayName(ofUID: uid),
                    usingName: defaultInputName())
            }
        case .fallback(let fallback):
            used = fallback
        }
        lock.withLock { activeFallback = used }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CaptureError.noInputDevice }
        guard
            let target = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: Double(AudioFormat.sampleRate), channels: 1,
                interleaved: false),
            let converter = AVAudioConverter(from: format, to: target)
        else { throw CaptureError.converterUnavailable }

        let (stream, continuation) = AsyncStream<[Float]>.makeStream(bufferingPolicy: .unbounded)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
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
        // A device change or sleep reconfigures the engine and stops it: end the stream.
        let observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.finishStream()
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            NotificationCenter.default.removeObserver(observer)
            throw CaptureError.engineFailed(error.localizedDescription)
        }
        lock.withLock {
            self.engine = engine
            self.observer = observer
            self.continuation = continuation
        }
        return stream
    }

    public func stop() async {
        let (engine, observer, continuation) = lock.withLock {
            () -> (AVAudioEngine?, (any NSObjectProtocol)?, AsyncStream<[Float]>.Continuation?) in
            defer {
                self.engine = nil
                self.observer = nil
                self.continuation = nil
            }
            return (self.engine, self.observer, self.continuation)
        }
        if let observer { NotificationCenter.default.removeObserver(observer) }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        continuation?.finish()
    }

    private func finishStream() {
        let continuation = lock.withLock { self.continuation }
        continuation?.finish()
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

    private static func deviceID(forUID uid: String) -> AudioDeviceID? {
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

    private static func select(deviceUID: String, on engine: AVAudioEngine) throws {
        guard let device = deviceID(forUID: deviceUID), let unit = engine.inputNode.audioUnit else {
            throw CaptureError.noInputDevice
        }
        var id = device
        let status = AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id,
            UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else { throw CaptureError.noInputDevice }
    }
}

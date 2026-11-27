#if DEBUG
import AVFoundation
import AppKit
import Foundation
import LintelKit
import LintelSpeech
import SwiftUI
import Synchronization

/// DEBUG only: a QA run that dictates from a WAV file instead of the microphone, through the whole session
/// (voice activity detection, speech model, cleanup, paste), for QA without the tester's microphone permission, a
/// hotkey or a person (`docs/qa.md`, `qa dictation play`). Not a contract.
///
/// While a file is set the plugin builds its sessions over `WAVFileAudioInput` and reports the microphone as
/// allowed; the HUD is wrapped so the last state it showed can be drawn in the result card.
final class DictationQAPlayback: Sendable {
    private let state = Mutex<URL?>(nil)

    var url: URL? {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }

    /// `--qa-setting plugins.dictation.qaAudio` (set by `AppEnvironment.qa` in every `--qa` run): while it is on, the
    /// plugin never builds the real microphone, so a dictation outside `qa dictation play` hears silence.
    static let settingName = "qaAudio"

    /// The session's audio in a DEBUG build: the file being played, silence in a `--qa` run, `nil` for the real
    /// microphone (every other run).
    func input(isQARun: Bool) -> (any AudioInput)? {
        if let url { return WAVFileAudioInput(url: url) }
        return isQARun ? QASilentAudioInput() : nil
    }
}

/// Silence in 100 ms chunks, in real time, until `stop()`: the microphone of a `--qa` run outside `qa dictation play`.
struct QASilentAudioInput: AudioInput {
    func start(onLevel: @escaping @Sendable (Float) -> Void) async throws -> AsyncStream<[Float]> {
        AsyncStream { continuation in
            let task = Task {
                let chunk = [Float](repeating: 0, count: AudioFormat.sampleRate / 10)
                while !Task.isCancelled {
                    onLevel(0)
                    continuation.yield(chunk)
                    try? await Task.sleep(for: .milliseconds(100))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func stop() async {}
}

/// The microphone permission as the QA playback sees it: granted while a file is played and in a `--qa` run, the real
/// answer otherwise.
struct DictationQAAuthorizer: MicrophoneAuthorizer {
    let playback: DictationQAPlayback
    let base: any MicrophoneAuthorizer
    /// A `--qa` run: granted without asking, so the QA bundle shows no system prompt.
    var isQARun = false

    private var isGranted: Bool { playback.url != nil || isQARun }
    func status() -> MicrophoneAccess { isGranted ? .granted : base.status() }
    func requestAccess() async -> Bool { isGranted ? true : await base.requestAccess() }
}

/// Forwards to the real HUD and remembers the last state, and the dictation the history was handed.
@MainActor
final class DictationQARecorder: HUDPresenter {
    private let wrapped: any HUDPresenter
    private(set) var lastState: HUDState?
    private(set) var entry: DictationEntry?

    init(wrapping wrapped: any HUDPresenter) { self.wrapped = wrapped }

    func show(_ state: HUDState) {
        lastState = state
        wrapped.show(state)
    }

    func hide() { wrapped.hide() }

    func record(_ entry: DictationEntry) { self.entry = entry }

    func reset() {
        lastState = nil
        entry = nil
    }
}

/// A 16 kHz mono WAV (any sample rate and channel count is converted), played to the session faster than real time,
/// followed by a second of silence so the last segment closes. The stream ends after it, which the session reports as
/// a lost microphone and the controller turns into "finish and paste".
struct WAVFileAudioInput: AudioInput {
    let url: URL

    enum Failure: Error { case unreadable }

    func start(onLevel: @escaping @Sendable (Float) -> Void) async throws -> AsyncStream<[Float]> {
        let samples = try Self.samples(of: url) + [Float](repeating: 0, count: AudioFormat.sampleRate)
        return AsyncStream { continuation in
            let task = Task {
                let step = AudioFormat.sampleRate / 10
                var offset = 0
                while offset < samples.count, !Task.isCancelled {
                    let chunk = Array(samples[offset..<min(samples.count, offset + step)])
                    offset += step
                    let level = chunk.isEmpty ? 0 : sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count))
                    onLevel(min(1, level * 4))
                    continuation.yield(chunk)
                    try? await Task.sleep(for: .milliseconds(4))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func stop() async {}

    static func samples(of url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard
            let target = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: Double(AudioFormat.sampleRate), channels: 1,
                interleaved: false),
            let source = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
            let converter = AVAudioConverter(from: file.processingFormat, to: target)
        else { throw Failure.unreadable }
        try file.read(into: source)
        let ratio = target.sampleRate / file.processingFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(source.frameLength) * ratio) + 1024
        guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw Failure.unreadable
        }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .endOfStream
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return source
        }
        guard status != .error, let channel = converted.floatChannelData?[0] else { throw Failure.unreadable }
        return Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
    }
}

extension DictationPlugin: PluginQACommands {
    /// `play <output prefix> <wav path>`: dictates the file through the real session and the real cleanup, waits for
    /// the paste, then writes `<prefix>.json` (the transcript, the cleaned text and the last HUD state) and the result card
    /// as `<prefix>-light.png` and `<prefix>-dark.png`. The microphone, the hotkey and Accessibility are not needed;
    /// the speech model and the cleanup model must be installed under the QA data root (`Models/`).
    public func runQACommand(_ line: String) async -> String {
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 3, parts[0] == "play" else { return "error: usage: play <output prefix> <wav path>" }
        guard let controller, let recorder = qaRecorder else { return "error: plugin is off" }
        let wav = URL(filePath: parts[2])
        guard FileManager.default.fileExists(atPath: wav.path) else { return "error: no such file" }
        guard !controller.isBusy else { return "error: a dictation is running" }

        recorder.reset()
        qaPlayback.url = wav
        defer { qaPlayback.url = nil }
        controller.keyEvent(.down)
        try? await Task.sleep(for: .milliseconds(80))
        controller.keyEvent(.up)
        let deadline = ContinuousClock.now + .seconds(240)
        while controller.isBusy, ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(100)) }
        // Let the HUD show its last state and the history take the entry.
        try? await Task.sleep(for: .milliseconds(300))
        guard !controller.isBusy else { return "error: timed out" }
        guard let state = recorder.lastState else { return "error: no HUD state" }

        let raw = controller.lastRawText ?? ""
        let promptVersion = CleanupPrompt.version(for: settings.effectiveLevel ?? .standard)
        let text = recorder.entry?.bestText ?? ""
        let card = DictationQACard(
            file: wav.deletingPathExtension().lastPathComponent, raw: raw, text: text, state: state,
            promptVersion: promptVersion)
        let prefix = parts[1]
        var written: [String] = []
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            let path = "\(prefix)-\(name).png"
            if card.writePNG(to: URL(filePath: path), appearance: appearance) { written.append(path) }
        }
        struct Result: Encodable {
            let file: String
            let raw: String
            let text: String
            let hud: String
            let promptVersion: Int
        }
        let result = Result(
            file: wav.lastPathComponent, raw: raw, text: text, hud: state.title, promptVersion: promptVersion)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(result) { try? data.write(to: URL(filePath: "\(prefix).json")) }
        return "ok: \(state.title); \(written.count) screenshots"
    }
}

/// The card of a QA dictation: the real HUD view in the state the flow ended in, what the speech model heard and what
/// the cleanup pasted.
@MainActor
struct DictationQACard {
    let file: String
    let raw: String
    let text: String
    let state: HUDState
    let promptVersion: Int

    func writePNG(to url: URL, appearance name: NSAppearance.Name) -> Bool {
        let model = HUDModel()
        model.reducesMotion = true
        model.state = state
        let view = Card(file: file, raw: raw, text: text, promptVersion: promptVersion, hud: model)
        let host = NSHostingView(rootView: view)
        let size = NSSize(width: 520, height: 520)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.appearance = NSAppearance(named: name)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return false }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: url)) != nil
    }

    private struct Card: View {
        let file: String
        let raw: String
        let text: String
        let promptVersion: Int
        let hud: HUDModel

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Dictation QA: \(file)").font(.headline)
                    Spacer()
                    Text("cleanup prompt v\(promptVersion)").font(.caption).foregroundStyle(.secondary)
                }
                // The HUD's glass is not drawn by `cacheDisplay`: a solid pill stands behind the real view.
                DictationHUDView(model: hud)
                    .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)).frame(width: 248, height: 40))
                    .frame(maxWidth: .infinity)
                block("Heard (speech model, before cleanup)", raw)
                block("Pasted (after cleanup)", text)
            }
            .padding(16)
            .frame(width: 520, height: 520, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        }

        private func block(_ title: String, _ value: String) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(value.isEmpty ? " " : value)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            }
        }
    }
}
#endif

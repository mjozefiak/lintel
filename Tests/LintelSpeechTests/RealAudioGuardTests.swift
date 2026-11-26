#if DEBUG
import Foundation
import Testing

@testable import LintelSpeech

/// `--qa` mode never opens real audio: `RealAudioGuard` makes the places that create it throw. The process's gate is
/// set by the app only, so these tests use their own `Gate` and read the shared one.
@Suite struct RealAudioGuardTests {
    @Test func aForbiddenGateThrowsAndAnOpenOneDoesNot() throws {
        let gate = RealAudioGuard.Gate()
        try gate.check("microphone")
        gate.forbid()
        #expect(gate.isForbidden)
        #expect(throws: RealAudioGuard.Forbidden.self) { try gate.check("microphone") }
        #expect(RealAudioGuard.Forbidden(source: "tap").description.contains("tap"))
    }

    @Test func noTestFlipsTheProcessGate() {
        // Tests build fake engines and fake sources; the shared gate is the app's alone.
        #expect(!RealAudioGuard.isForbidden)
    }

    /// Every file that creates real audio objects asks the guard first. A new place that opens the microphone, the
    /// Core Audio tap or an output engine fails here until it does too.
    @Test func everyFileThatOpensRealAudioAsksTheGuard() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Sources", directoryHint: .isDirectory)
        let creators = ["AVAudioEngine()", "AudioHardwareCreateProcessTap(", "AudioDeviceStart(", "AVAudioRecorder("]
        var found: [String] = []
        let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            guard creators.contains(where: text.contains) else { continue }
            found.append(url.lastPathComponent)
            #expect(text.contains("RealAudioGuard"), "\(url.lastPathComponent) opens real audio without the guard")
        }
        #expect(
            Set(found) == ["MicrophoneCapture.swift", "CoreAudioProcessTapBackend.swift"],
            "a new file opens real audio: \(found.sorted())")
    }
}
#endif

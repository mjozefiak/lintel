#if DEBUG
import Foundation
import LintelSpeech
import Testing

@testable import DictationPlugin

/// A `--qa` run never dictates through the tester's microphone: a session hears the played file or silence, and the
/// permission reads as granted so the QA bundle shows no system prompt.
@Suite struct DictationQAAudioTests {
    private struct Denied: MicrophoneAuthorizer {
        func status() -> MicrophoneAccess { .denied }
        func requestAccess() async -> Bool { false }
    }

    @Test func aQARunWithoutAFileHearsSilence() async throws {
        let input = try #require(DictationQAPlayback().input(isQARun: true))
        #expect(input is QASilentAudioInput)
        let stream = try await input.start { _ in }
        var chunks: [[Float]] = []
        for await chunk in stream {
            chunks.append(chunk)
            if chunks.count == 2 { break }
        }
        await input.stop()
        #expect(chunks.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0 == 0 } })
    }

    @Test func thePlayedFileWinsAndOtherRunsKeepTheRealMicrophone() {
        let playback = DictationQAPlayback()
        #expect(playback.input(isQARun: false) == nil)
        playback.url = URL(filePath: "/tmp/dictation.wav")
        #expect(playback.input(isQARun: true) is WAVFileAudioInput)
        #expect(playback.input(isQARun: false) is WAVFileAudioInput)
    }

    @Test func aQARunNeverAsksForThePermission() async {
        let playback = DictationQAPlayback()
        let qa = DictationQAAuthorizer(playback: playback, base: Denied(), isQARun: true)
        #expect(qa.status() == .granted)
        #expect(await qa.requestAccess())
        let real = DictationQAAuthorizer(playback: playback, base: Denied())
        #expect(real.status() == .denied)
        #expect(await real.requestAccess() == false)
    }
}
#endif

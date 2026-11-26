#if DEBUG
import Foundation
import Testing

@testable import LintelApp

@Suite struct QAMeetingOptionsTests {
    @Test func parsesTheMeetingAudioFilesAndTheSpoolFolder() throws {
        let options = try #require(
            try QAOptions.parse([
                "Lintel", "--qa-meeting-mic-wav", "/tmp/mic.wav", "--qa-meeting-system-wav", "/tmp/system.wav",
                "--qa-meeting-spool-dir", "/tmp/spool",
            ])
        )
        #expect(options.meetingMicWAV?.path == "/tmp/mic.wav")
        #expect(options.meetingSystemWAV?.path == "/tmp/system.wav")
        #expect(options.meetingSpoolDirectory?.path == "/tmp/spool")
        #expect(try QAOptions.parse(["--qa"])?.meetingMicWAV == nil)
    }

    @Test func everyQARunSwitchesMeetingsAndDictationToFilesOrSilence() throws {
        let plain = AppEnvironment.qaAudioSettings([:], options: try #require(try QAOptions.parse(["--qa"])))
        #expect(plain[QAOptions.meetingsAudioKey] == .bool(true))
        #expect(plain[QAOptions.dictationAudioKey] == .bool(true))
        #expect(plain[QAOptions.meetingsMicWAVKey] == nil)
        // A `--qa-setting` cannot turn the switch off.
        let forced = AppEnvironment.qaAudioSettings(
            [QAOptions.meetingsAudioKey: .bool(false), QAOptions.dictationAudioKey: .bool(false)],
            options: try #require(try QAOptions.parse(["--qa"])))
        #expect(forced[QAOptions.meetingsAudioKey] == .bool(true))
        #expect(forced[QAOptions.dictationAudioKey] == .bool(true))
    }

    @Test func theFlagsFilesAndSpoolFolderReachThePluginsSettings() throws {
        let options = try #require(
            try QAOptions.parse([
                "--qa", "--qa-meeting-mic-wav", "/tmp/mic.wav", "--qa-meeting-system-wav", "/tmp/system.wav",
                "--qa-meeting-spool-dir", "/tmp/spool",
            ]))
        let settings = AppEnvironment.qaAudioSettings([:], options: options)
        #expect(settings[QAOptions.meetingsMicWAVKey] == .string("/tmp/mic.wav"))
        #expect(settings[QAOptions.meetingsSystemWAVKey] == .string("/tmp/system.wav"))
        #expect(settings[QAOptions.meetingsSpoolDirectoryKey] == .string("/tmp/spool"))
    }

    @Test func qaNotesTurnsOnTheFixturesKeyOnly() throws {
        #expect(try QAOptions.parse(["--qa-notes"])?.notesFixtures == true)
        #expect(try QAOptions.parse(["--qa"])?.notesFixtures == false)
        let on = AppEnvironment.qaNotesSettings(["plugins.x": .bool(true)], fixtures: true)
        #expect(on == ["plugins.x": .bool(true), QAOptions.notesFixturesKey: .bool(true)])
        #expect(AppEnvironment.qaNotesSettings([:], fixtures: false).isEmpty)
    }

    @Test func qaSnapshotTakesAPathAndNotesOpenTabsComeFromASetting() throws {
        #expect(try QAOptions.parse(["--qa-snapshot", "/tmp/window.png"])?.snapshotPath == "/tmp/window.png")
        #expect(try QAOptions.parse(["--qa"])?.snapshotPath == nil)
        #expect(throws: QAOptions.ParseError.missingValue("--qa-snapshot")) {
            try QAOptions.parse(["--qa-snapshot"])
        }
        let options = try QAOptions.parse(["--qa-setting", "plugins.notes.qaOpen=meetings:a@transcript"])
        #expect(options?.settings["plugins.notes.qaOpen"] == .string("meetings:a@transcript"))
    }

    @Test func rejectsAMissingOrOptionLikeValue() {
        #expect(throws: QAOptions.ParseError.missingValue("--qa-meeting-mic-wav")) {
            _ = try QAOptions.parse(["--qa-meeting-mic-wav"])
        }
        #expect(throws: QAOptions.ParseError.invalidValue("--qa-meeting-system-wav", "--qa")) {
            _ = try QAOptions.parse(["--qa-meeting-system-wav", "--qa"])
        }
    }
}
#endif

import Foundation
import Testing

@testable import MeetingsPlugin

/// Measurement only (spec `2026-11-25-meeting-notes-structure`, F2 and F3): the guard of THIS build over the MAP
/// answers an earlier run saved (`<name>.notes-rejections.json`), so a change of the guard is measured on exactly
/// the same proposals (the model's answers differ from run to run). Off unless
/// `LINTEL_NOTES_REGUARD_DUMP=<saved dump>`, `LINTEL_NOTES_REGUARD_TRANSCRIPT=<EvalResult.json>` and
/// `LINTEL_NOTES_REGUARD_OUT=<folder>` are set; the new dump (it holds meeting text) goes only to that folder,
/// mode 0600, and stdout gets numbers only.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["LINTEL_NOTES_REGUARD_DUMP"] != nil))
struct RegardDumpTests {
    @Test func theGuardOfThisBuildOverSavedMapAnswers() throws {
        let environment = ProcessInfo.processInfo.environment
        let dumpURL = URL(filePath: try #require(environment["LINTEL_NOTES_REGUARD_DUMP"]))
        let transcriptURL = URL(filePath: try #require(environment["LINTEL_NOTES_REGUARD_TRANSCRIPT"]))
        let out = URL(filePath: try #require(environment["LINTEL_NOTES_REGUARD_OUT"]), directoryHint: .isDirectory)
        let saved = try JSONDecoder().decode(NotesRejectionReport.self, from: Data(contentsOf: dumpURL))
        let transcript = try JSONDecoder().decode(EvalResult.self, from: Data(contentsOf: transcriptURL))
        let utterances = transcript.asr.segments.map {
            NotesUtterance(startMs: $0.startMs, speaker: $0.speaker ?? "?", text: $0.text)
        }
        let records = saved.answers.map {
            RecordingRuntime.Record(
                isMap: true, maxTokens: $0.maxTokens, response: $0.response, stoppedByTokenLimit: $0.stoppedByTokenLimit
            )
        }
        let written = try #require(
            try NotesRejectionReport.writeIfEnabled(
                true, recording: saved.recording, records: records, utterances: utterances, to: out))
        print(
            "REGUARD rules=\(NotesGuard.rulesVersion) points=\(written.report.pointCount)"
                + " rejected=\(written.report.rejectedCount)")
    }
}

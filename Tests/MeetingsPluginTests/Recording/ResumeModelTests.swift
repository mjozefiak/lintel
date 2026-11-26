import LintelSpeech
import Testing

@testable import MeetingsPlugin

/// Which speech model a resumed meeting is transcribed with (#314). Pure: the resumer then looks the package up
/// where Lintel installed it.
@Suite struct ResumeModelTests {
    private let parakeet = ModelCatalog.parakeetUltra
    private let whisper = ModelCatalog.whisperLargeV3Turbo

    @Test func theStoredModelWinsOverTheOneChosenInSettingsNow() {
        // Settings now says Parakeet; the meeting was recorded with Whisper (and the other way round).
        #expect(MeetingsRuntime.resumePackage(storedModelID: whisper.id, selected: parakeet) == whisper)
        #expect(MeetingsRuntime.resumePackage(storedModelID: parakeet.id, selected: whisper) == parakeet)
    }

    @Test func aRowThatRecordedNoModelFollowsTheChoiceInSettings() {
        #expect(MeetingsRuntime.resumePackage(storedModelID: "", selected: whisper) == whisper)
    }

    @Test func aStoredModelThatIsNoLongerInTheCatalogIsGoneAndNothingElseIsUsed() {
        #expect(MeetingsRuntime.resumePackage(storedModelID: "removed-model", selected: parakeet) == nil)
    }

    /// The resumer the runtime builds asks for the meeting's stored model, for the detector and the engine alike.
    /// `MeetingsRuntime.makeResumer` builds the real engines and needs an installed model, so no test can run it:
    /// the wiring is checked in the source, where a return to the model chosen in Settings would show.
    @Test func theRuntimeNeverResumesWithTheModelChosenNow() throws {
        let source = try String(
            contentsOf: TestPaths.meetingsSource(named: "MeetingsRuntime.swift"), encoding: .utf8)
        #expect(!source.contains("runtime.speechLookup()"), "the resumer reads the current selection again")
        #expect(
            source.components(separatedBy: "runtime.speechLookup(for: modelID)").count - 1 == 2,
            "the detector and the engine no longer both use the stored model")
    }
}

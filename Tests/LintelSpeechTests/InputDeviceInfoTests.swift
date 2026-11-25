import Testing

@testable import LintelSpeech

@Suite struct InputDeviceInfoTests {
    @Test func theLogLineHasTheDeviceFactsAndNoAudio() {
        let info = InputDeviceInfo(name: "AirPods", uid: "AA-BB", sampleRate: 24_000, channels: 1)
        #expect(info.logDescription == "name=AirPods, uid=AA-BB, sampleRate=24000, channels=1")
    }

    @Test func aCaptureErrorNamesItsCaseForTheLog() {
        #expect(String(describing: CaptureError.noInputDevice) == "noInputDevice")
        #expect(String(describing: CaptureError.converterUnavailable) == "converterUnavailable")
        #expect(String(describing: CaptureError.engineFailed("-10868")) == "engineFailed(-10868)")
    }
}

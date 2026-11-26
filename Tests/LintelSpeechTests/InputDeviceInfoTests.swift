import Testing

@testable import LintelSpeech

@Suite struct InputDeviceInfoTests {
    /// Issue #269: a device's name often carries a person's name and a Bluetooth device's UID its hardware
    /// address, so the log line hashes both (the first 4 bytes of SHA-256, like `NotesLog.hashedKey`) and keeps
    /// only the sample rate and the channel count readable. The hashes are literals here on purpose: the test
    /// fails if the format or the hashing changes.
    @Test func theLogLineHashesTheNameAndTheUIDAndKeepsTheNumbersReadable() {
        let info = InputDeviceInfo(name: "AirPods", uid: "AA-BB", sampleRate: 24_000, channels: 1)
        #expect(info.logDescription == "name=#9e5b09a1, uid=#00d8eb47, sampleRate=24000, channels=1")
        #expect(!info.logDescription.contains("AirPods"))
        #expect(!info.logDescription.contains("AA-BB"))
    }

    /// Two lines about one device still match, whatever its format; two devices do not look alike.
    @Test func theHashesAreStableAndDifferentPerDevice() {
        let first = InputDeviceInfo(name: "Anna's AirPods Pro", uid: "00-11-22", sampleRate: 48_000, channels: 2)
        let same = InputDeviceInfo(name: "Anna's AirPods Pro", uid: "00-11-22", sampleRate: 44_100, channels: 1)
        let other = InputDeviceInfo(name: "Yeti", uid: "33-44-55", sampleRate: 48_000, channels: 2)
        func identity(_ info: InputDeviceInfo) -> String {
            info.logDescription.components(separatedBy: ", sampleRate=")[0]
        }
        #expect(identity(first) == identity(same))
        #expect(identity(first) != identity(other))
        #expect(!first.logDescription.contains("AirPods"))
        #expect(!first.logDescription.contains("00-11-22"))
    }

    @Test func aCaptureErrorNamesItsCaseForTheLog() {
        #expect(String(describing: CaptureError.noInputDevice) == "noInputDevice")
        #expect(String(describing: CaptureError.converterUnavailable) == "converterUnavailable")
        #expect(String(describing: CaptureError.engineFailed("-10868")) == "engineFailed(-10868)")
    }
}

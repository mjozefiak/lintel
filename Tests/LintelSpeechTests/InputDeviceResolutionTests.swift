import Testing

@testable import LintelSpeech

@Suite struct InputDeviceResolutionTests {
    private let usbUID = "AppleUSBAudioEngine:MICE MICROPHONE:USB MICROPHONE:201308:1"
    private let builtIn = MicrophoneCapture.InputDevice(uid: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone")

    @Test func noChoiceFollowsTheSystemInput() {
        for uid in [nil, ""] as [String?] {
            #expect(
                InputDeviceResolution.resolve(
                    requestedUID: uid, requestedName: nil, available: [builtIn], defaultInputName: "X")
                    == .systemDefault)
        }
    }

    @Test func aChosenDeviceThatIsListedIsUsed() {
        let usb = MicrophoneCapture.InputDevice(uid: usbUID, name: "USB MICROPHONE")
        #expect(
            InputDeviceResolution.resolve(
                requestedUID: usbUID, requestedName: "USB MICROPHONE", available: [builtIn, usb],
                defaultInputName: "MacBook Pro Microphone") == .chosen(uid: usbUID))
    }

    @Test func aChosenDeviceThatIsNotListedFallsBackToTheDefaultInputWithBothNames() {
        let resolution = InputDeviceResolution.resolve(
            requestedUID: usbUID, requestedName: "USB MICROPHONE", available: [builtIn],
            defaultInputName: "MacBook Pro Microphone")
        #expect(
            resolution
                == .fallback(InputFallback(requestedName: "USB MICROPHONE", usingName: "MacBook Pro Microphone")))
    }

    @Test func theStoredNameWinsOverTheOneReadFromTheUID() {
        let resolution = InputDeviceResolution.resolve(
            requestedUID: usbUID, requestedName: "Desk mic", available: [], defaultInputName: nil)
        #expect(resolution == .fallback(InputFallback(requestedName: "Desk mic", usingName: nil)))
    }

    @Test func aUSBUIDWithoutAStoredNameStillGivesTheProductName() {
        let resolution = InputDeviceResolution.resolve(
            requestedUID: usbUID, requestedName: nil, available: [builtIn], defaultInputName: "MacBook Pro Microphone")
        #expect(
            resolution
                == .fallback(InputFallback(requestedName: "USB MICROPHONE", usingName: "MacBook Pro Microphone")))
    }

    @Test func otherUIDsAreNeverShownAsAName() {
        #expect(InputDeviceResolution.displayName(ofUID: "AA-BB-CC-DD-EE-FF:input") == nil)
        #expect(InputDeviceResolution.displayName(ofUID: "AppleUSBAudioEngine:Vendor") == nil)
        #expect(InputDeviceResolution.displayName(ofUID: "AppleUSBAudioEngine:Vendor: :1:1") == nil)
        let resolution = InputDeviceResolution.resolve(
            requestedUID: "AA-BB-CC-DD-EE-FF:input", requestedName: nil, available: [], defaultInputName: "Built-in")
        #expect(resolution == .fallback(InputFallback(requestedName: nil, usingName: "Built-in")))
        #expect(InputDeviceResolution.displayName(ofUID: usbUID) == "USB MICROPHONE")
    }

    @Test func theMessageNamesDevicesAndNeverAUID() {
        let all = InputFallback(requestedName: "USB MICROPHONE", usingName: "MacBook Pro Microphone").message
        #expect(all == "Microphone “USB MICROPHONE” is unavailable – recording from “MacBook Pro Microphone”")
        let noUsing = InputFallback(requestedName: "USB MICROPHONE", usingName: nil).message
        #expect(noUsing == "Microphone “USB MICROPHONE” is unavailable – recording from the system input")
        let noRequested = InputFallback(requestedName: nil, usingName: "Built-in").message
        #expect(noRequested == "The chosen microphone is unavailable – recording from “Built-in”")
        let none = InputFallback(requestedName: nil, usingName: nil).message
        #expect(none == "The chosen microphone is unavailable – recording from the system input")
        for text in [all, noUsing, noRequested, none] { #expect(!text.contains("AppleUSBAudioEngine")) }
    }
}

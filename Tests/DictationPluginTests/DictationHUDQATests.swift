#if DEBUG
import Testing

@testable import DictationPlugin

@Suite @MainActor struct DictationHUDQATests {
    @Test func everyStateNameIsUniqueAndResolves() {
        let names = DictationHUDQA.states.map(\.name)
        #expect(Set(names).count == names.count)
        for name in names { #expect(DictationHUDQA.state(named: name) != nil) }
        #expect(DictationHUDQA.state(named: "no-such-state") == nil)
    }

    @Test func theListCoversTheStatesOfTheHUD() {
        let states = DictationHUDQA.states.map(\.state)
        #expect(states.contains(.allowMicrophone))
        #expect(states.contains(.finishing))
        #expect(states.contains(.pasted))
        #expect(states.contains(.pastedUnformatted(all: true)))
        #expect(states.contains(.pastedUnformatted(all: false)))
        #expect(states.contains(.problem(.nothingToPaste)))
        #expect(states.contains(.problem(.speechModelBusy)))
        let recordings = states.filter { if case .recording = $0 { true } else { false } }
        #expect(recordings.count == 7)
        // Every state has its words; none is blank. A partial cleanup is the one state that shows nothing (OD-4).
        for state in states where state != .pastedUnformatted(all: false) {
            #expect(!state.accessibilityLabel().isEmpty)
            #expect(state.pill() != nil)
        }
    }

    @Test func thePanelHasTheIdentifierTheShellLooksFor() {
        #expect(DictationHUDQA.panelIdentifier == "lintel.qa.hud")
        #expect(DictationHUDQA.settingName == "qaHUD")
        #expect(DictationHUDQA.hoverSettingName == "qaHUDHover")
    }

    @Test func theMicrophoneAndEscapeFixturesHaveTheirOwnStates() throws {
        guard case .recording(let unclaimed)? = DictationHUDQA.state(named: "recording-escape-unclaimed") else {
            Issue.record("no recording")
            return
        }
        #expect(!unclaimed.escapeCancels)
        guard case .recording(let unnamed)? = DictationHUDQA.state(named: "recording-microphone-fallback-unnamed")
        else {
            Issue.record("no recording")
            return
        }
        #expect(unnamed.fallback != nil && unnamed.fallback?.usingName == nil)
        let named = try #require(DictationHUDQA.fixture(named: "recording-microphone-fallback"))
        let collapsed = try #require(DictationHUDQA.fixture(named: "recording-microphone-fallback-collapsed"))
        #expect(!named.lineCollapsed && collapsed.lineCollapsed)
        #expect(named.state == collapsed.state)
        #expect(
            DictationHUDQA.states.filter(\.lineCollapsed).map(\.name) == ["recording-microphone-fallback-collapsed"])
    }
}
#endif

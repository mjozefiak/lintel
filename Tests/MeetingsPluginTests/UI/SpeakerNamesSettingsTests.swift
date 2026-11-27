import Foundation
import LintelKit
import Testing

@testable import MeetingsPlugin

/// Settings → Meetings → Speaker names: "From the conversation" (`plugins.meetings.namesFromConversation`).
@MainActor
@Suite struct SpeakerNamesSettingsTests {
    private static let key = "plugins.meetings.namesFromConversation"

    @Test func theSettingIsOnByDefaultAndReadsAStoredValue() throws {
        let rig = try SettingsRig()
        #expect(MeetingsSettings.defaultNamesFromConversation)
        #expect(rig.harness.meetingsSettings.namesFromConversation)
        #expect(rig.harness.settings.value(forKey: Self.key) == nil)
        rig.harness.meetingsSettings.setNamesFromConversation(false)
        #expect(rig.harness.meetingsSettings.namesFromConversation == false)
    }

    @Test func theSwitchWritesOnlyWhenTheUserFlipsIt() throws {
        let rig = try SettingsRig()
        #expect(rig.model.namesFromConversation)
        rig.model.namesFromConversation = true
        #expect(rig.harness.settings.value(forKey: Self.key) == nil)
        rig.model.namesFromConversation = false
        #expect(rig.harness.settings.value(forKey: Self.key) == .bool(false))
        #expect(rig.harness.meetingsSettings.namesFromConversation == false)
    }

    @Test func theSwitchFollowsTheNotesSwitch() throws {
        let rig = try SettingsRig()
        rig.model.notes.enabled = true
        #expect(rig.model.notesEnabledForNames)
        rig.model.notes.enabled = false
        #expect(rig.model.notesEnabledForNames == false)
        // Turning notes off does not change the stored choice: it only makes the switch inactive.
        #expect(rig.model.namesFromConversation)
        #expect(rig.harness.settings.value(forKey: Self.key) == nil)
    }

    @Test func theSwitchIsInactiveWhileNotesAreOff() throws {
        let pane = try String(
            contentsOf: TestPaths.meetingsSource(named: "MeetingsSettingsPane.swift"), encoding: .utf8)
        let section = try #require(pane.range(of: "struct SpeakerNamesSection"))
        let body = pane[section.lowerBound...]
        #expect(body.contains(".disabled(!model.notesEnabledForNames)"))
        #expect(body.contains("\"Works when notes are on.\""))
    }
}

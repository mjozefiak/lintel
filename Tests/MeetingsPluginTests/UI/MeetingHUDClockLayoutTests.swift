import Foundation
import Testing

@testable import MeetingsPlugin

@Suite struct MeetingHUDClockLayoutTests {
    /// The HUD is a fixed 400 pt wide; a notice with a second button (consent, no system audio, no microphone
    /// audio) must squeeze the buttons and the level meters, never the clock, so the clock stays on one line
    /// (issue #233). A rendered-pixel test would be brittle, so this pins the two modifiers in the source.
    @Test func theClockIsPinnedToOneLine() throws {
        let source = try String(contentsOf: TestPaths.meetingsSource(named: "MeetingHUD.swift"), encoding: .utf8)
        let anchor = try #require(source.range(of: "Text(MeetingHUDState.clock(recording.elapsedSeconds))"))
        let next = source[anchor.upperBound...].prefix(300)
        #expect(next.contains(".lineLimit(1)"))
        #expect(next.contains(".fixedSize(horizontal: true, vertical: false)"))
    }

    /// The recording row must fit the 386 pt content width in every state (issue #233, review round 2): the
    /// meters give way (labelled, bare, none), never the clock or the buttons.
    @Test func theMetersGiveWayBeforeTheButtons() throws {
        let source = try String(contentsOf: TestPaths.meetingsSource(named: "MeetingHUD.swift"), encoding: .utf8)
        #expect(source.contains("ViewThatFits(in: .horizontal)"))
        for variant in [".labelled", ".bare", ".hidden"] {
            #expect(source.contains("headerRow(state, meters: \(variant))"))
        }
    }
}

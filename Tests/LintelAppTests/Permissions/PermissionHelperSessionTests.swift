import Testing

@testable import LintelApp

/// Spec 2026-11-24 Phase 2, step 2.5: when the helper follows Settings, where it sits and when it closes.
@Suite struct PermissionHelperSessionTests {
    typealias Session = PermissionHelperSession

    private func session() -> Session { Session(openedAt: .zero) }

    @Test func itOpensSearchingForTheSettingsWindow() {
        let session = session()
        #expect(session.phase == .open)
        #expect(session.placement == .searching)
    }

    @Test func itFollowsTheWindowOnceFound() {
        var session = session()
        session.apply(.settingsWindow(found: true), at: .seconds(1))
        #expect(session.placement == .followingSettings)
    }

    @Test func itSitsBesideLintelWhenNoWindowAppearsWithinThreeSeconds() {
        var session = session()
        session.apply(.settingsWindow(found: false), at: .seconds(2))
        #expect(session.placement == .searching)
        session.apply(.settingsWindow(found: false), at: .seconds(3))
        #expect(session.placement == .besideLintel)
        // The window shows up later: the panel goes to it.
        session.apply(.settingsWindow(found: true), at: .seconds(4))
        #expect(session.placement == .followingSettings)
    }

    @Test func aWindowThatDisappearsMovesThePanelBesideLintelAfterTheGrace() {
        var session = session()
        session.apply(.settingsWindow(found: true), at: .seconds(1))
        session.apply(.settingsWindow(found: false), at: .seconds(2))
        #expect(session.placement == .followingSettings)
        session.apply(.settingsWindow(found: false), at: .seconds(4))
        #expect(session.placement == .besideLintel)
    }

    @Test func aGrantShowsAllowedForOneSecondThenCloses() {
        var session = session()
        session.apply(.granted, at: .seconds(5))
        #expect(session.showsAllowed)
        session.apply(.tick, at: .milliseconds(5900))
        #expect(session.showsAllowed)
        session.apply(.tick, at: .seconds(6))
        #expect(session.phase == .closed(.granted))
    }

    @Test func settingsQuittingClosesItOnlyAfterItWasSeenRunning() {
        var early = session()
        early.apply(.settingsRunning(false), at: .seconds(1))
        #expect(early.phase == .open, "System Settings may still be launching")

        var session = session()
        session.apply(.settingsRunning(true), at: .seconds(1))
        session.apply(.settingsRunning(false), at: .seconds(20))
        #expect(session.phase == .closed(.settingsQuit))
    }

    @Test func doneClosesItAtOnce() {
        var session = session()
        session.apply(.doneTapped, at: .seconds(2))
        #expect(session.phase == .closed(.done))
        session.apply(.granted, at: .seconds(3))
        #expect(session.phase == .closed(.done), "a closed session ignores everything")
    }

    @Test func itClosesAfterTenMinutesWithoutAGrant() {
        var session = session()
        session.apply(.settingsWindow(found: true), at: .seconds(599))
        #expect(session.phase == .open)
        session.apply(.tick, at: .seconds(600))
        #expect(session.phase == .closed(.timedOut))
    }

    @Test func settingsQuittingDoesNotCutTheAllowedStateShort() {
        var session = session()
        session.apply(.settingsRunning(true), at: .seconds(1))
        session.apply(.granted, at: .seconds(2))
        session.apply(.settingsRunning(false), at: .milliseconds(2300))
        #expect(session.showsAllowed)
        session.apply(.tick, at: .seconds(3))
        #expect(session.phase == .closed(.granted))
    }
}

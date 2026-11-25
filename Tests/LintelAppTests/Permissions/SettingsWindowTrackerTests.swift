import CoreGraphics
import Testing

@testable import LintelApp

/// Spec 2026-11-24 Phase 2, step 2.4: which window the permission helper follows.
@Suite struct SettingsWindowTrackerTests {
    private let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let settings: Set<pid_t> = [500]

    private func window(
        pid: pid_t = 500, _ frame: CGRect = CGRect(x: 200, y: 100, width: 700, height: 500), layer: Int = 0,
        onScreen: Bool = true
    ) -> WindowSample {
        WindowSample(ownerPID: pid, bounds: frame, layer: layer, isOnScreen: onScreen)
    }

    private func frame(_ windows: [WindowSample], displays: [CGRect]? = nil) -> CGRect? {
        SettingsWindowTracker.frame(in: windows, settingsPIDs: settings, displays: displays ?? [display])
    }

    @Test func noWindowsGivesNil() {
        #expect(frame([]) == nil)
    }

    @Test func otherAppsWindowsAreIgnored() {
        #expect(frame([window(pid: 77), window(pid: 78)]) == nil)
    }

    @Test func theSettingsWindowIsFound() {
        let target = CGRect(x: 300, y: 120, width: 760, height: 540)
        #expect(frame([window(pid: 77), window(target)]) == target)
    }

    @Test func theFrontMostOfTwoSettingsWindowsWins() {
        let front = CGRect(x: 10, y: 10, width: 600, height: 400)
        let back = CGRect(x: 400, y: 300, width: 800, height: 600)
        #expect(frame([window(front), window(back)]) == front)
    }

    @Test func offScreenAndOverlayWindowsAreIgnored() {
        #expect(frame([window(onScreen: false)]) == nil)
        #expect(frame([window(layer: 25)]) == nil)
        // A window parked on a display that is gone.
        #expect(frame([window(CGRect(x: 5000, y: 0, width: 700, height: 500))]) == nil)
    }

    @Test func aSheetOrPopoverTooSmallToBeTheWindowIsIgnored() {
        #expect(frame([window(CGRect(x: 200, y: 100, width: 280, height: 160))]) == nil)
    }

    @Test func aWindowOnASecondDisplayIsFound() {
        let second = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        let target = CGRect(x: 2200, y: 100, width: 700, height: 500)
        #expect(frame([window(target)], displays: [display, second]) == target)
    }
}

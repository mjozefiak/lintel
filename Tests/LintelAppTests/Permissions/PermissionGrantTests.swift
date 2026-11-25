import AppKit
import CoreGraphics
import Foundation
import LintelKit
import Testing

@testable import LintelApp

/// Spec 2026-11-24 Phase 2, steps 2.2 and 2.6, and issue #71: a grant given in System Settings shows without a
/// restart, and Accessibility means `AXIsProcessTrusted()`.
@MainActor
@Suite(.serialized) struct PermissionGrantTests {
    let env: TestEnvironment

    init() throws {
        env = try TestEnvironment()
    }

    private func service(
        reader: FakePermissionsReader, requester: FakePermissionRequester = FakePermissionRequester(),
        opened: OpenedURLs = OpenedURLs(), pollInterval: Duration = .milliseconds(5)
    ) -> PermissionGrantService {
        PermissionGrantService(
            reader: reader, requester: requester, openURL: { opened.urls.append($0) }, pollInterval: pollInterval,
            notificationCenter: nil)
    }

    // MARK: Accessibility means AXIsProcessTrusted (#71)

    @Test func accessibilityIsGrantedExactlyWhenTheProcessIsTrusted() {
        #expect(AccessibilityAccess.status(axTrusted: true) == .granted)
        #expect(AccessibilityAccess.status(axTrusted: false) == .denied)
    }

    @Test func pasteKeepsTheOlderPostEventGrantAndAcceptsTheAccessibilityOne() {
        #expect(AccessibilityAccess.canPostEvents(axTrusted: true, postEvent: false))
        #expect(AccessibilityAccess.canPostEvents(axTrusted: false, postEvent: true))
        #expect(AccessibilityAccess.canPostEvents(axTrusted: true, postEvent: true))
        #expect(!AccessibilityAccess.canPostEvents(axTrusted: false, postEvent: false))
    }

    @Test func theSystemReaderAnswersAccessibilityFromTheLiveTrustCheck() {
        let trusted = Locked(false)
        let reader = SystemPermissionsReader(accessibilityTrusted: { trusted.value })
        #expect(reader.status(of: .accessibility) == .denied)
        trusted.value = true
        #expect(reader.status(of: .accessibility) == .granted)
        trusted.value = false
        #expect(reader.status(of: .accessibility) == .denied)
    }

    @Test func aQAOverrideStillWinsOverTheTrustCheck() {
        let reader = SystemPermissionsReader(accessibilityOverride: .denied, accessibilityTrusted: { true })
        #expect(reader.status(of: .accessibility) == .denied)
    }

    // MARK: The pane, the plugin banner and the shell show the grant after the next re-read (#71 acceptance)

    @Test func theBannerAndThePaneShowAnAccessibilityGrantAfterTheNextRead() async {
        defer { env.tearDown() }
        let reader = FakePermissionsReader()
        reader.answers[.accessibility] = .denied
        reader.answers[.pasteboard] = .granted
        let host = env.makeHost([PastingPlugin.self])
        await host.start()
        let settings = SettingsHostModel(host: host, reader: reader)
        settings.show("pasting")
        #expect(settings.needsLiveRefresh)
        let before = settings.banner
        #expect(before?.level != .ok)

        let pane = PermissionsModel(host: host, reader: reader) { _ in }
        pane.refresh()
        #expect(pane.status(of: .accessibility) == .denied)

        reader.answers[.accessibility] = .granted
        settings.liveTick()
        pane.refresh()

        #expect(settings.banner?.level == .ok)
        #expect(!settings.needsLiveRefresh)
        #expect(pane.status(of: .accessibility) == .granted)
    }

    @Test func theLiveTickDoesNothingWhileNoPermissionBannerIsShown() async {
        defer { env.tearDown() }
        let reader = FakePermissionsReader()
        let host = env.makeHost([PastingPlugin.self])
        await host.start()
        let settings = SettingsHostModel(host: host, reader: reader)
        #expect(!settings.needsLiveRefresh)
        let reads = reader.reads.count
        settings.liveTick()
        #expect(reader.reads.count == reads)
    }

    // MARK: PermissionGrantService

    @Test func buildingAServiceReadsNothingAndStatusReadsOnDemand() {
        let reader = FakePermissionsReader()
        reader.answers[.accessibility] = .denied
        let service = service(reader: reader)
        #expect(reader.reads.isEmpty, "banner redraws build models, and a model must not probe every permission")
        #expect(service.status(of: .accessibility) == .denied)
        #expect(reader.reads == [.accessibility])
    }

    @Test func aGrantIsOneChangeAndTheFirstReadIsNone() {
        let reader = FakePermissionsReader()
        reader.answers[.accessibility] = .denied
        let service = service(reader: reader)
        var changes: [Permission] = []
        service.onChange = { permission, _ in changes.append(permission) }
        service.refresh()
        #expect(service.status(of: .accessibility) == .denied)
        #expect(changes.isEmpty, "the first read is not a change")

        reader.answers[.accessibility] = .granted
        #expect(service.refresh() == [.accessibility])
        #expect(service.status(of: .accessibility) == .granted)
        #expect(changes == [.accessibility])

        #expect(service.refresh().isEmpty, "an unchanged read changes nothing")
        #expect(changes == [.accessibility])
    }

    @Test func aPermissionMacOSCannotReportStaysNotDetermined() {
        let service = service(reader: FakePermissionsReader())
        #expect(service.status(of: .systemAudioRecording) == .notDetermined)
        #expect(service.statuses[.systemAudioRecording] == nil)
    }

    @Test func watchingReReadsEveryIntervalAndStopsWithTheLastWatcher() async {
        let reader = FakePermissionsReader()
        reader.answers[.accessibility] = .denied
        let service = service(reader: reader)
        #expect(!service.isWatching)
        service.beginWatching()
        service.beginWatching()
        #expect(service.isWatching)

        reader.answers[.accessibility] = .granted
        await eventually { service.status(of: .accessibility) == .granted }
        #expect(service.status(of: .accessibility) == .granted)

        service.endWatching()
        #expect(service.isWatching, "one watcher is left")
        service.endWatching()
        #expect(!service.isWatching)
        service.endWatching()
        #expect(!service.isWatching, "an extra end never goes below zero")
    }

    @Test func becomingActiveReReadsWithoutWatching() async {
        let reader = FakePermissionsReader()
        reader.answers[.accessibility] = .denied
        let center = NotificationCenter()
        let service = PermissionGrantService(
            reader: reader, requester: FakePermissionRequester(), openURL: { _ in }, notificationCenter: center)
        #expect(service.status(of: .accessibility) == .denied)

        reader.answers[.accessibility] = .granted
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        await eventually { service.status(of: .accessibility) == .granted }
        #expect(service.status(of: .accessibility) == .granted)
    }

    // MARK: Asking

    @Test func microphoneAsksTheSystemOnceThenOpensSettingsAfterADenial() async {
        let reader = FakePermissionsReader()
        reader.answers[.microphone] = .notDetermined
        let requester = FakePermissionRequester()
        let opened = OpenedURLs()
        let service = service(reader: reader, requester: requester, opened: opened)

        await service.allow(.microphone)
        #expect(requester.requested == [.microphone])
        #expect(opened.urls.isEmpty, "the prompt is the whole interaction")

        reader.answers[.microphone] = .denied
        service.refresh()
        await service.allow(.microphone)
        #expect(requester.requested == [.microphone], "the prompt never comes back after a denial")
        #expect(opened.urls == [Permission.microphone.settingsURL])
    }

    @Test func accessibilityPromptsThenOpensItsPaneUnlessTheGrantAlreadyShows() async {
        let reader = FakePermissionsReader()
        reader.answers[.accessibility] = .denied
        let requester = FakePermissionRequester()
        let opened = OpenedURLs()
        let service = service(reader: reader, requester: requester, opened: opened)

        await service.allow(.accessibility)
        #expect(requester.requested == [.accessibility])
        #expect(opened.urls == [Permission.accessibility.settingsURL])

        // The user turned the switch on while the prompt was up: nothing opens.
        requester.onRequest = { reader.answers[.accessibility] = .granted }
        opened.urls.removeAll()
        await service.allow(.accessibility)
        #expect(service.status(of: .accessibility) == .granted)
        #expect(opened.urls.isEmpty)
    }

    @Test func fullDiskAccessAndTheOthersOnlyOpenTheirPane() async {
        let requester = FakePermissionRequester()
        let opened = OpenedURLs()
        let service = service(reader: FakePermissionsReader(), requester: requester, opened: opened)
        for permission in [Permission.fullDiskAccess, .pasteboard, .systemAudioRecording] {
            await service.allow(permission)
        }
        #expect(requester.requested.isEmpty)
        #expect(opened.urls.count == 3)
        #expect(opened.urls.first == Permission.fullDiskAccess.settingsURL)
    }

    @Test func thePlanFollowsTheMechanismTable() {
        func plan(_ permission: Permission, _ status: PermissionStatus = .denied) -> PermissionGrantPlan {
            .plan(for: permission, status: status)
        }
        #expect(plan(.microphone, .notDetermined) == .init(asksSystem: true, opensSettings: false, help: .none))
        #expect(plan(.microphone) == .init(asksSystem: false, opensSettings: true, help: .turnOnSwitch))
        #expect(plan(.accessibility) == .init(asksSystem: true, opensSettings: true, help: .turnOnSwitch))
        #expect(plan(.fullDiskAccess) == .init(asksSystem: false, opensSettings: true, help: .dragTile))
        #expect(plan(.systemAudioRecording).help == .turnOnSwitch)
        #expect(plan(.pasteboard).help == .none)
    }
}

/// URLs the service opened.
@MainActor
final class OpenedURLs {
    var urls: [URL] = []
}

/// A value two closures share across threads.
nonisolated final class Locked<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// Waits (up to two seconds) for `condition`, yielding to the main actor.
@MainActor
func eventually(_ condition: () -> Bool) async {
    for _ in 0..<400 where !condition() {
        try? await Task.sleep(for: .milliseconds(5))
    }
}

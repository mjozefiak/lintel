import Foundation
import LintelKit
import Testing

@testable import LintelApp

/// Owner decision 2026-11-24: the launcher shortcut is registered only while an active plugin searches (Apps, Files,
/// Windows), so with every launcher add-on off it does not take a key for a panel that finds nothing.
@MainActor
@Suite(.serialized) struct MainShortcutRegistrationTests {
    @Test func theServiceRegistersAndUnregistersWithoutForgettingTheShortcut() {
        let registrar = InMemoryHotkeyRegistrar()
        let service = HotkeyService(registrar: registrar, settings: InMemorySettingsStore()) { [] }
        service.setMainShortcutActive(true)
        #expect(registrar.handlers[.main] == nil, "nothing registers before start")

        service.start(onMainShortcut: {}, active: false)
        #expect(service.mainShortcut == .commandSpace)
        #expect(registrar.handlers[.main] == nil)
        #expect(!service.isMainShortcutActive)

        service.setMainShortcutActive(true)
        #expect(registrar.handlers[.main] != nil)
        #expect(service.isMainShortcutActive)

        service.setMainShortcutActive(false)
        #expect(registrar.handlers[.main] == nil)
        #expect(registrar.shortcut(for: .main) == .commandSpace)
        #expect(service.mainShortcut == .commandSpace)
    }

    @Test func startIsActiveByDefault() {
        let registrar = InMemoryHotkeyRegistrar()
        let service = HotkeyService(registrar: registrar, settings: InMemorySettingsStore()) { [] }
        service.start {}
        #expect(registrar.handlers[.main] != nil)
        #expect(service.isMainShortcutActive)
    }

    @Test func theShortcutFollowsTheFirstAndLastSearchingPlugin() async throws {
        let test = try TestEnvironment()
        defer { test.tearDown() }
        // Alpha searches; Beta (off by default) only has a command.
        test.settings.setValue(.bool(false), forKey: SettingsKeys.pluginEnabled("alpha"))
        let registrar = InMemoryHotkeyRegistrar()
        let coordinator = AppCoordinator(
            environment: test.environment, pluginTypes: [AlphaPlugin.self, BetaPlugin.self], registrar: registrar,
            occupiedShortcuts: { [] }, launchAtLogin: NoLaunchAtLogin())
        await coordinator.host.start()
        coordinator.hotkeys.start(onMainShortcut: {}, active: !coordinator.host.activeSources.isEmpty)
        #expect(registrar.handlers[.main] == nil)

        await coordinator.host.setEnabled(true, for: "beta")
        coordinator.pluginsChanged()
        #expect(registrar.handlers[.main] == nil, "a plugin without search sources does not need the launcher")

        await coordinator.host.setEnabled(true, for: "alpha")
        coordinator.pluginsChanged()
        #expect(registrar.handlers[.main] != nil)
        #expect(coordinator.hotkeys.isMainShortcutActive)

        await coordinator.host.setEnabled(false, for: "alpha")
        coordinator.pluginsChanged()
        #expect(registrar.handlers[.main] == nil)
        // The stored shortcut is kept for when a search add-on comes back.
        #expect(registrar.shortcut(for: .main) != nil)
    }

    @Test func theGeneralBannerSaysTheLauncherIsOff() {
        let off = ShellPaneBanners.general(shortcut: "⌃⌥Space", launcherIsActive: false)
        #expect(off.level == .neutral)
        #expect(off.title == "The launcher is off")
        #expect(off.detail == "Turn on Apps, Files or Window Management in Features to use the shortcut.")
        #expect(ShellPaneBanners.general(shortcut: "⌃⌥Space").level == .ok)
    }
}

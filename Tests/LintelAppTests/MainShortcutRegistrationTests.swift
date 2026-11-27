import Carbon.HIToolbox
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

    /// Storing a shortcut registers it with the system even without a handler (KeyboardShortcuts), so an inactive
    /// launcher gives the key back after the first default and after the user records another shortcut.
    @Test func anInactiveLauncherGivesTheKeyBackWheneverAShortcutIsStored() {
        let registrar = InMemoryHotkeyRegistrar()
        let service = HotkeyService(registrar: registrar, settings: InMemorySettingsStore()) { [] }
        service.start(onMainShortcut: {}, active: false)
        #expect(registrar.releases[.main] == 1, "the first launch stores the default")

        registrar.setShortcut(.controlOptionSpace, for: .main)
        service.userRecordedMainShortcut()
        #expect(registrar.releases[.main] == 2)
        #expect(service.mainShortcut == .controlOptionSpace, "the user's shortcut is kept")

        service.setMainShortcutActive(true)
        registrar.setShortcut(.commandSpace, for: .main)
        service.userRecordedMainShortcut()
        #expect(registrar.releases[.main] == 2, "an active launcher keeps its key")
        #expect(registrar.handlers[.main] != nil)

        service.setMainShortcutActive(false)
        service.setMainShortcutActive(false)
        #expect(registrar.releases[.main] == 3, "turning it off releases exactly once")
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

/// The coordinator hands the symbolic hot keys (`systemOccupiedShortcuts`) to the one-time default, so a key the
/// system takes makes a command fall back to its declared shortcut.
@MainActor
@Suite(.serialized) struct CommandDefaultWiringTests {
    @Test func aSystemShortcutOnTheDefaultMakesTheCoordinatorUseTheFallback() async throws {
        let test = try TestEnvironment()
        defer { test.tearDown() }
        let registrar = InMemoryHotkeyRegistrar()
        let coordinator = AppCoordinator(
            environment: test.environment, pluginTypes: [FallbackShortcutPlugin.self], registrar: registrar,
            occupiedShortcuts: { [] }, systemOccupiedShortcuts: { [.optionSpace] }, launchAtLogin: NoLaunchAtLogin())
        await coordinator.host.start()
        coordinator.pluginsChanged()
        let fallback = HotkeyShortcut(carbonKeyCode: kVK_ANSI_D, carbonModifiers: controlKey | optionKey)
        #expect(registrar.shortcut(for: .command(FallbackShortcutPlugin.commandID)) == fallback)
        #expect(
            coordinator.hotkeys.commandDefaultOutcomes[FallbackShortcutPlugin.commandID]
                == .fellBack(to: fallback, requested: .optionSpace, because: .systemHoldsIt))
    }
}

private final class FallbackShortcutPlugin: LintelPlugin {
    static let commandID = "fallback.record"
    static let manifest = PluginManifest(
        id: "fallback", displayName: "Fallback", symbolName: "mic", order: 1, defaultEnabled: true)

    init(context: PluginContext) {}

    func activate() async throws {}
    func deactivate() async {}

    var commands: [PluginCommand] {
        [
            PluginCommand(
                id: Self.commandID, title: "Record",
                defaultShortcut: KeyShortcut(key: " ", modifiers: .option),
                fallbackShortcut: KeyShortcut(key: "d", modifiers: [.control, .option]))
        ]
    }
}

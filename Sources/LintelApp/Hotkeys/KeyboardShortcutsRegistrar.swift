import Carbon.HIToolbox
import Foundation
import KeyboardShortcuts
import LintelKit

extension KeyboardShortcuts.Name {
    init(_ name: HotkeyName) {
        self.init(name.rawValue)
    }
}

extension HotkeyShortcut {
    init(_ shortcut: KeyboardShortcuts.Shortcut) {
        self.init(carbonKeyCode: shortcut.carbonKeyCode, carbonModifiers: shortcut.carbonModifiers)
    }

    var keyboardShortcut: KeyboardShortcuts.Shortcut {
        KeyboardShortcuts.Shortcut(carbonKeyCode: carbonKeyCode, carbonModifiers: carbonModifiers)
    }
}

/// Global shortcuts through KeyboardShortcuts: stored in `UserDefaults.standard` under
/// `KeyboardShortcuts_<name>` and registered with Carbon while a handler listens.
final class KeyboardShortcutsRegistrar: HotkeyRegistrar {
    private var listeners: [HotkeyName: Task<Void, Never>] = [:]

    func shortcut(for name: HotkeyName) -> HotkeyShortcut? {
        KeyboardShortcuts.getShortcut(for: .init(name)).map(HotkeyShortcut.init)
    }

    func setShortcut(_ shortcut: HotkeyShortcut?, for name: HotkeyName) {
        KeyboardShortcuts.setShortcut(shortcut?.keyboardShortcut, for: .init(name))
    }

    func setHandler(for name: HotkeyName, _ action: @escaping @MainActor () -> Void) {
        listeners[name]?.cancel()
        let events = KeyboardShortcuts.events(.keyDown, for: .init(name))
        listeners[name] = Task { @MainActor in
            for await _ in events {
                action()
            }
        }
    }

    func setKeyEventHandler(for name: HotkeyName, _ handler: @escaping @MainActor (KeyPhase) -> Void) {
        listeners[name]?.cancel()
        // One stream carries both phases, consumed by one loop on the main actor, so their order is the
        // stream's order.
        listeners[name] = Self.forward(KeyboardShortcuts.events(for: .init(name)), to: handler)
    }

    /// Hands each event of the stream to `handler` on the main actor, one at a time, in stream order.
    /// Cancelling the task ends the stream.
    static func forward(
        _ events: AsyncStream<KeyboardShortcuts.EventType>,
        to handler: @escaping @MainActor (KeyPhase) -> Void
    ) -> Task<Void, Never> {
        Task { @MainActor in
            for await event in events {
                handler(event == .keyDown ? .down : .up)
            }
        }
    }

    func claimEscape(_ action: @escaping @MainActor () -> Void) -> EscapeKeyClaim {
        CarbonEscapeRegistration.claim(action)
    }

    func canRegister(_ shortcut: HotkeyShortcut) -> Bool {
        CarbonHotkeyProbe.canRegister(shortcut)
    }

    func removeHandler(for name: HotkeyName) {
        // Cancelling ends the event stream and removes the handler. KeyboardShortcuts 1.10.0 does not give the key
        // back then (the name stays in its handler table), and `setShortcut` registers a shortcut that has no handler
        // at all, so the key is released here. `setHandler` registers it again.
        listeners.removeValue(forKey: name)?.cancel()
        KeyboardShortcuts.disable(.init(name))
        // Once more after what the library has already queued on the main queue (a listener's first registration).
        DispatchQueue.main.async { [weak self] in
            guard let self, self.listeners[name] == nil else { return }
            KeyboardShortcuts.disable(.init(name))
        }
    }
}

#if DEBUG
/// QA mode: shortcuts live in the in-memory registrar, and the recorder views read them from the
/// volatile registration domain, so nothing is persisted or registered with the system.
final class PreviewHotkeyRegistrar: HotkeyRegistrar {
    private let memory = InMemoryHotkeyRegistrar()

    func shortcut(for name: HotkeyName) -> HotkeyShortcut? { memory.shortcut(for: name) }

    func setShortcut(_ shortcut: HotkeyShortcut?, for name: HotkeyName) {
        memory.setShortcut(shortcut, for: name)
        let key = "KeyboardShortcuts_\(name.rawValue)"
        if let shortcut, let data = try? JSONEncoder().encode(shortcut.keyboardShortcut),
            let json = String(data: data, encoding: .utf8)
        {
            UserDefaults.standard.register(defaults: [key: json])
        }
    }

    func setHandler(for name: HotkeyName, _ action: @escaping @MainActor () -> Void) {}

    func setKeyEventHandler(for name: HotkeyName, _ handler: @escaping @MainActor (KeyPhase) -> Void) {}

    /// QA mode never takes the tester's Escape key.
    func claimEscape(_ action: @escaping @MainActor () -> Void) -> EscapeKeyClaim { .inactive }

    func canRegister(_ shortcut: HotkeyShortcut) -> Bool { memory.canRegister(shortcut) }

    func removeHandler(for name: HotkeyName) {}
}
#endif

/// Whether the system would accept a hot key: the call KeyboardShortcuts makes, attempted and given back at once.
///
/// The spike of onboarding step 4.2 measured what Carbon reports: a combination another app holds **without**
/// `kEventHotKeyExclusive` registers with `noErr`, and both apps then receive the key, so that conflict cannot be
/// detected (the Try dictation step handles it with "It didn't work"); one another app holds **exclusively** also
/// registers with `noErr` here, and the key then reaches only that app; and a combination this process already
/// holds answers `eventHotKeyExistsErr`, which is what a second of Lintel's own commands on one key looks like.
nonisolated enum CarbonHotkeyProbe {
    /// "LINT", so a probe that leaked a registration would still be recognisable in a log.
    private static let signature = OSType(0x4C49_4E54)

    static func canRegister(_ shortcut: HotkeyShortcut) -> Bool {
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.carbonKeyCode), UInt32(shortcut.carbonModifiers),
            EventHotKeyID(signature: signature, id: 0),
            GetEventDispatcherTarget(), 0, &reference)
        if let reference { UnregisterEventHotKey(reference) }
        return status == noErr
    }
}

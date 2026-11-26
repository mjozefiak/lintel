#if DEBUG
import LintelKit
import SwiftUI

/// DEBUG only: a `SettingsStore` over a dictionary in memory, no I/O (spec `2026-11-23-swiftui-design-gallery`). The
/// scenes of plugins and of the shell use it where the product reads the settings. `LintelApp`'s own in-memory store
/// is out of reach of the plugins, and `LintelKit` stays a contract without implementations.
public final class GallerySettingsStore: SettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: SettingValue]

    public init(_ values: [String: SettingValue] = [:]) {
        self.values = values
    }

    public func value(forKey key: String) -> SettingValue? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    public func setValue(_ value: SettingValue?, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }
}
#endif

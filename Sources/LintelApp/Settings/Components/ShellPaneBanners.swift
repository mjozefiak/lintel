import Foundation
import LintelKit

/// The banners of the shell's own panes (spec step 4.1, prototype `set-general`, `set-features` and
/// `set-permissions`), as data. Pure: `SettingsHostModel` reads them through its `shellBanners` seam while the
/// view draws. Advanced has no banner (prototype `set-advanced`); Models has its own (`ModelsPaneModel.banner`).
enum ShellPaneBanners {
    /// General: "Ready · Press ⌘Space to open Lintel.", or attention when no main shortcut is set.
    static func general(shortcut: String?, launcherIsActive: Bool = true) -> StatusDerivation.Banner {
        guard launcherIsActive else {
            // No plugin searches, so the shortcut is not registered (owner decision 2026-11-24).
            return StatusDerivation.Banner(
                level: .neutral,
                title: String(
                    localized: "The launcher is off", comment: "Settings → General banner: no plugin searches"),
                detail: String(
                    localized: "Turn on Apps, Files or Window Management in Features to use the shortcut.",
                    comment: "Settings → General banner detail: the main shortcut works once a search add-on is on"),
                actions: [])
        }
        guard let shortcut else {
            return StatusDerivation.Banner(
                level: .attention,
                title: String(localized: "No shortcut is set", comment: "Settings → General banner: no main shortcut"),
                detail: String(
                    localized: "Record one below to open Lintel from any app.",
                    comment: "Settings → General banner detail: no main shortcut"),
                actions: [])
        }
        return StatusDerivation.Banner(
            level: .ok, title: StatusDerivation.levelName(.ok),
            detail: String(
                localized: "Press \(shortcut) to open Lintel.",
                comment: "Settings → General banner detail; the main shortcut, for example ⌘Space"),
            actions: [])
    }

    /// What the Features banner needs to know about one plugin.
    struct Feature: Equatable {
        var name: String = ""
        let isEnabled: Bool
        let isFailed: Bool
        /// The level of the plugin's own settings banner when it is `attention` or `error`: the level that gives the
        /// plugin its dot in the sidebar (`StatusDerivation.attention`). `nil` for a feature that is off.
        var attention: SettingsStatus.Level? = nil
    }

    /// Features: attention for a feature that could not start, or for enabled features whose own pane says they need
    /// something (the same banners that give them a dot in the sidebar); else "All set · All features are on." or
    /// "Some features are off." A feature that cannot be turned off counts as on (`PluginHost.isEnabled`).
    static func features(_ features: [Feature]) -> StatusDerivation.Banner {
        if features.contains(where: \.isFailed) {
            return StatusDerivation.Banner(
                level: .attention,
                title: String(
                    localized: "A feature couldn't start", comment: "Settings → Features banner: a plugin failed"),
                detail: String(
                    localized: "Open its pane to try again. Nothing was deleted.",
                    comment: "Settings → Features banner detail: a plugin failed"),
                actions: [])
        }
        let waiting = features.filter { $0.isEnabled && $0.attention != nil }
        if !waiting.isEmpty {
            let names = waiting.map(\.name).formatted(.list(type: .and))
            return StatusDerivation.Banner(
                level: waiting.contains { $0.attention == .error } ? .error : .attention,
                title: StatusDerivation.levelName(.attention),
                detail: String(
                    localized: "Open \(names) in the sidebar to finish setting up.",
                    comment: "Settings → Features banner detail: the features whose panes have something to do"),
                actions: [])
        }
        let allOn = features.allSatisfy(\.isEnabled)
        return StatusDerivation.Banner(
            level: .ok,
            title: String(localized: "All set", comment: "Settings → Features banner"),
            detail: allOn
                ? String(localized: "All features are on.", comment: "Settings → Features banner detail")
                : String(localized: "Some features are off.", comment: "Settings → Features banner detail"),
            actions: [])
    }

    /// The banner of the Features pane. `reader` gives the permission states the sidebar dots use, so a feature
    /// that has a dot there is named here.
    static func features(host: PluginHost, reader: any PermissionsReader) -> StatusDerivation.Banner {
        features(
            host.entries.map {
                let id = $0.manifest.id
                let failed = if case .failed = $0.state { true } else { false }
                let enabled = host.isEnabled(id)
                return Feature(
                    name: String(localized: $0.manifest.displayName), isEnabled: enabled, isFailed: failed,
                    attention: enabled
                        ? StatusDerivation.attention(
                            SettingsHostModel.banner(for: id.rawValue, host: host, reader: reader))
                        : nil)
            })
    }

    /// Permissions: "N things to do" for every readable permission an enabled feature needs that is not allowed
    /// yet (denied or not asked), unless the active plugins that need it acknowledge running without it; else
    /// "Ready".
    static func permissions(
        requirements: [PermissionRequirement], status: (Permission) -> PermissionStatus,
        acknowledged: Set<Permission> = []
    ) -> StatusDerivation.Banner {
        let open = requirements.map(\.permission).filter { permission in
            permission.isReadable && !acknowledged.contains(permission) && status(permission) != .granted
        }
        guard !open.isEmpty else {
            return StatusDerivation.Banner(level: .ok, title: StatusDerivation.levelName(.ok), detail: nil, actions: [])
        }
        return StatusDerivation.Banner(
            level: .attention,
            title: String(
                localized: "\(open.count) things to do",
                comment: "Settings banner: the number of things needed (Permissions pane and plugin panes)"),
            detail: permissionsDetail(requirements.filter { open.contains($0.permission) }),
            actions: [])
    }

    /// "Meetings and Dictation can't start until Microphone is allowed."
    private static func permissionsDetail(_ open: [PermissionRequirement]) -> String {
        var features: [String] = []
        for name in open.flatMap(\.pluginNames) where !features.contains(name) { features.append(name) }
        let featureList = features.formatted(.list(type: .and))
        let permissionList = open.map(\.permission.title).formatted(.list(type: .and))
        if open.count == 1 {
            return String(
                localized: "\(featureList) can't start until \(permissionList) is allowed.",
                comment: "Settings → Permissions banner detail: the features and the one permission they wait for")
        }
        return String(
            localized: "\(featureList) can't start until \(permissionList) are allowed.",
            comment: "Settings → Permissions banner detail: the features and the permissions they wait for")
    }

    static func permissions(host: PluginHost, reader: any PermissionsReader) -> StatusDerivation.Banner {
        let model = PermissionsModel(host: host, reader: reader) { _ in }
        let enabled = host.entries.filter { host.isEnabled($0.manifest.id) }
        // Acknowledged only when every enabled plugin that needs it says so (Files without Full Disk Access).
        let acknowledged = Set(
            Permission.allCases.filter { permission in
                let needing = enabled.filter { $0.plugin.requiredPermissions.contains(permission) }
                return !needing.isEmpty
                    && needing.allSatisfy { entry in
                        entry.state.isActive
                            && (entry.plugin.settingsStatus?.acknowledgedPermissions.contains(permission) ?? false)
                    }
            })
        return permissions(
            requirements: model.requirements, status: { reader.status(of: $0) }, acknowledged: acknowledged)
    }
}

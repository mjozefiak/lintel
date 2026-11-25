import LintelKit

/// What the Allow button of one permission does (spec 2026-11-24, section 3, mechanism table), as data. Pure, so
/// the table is tested; `PermissionGrantService` carries it out.
nonisolated struct PermissionGrantPlan: Equatable, Sendable {
    /// What the floating helper shows next to the System Settings list.
    enum Help: Equatable, Sendable {
        /// No helper: the system prompt is the whole interaction.
        case none
        /// "Turn on the switch next to Lintel."
        case turnOnSwitch
        /// The Lintel icon to drag into the list, then the switch.
        case dragTile
    }

    /// Ask the system first (a prompt that adds Lintel to the list). Skipped once the system will not ask again.
    let asksSystem: Bool
    /// Open the permission's page in System Settings (after the prompt, when the grant is still missing).
    let opensSettings: Bool
    let help: Help

    /// The plan for `permission` given what is known now.
    static func plan(for permission: Permission, status: PermissionStatus) -> PermissionGrantPlan {
        switch permission {
        case .microphone:
            // The prompt comes once. After a denial it never comes back, and the list does not accept drops.
            if status == .notDetermined {
                return PermissionGrantPlan(asksSystem: true, opensSettings: false, help: .none)
            }
            return PermissionGrantPlan(asksSystem: false, opensSettings: true, help: .turnOnSwitch)
        case .accessibility:
            // The prompt adds Lintel with its switch off. The drag tile is the fallback for a Lintel that is
            // missing from the list; it needs the PR with the helper views, so this plan only names it.
            return PermissionGrantPlan(asksSystem: true, opensSettings: true, help: .turnOnSwitch)
        case .fullDiskAccess:
            // No API and no prompt: the only way is the list, and Lintel is not added to it.
            return PermissionGrantPlan(asksSystem: false, opensSettings: true, help: .dragTile)
        case .systemAudioRecording:
            // The first process tap makes the system prompt (the call-audio check). Until the spike shows that
            // the list accepts a drop, the helper only says to turn the switch on.
            return PermissionGrantPlan(asksSystem: false, opensSettings: true, help: .turnOnSwitch)
        case .pasteboard:
            // No documented pane: Privacy & Security opens, there is nothing to drag.
            return PermissionGrantPlan(asksSystem: false, opensSettings: true, help: .none)
        }
    }
}

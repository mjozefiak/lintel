import Foundation

/// What `ProviderChoiceModel` and `NotesSettingsModel` (Settings → Meetings) ask of the notes service: the board they
/// copy their state from and the calls they make. The port exists so the design gallery (spec
/// `2026-11-23-swiftui-design-gallery`) can draw those panes with a fake that has no database, Keychain, model or
/// process behind it; the product passes `NotesService`, which conforms without a change of behaviour. An internal
/// seam of the plugin, not a `LintelKit` contract.
@MainActor protocol ProviderNotesControl: AnyObject, Sendable {
    var board: NotesBoard { get }
    /// Whether any job is queued or running (a model file is in use then).
    var isBusy: Bool { get }
    func refreshAvailability() async
    func selectionChanged()
    func regenerate(_ meetingID: Int64)
    func writeOnThisMac(_ meetingID: Int64)
}

extension NotesService: ProviderNotesControl {}

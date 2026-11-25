#if DEBUG
import Foundation

/// DEBUG only (design gallery, spec `2026-11-23-swiftui-design-gallery`): the notes service of a scene. It keeps a real
/// `NotesBoard` (a class without I/O) whose state the scene sets (a job running, the last job's failure) and counts
/// the calls the panes make. No database, Keychain, model, process or network is behind it.
@MainActor final class GalleryNotesControl: ProviderNotesControl {
    let board = NotesBoard()
    /// The names of the calls the pane made, in order.
    private(set) var calls: [String] = []

    var isBusy: Bool { board.snapshot.jobRunning }

    init(jobRunning: Bool = false, failure: ProviderJobFailure? = nil) {
        board.update {
            if jobRunning { $0.phases[1] = .reducing }
            $0.providerFailure = failure
        }
    }

    func refreshAvailability() async { calls.append("refreshAvailability") }

    func selectionChanged() { calls.append("selectionChanged") }

    func regenerate(_ meetingID: Int64) { calls.append("regenerate") }

    func writeOnThisMac(_ meetingID: Int64) { calls.append("writeOnThisMac") }
}
#endif

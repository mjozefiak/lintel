import LintelKit
import LintelUI
import SwiftUI

/// The Notes section's block of the main window's sidebar (spec "Layout"): All notes, Meetings and Dictations with
/// their counts. The shell draws the sidebar and calls this through `WorkspaceSection.sidebar`; a click selects the
/// Notes section and the collection. The Folders header stays hidden until phase 6 and the Dictionary row (phase 7)
/// is the Dictation section's own.
struct NotesSidebarBlock: View {
    let model: NotesWorkspaceModel
    let context: WorkspaceSidebarContext

    /// The rows in the order the sidebar shows them.
    static let rows: [(collection: NoteCollection, symbol: String)] = [
        (.all, "note.text"), (.meetings, "person.2"), (.dictations, "mic"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Self.rows, id: \.collection) { row in
                SidebarRow(
                    title: NoteListView.title(of: row.collection), symbolName: row.symbol,
                    count: model.explorer.counts.count(of: row.collection),
                    isSelected: context.isSelected && model.explorer.collection == row.collection
                ) {
                    context.activate()
                    // The section shows its list again, whatever note was open.
                    Task { await model.showCollectionFromSidebar(row.collection) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Notes", comment: "Main window section title"))
    }
}

import LintelKit
import SwiftUI

/// Workspace mode's content: the sidebar, then the section. The sidebar is left out while the section fills the
/// window (`WorkspaceSection.hidesSidebar`, a note open in the full window, notes explorer spec phase 3b). The
/// closure is asked in `body`, so the window redraws when the section's state behind it changes.
struct WorkspaceContent: View {
    let section: WorkspaceSection
    let sidebar: MainSidebar

    var body: some View {
        HStack(spacing: 0) {
            if !section.hidesSidebar() { sidebar }
            section.makeView()
        }
    }
}

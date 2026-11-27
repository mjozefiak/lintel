import LintelKit
import SwiftUI

/// Workspace mode's content: the sidebar and the section side by side. It measures the window so the sidebar can
/// slim down when the window is narrow (`MainSidebar.width(windowWidth:)`).
struct MainWorkspaceView: View {
    let sections: [WorkspaceSection]
    let section: WorkspaceSection
    let select: @MainActor (String) -> Void
    let openSettings: @MainActor () -> Void
    @State private var windowWidth: CGFloat?

    var body: some View {
        HStack(spacing: 0) {
            MainSidebar(
                sections: sections, selectedSection: section.id, select: select, openSettings: openSettings,
                windowWidth: windowWidth)
            section.makeView()
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            windowWidth = $0
        }
    }
}

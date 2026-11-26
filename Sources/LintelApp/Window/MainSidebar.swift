import LintelKit
import LintelUI
import SwiftUI

/// What the main window's sidebar lists in Workspace mode (spec `2026-11-24-notes-explorer-main-window`, "Layout"):
/// one entry per active section in `order`, either the section's own block (`WorkspaceSection.sidebar`) or one default
/// row with its title and symbol. Pure, so the order and the "add-ons that are off are absent" rule are tested without
/// a window: a section of a plugin that is off is not in `sections` at all (`AppCoordinator.activeWorkspaceSections`).
enum MainSidebarModel {
    struct Entry: Equatable {
        var sectionID: String
        /// `true` when the section draws its own block.
        var hasBlock: Bool
    }

    static func entries(sections: [WorkspaceSection]) -> [Entry] {
        sections.sorted { $0.order < $1.order }.map { Entry(sectionID: $0.id, hasBlock: $0.sidebar != nil) }
    }
}

/// The sidebar of Workspace mode: the sections' blocks stacked, Settings at the bottom. Warm sidebar background and
/// hairline from the brand tokens; Verdigris only marks the selected row.
struct MainSidebar: View {
    let sections: [WorkspaceSection]
    let selectedSection: String
    let select: @MainActor (String) -> Void
    let openSettings: @MainActor () -> Void
    @Environment(\.lintelTextSize) private var textSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(sections.sorted { $0.order < $1.order }, id: \.id) { section in
                        block(of: section)
                    }
                }
                .padding(.horizontal, SidebarRow.rowInset)
                .padding(.top, 12 * textSize.scale)
            }
            LintelDivider()
            SidebarRow(
                title: String(localized: "Settings", comment: "Main window sidebar: opens Settings"),
                symbolName: "gearshape", isSelected: false
            ) { openSettings() }
            .padding(.horizontal, SidebarRow.rowInset)
            .padding(.vertical, 8 * textSize.scale)
        }
        .frame(width: 220 * textSize.scale)
        .frame(maxHeight: .infinity)
        .background(LintelBrand.sidebarBackground)
        .overlay(alignment: .trailing) { LintelDivider(axis: .vertical) }
    }

    @ViewBuilder private func block(of section: WorkspaceSection) -> some View {
        let isSelected = section.id == selectedSection
        if let sidebar = section.sidebar {
            sidebar.makeView(
                WorkspaceSidebarContext(isSelected: isSelected, activate: { select(section.id) }))
        } else {
            SidebarRow(
                title: String(localized: section.title), symbolName: section.symbolName, isSelected: isSelected
            ) { select(section.id) }
        }
    }
}

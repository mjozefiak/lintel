import LintelKit
import SwiftUI
import Testing

@testable import LintelApp

@MainActor
@Suite("Main window: the sidebar of Workspace mode")
struct MainSidebarTests {
    private func section(_ id: String, order: Int, block: Bool) -> WorkspaceSection {
        WorkspaceSection(
            id: id, title: LocalizedStringResource(stringLiteral: id), symbolName: "note.text", order: order,
            sidebar: block ? WorkspaceSidebar(makeView: { _ in AnyView(EmptyView()) }) : nil,
            makeView: { AnyView(EmptyView()) })
    }

    @Test("sections are listed in order, a block where the section has one and a default row where it has none")
    func order() {
        let entries = MainSidebarModel.entries(sections: [
            section("dictionary", order: 40, block: false), section("notes", order: 5, block: true),
        ])
        #expect(entries == [
            MainSidebarModel.Entry(sectionID: "notes", hasBlock: true),
            MainSidebarModel.Entry(sectionID: "dictionary", hasBlock: false),
        ])
    }

    @Test("a plugin that is off has no section, so its row is absent")
    func offPluginsAreAbsent() {
        let entries = MainSidebarModel.entries(sections: [section("notes", order: 5, block: true)])
        #expect(entries.map(\.sectionID) == ["notes"])
        #expect(MainSidebarModel.entries(sections: []).isEmpty)
    }
}

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
        #expect(
            entries == [
                MainSidebarModel.Entry(sectionID: "notes", hasBlock: true),
                MainSidebarModel.Entry(sectionID: "dictionary", hasBlock: false),
            ])
    }

    @Test("a window tiled narrower than the layout gets a slim sidebar, so the section keeps its room")
    func narrowWindowSlimsTheSidebar() {
        #expect(MainSidebar.width(windowWidth: nil) == 220)
        #expect(MainSidebar.width(windowWidth: 0) == 220)
        #expect(MainSidebar.width(windowWidth: 1180) == 220)
        #expect(MainSidebar.width(windowWidth: 640) == 220)
        #expect(MainSidebar.width(windowWidth: 639) == 56)
        // About 310 pt (AeroSpace): the slim sidebar leaves the section more than half the window.
        #expect(MainSidebar.width(windowWidth: 310) == 56)
        #expect(310 - MainSidebar.width(windowWidth: 310) > 310 / 2)
    }

    @Test("an add-on that is off has no row; switched on, its row appears in its order")
    func offPluginsAreAbsent() async throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        let host = env.makeHost([NoFilesPlugin.self, SidebarCorePlugin.self, SidebarAddOnPlugin.self])
        await host.start()
        var sections = AppCoordinator.activeWorkspaceSections(host)
        #expect(MainSidebarModel.entries(sections: sections).map(\.sectionID) == ["core"])
        await host.setEnabled(true, for: "sidebar-add-on")
        sections = AppCoordinator.activeWorkspaceSections(host)
        #expect(MainSidebarModel.entries(sections: sections).map(\.sectionID) == ["add-on", "core"])
    }
}

/// A plugin that is on by default, with a section that draws its own sidebar block.
@MainActor final class SidebarCorePlugin: LintelPlugin {
    static let manifest = PluginManifest(id: "sidebar-core", displayName: "Core", symbolName: "1.circle", order: 1)
    init(context: PluginContext) {}
    var workspaceSections: [WorkspaceSection] {
        [
            WorkspaceSection(
                id: "core", title: "Core", symbolName: "note.text", order: 20,
                sidebar: WorkspaceSidebar(makeView: { _ in AnyView(EmptyView()) }), makeView: { AnyView(EmptyView()) })
        ]
    }
}

/// An add-on: off by default, with a section that sorts before the core one.
@MainActor final class SidebarAddOnPlugin: LintelPlugin {
    static let manifest = PluginManifest(
        id: "sidebar-add-on", displayName: "Add-on", symbolName: "2.circle", order: 2, defaultEnabled: false)
    init(context: PluginContext) {}
    var workspaceSections: [WorkspaceSection] {
        [
            WorkspaceSection(
                id: "add-on", title: "Add-on", symbolName: "puzzlepiece", order: 10, makeView: { AnyView(EmptyView()) })
        ]
    }
}

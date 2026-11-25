#if DEBUG
import AppKit
import LintelUI
import SwiftUI

/// DEBUG only (`--qa-gallery`): the design gallery window, a developer tool (spec `2026-11-23-swiftui-design-gallery`).
/// A sidebar of the scenes (grouped by plugin), and for each state its caption and either the live view (the real
/// `NSHostingView`, glass and all) or the pictures of the chosen variants. Not a product screen: English only,
/// the scenes inside it are translated.
@MainActor final class GalleryWindowController {
    private(set) var window: NSWindow?

    func show(snapshotAfter: Duration? = nil) {
        let host = NSHostingView(rootView: GalleryBrowserView(groups: GalleryCatalog.groups))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_180, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Lintel Design Gallery"
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.center()
        // Like the other QA windows: in front, but without taking the focus from the tester.
        window.orderFrontRegardless()
        self.window = window
    }

    /// The window's content as a PNG (`--qa-snapshot`).
    func writeSnapshot(to path: String) {
        guard let view = window?.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(filePath: path))
    }
}

private struct GalleryBrowserView: View {
    let groups: [GalleryCatalog.Group]

    enum Mode: String, CaseIterable, Identifiable {
        case live = "Live"
        case pictures = "Pictures"
        var id: String { rawValue }
    }

    @State private var selection: String?
    @State private var mode = Mode.live
    @State private var appearance = GalleryVariant.Appearance.light
    @State private var textSize = TextSize.medium
    @State private var fullMatrix = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.scenes) { scene in
                            HStack {
                                Text(verbatim: scene.title)
                                Spacer()
                                Text(verbatim: "\(scene.states.count)").foregroundStyle(.secondary)
                            }
                            .tag(scene.id)
                        }
                    } header: {
                        Text(verbatim: group.title)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        } detail: {
            if let scene = groups.flatMap(\.scenes).first(where: { $0.id == selection }) {
                detail(scene)
            } else {
                Text(verbatim: groups.isEmpty ? "No plugin has gallery scenes." : "Choose a scene.")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { selection = selection ?? groups.first?.scenes.first?.id }
    }

    private func detail(_ scene: GalleryScene) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Picker(selection: $mode) {
                    ForEach(Mode.allCases) { Text(verbatim: $0.rawValue).tag($0) }
                } label: {
                    Text(verbatim: "View")
                }
                .pickerStyle(.segmented).frame(width: 180)
                Picker(selection: $appearance) {
                    ForEach(GalleryVariant.Appearance.allCases, id: \.self) { Text(verbatim: $0.rawValue).tag($0) }
                } label: {
                    Text(verbatim: "Appearance")
                }
                .frame(width: 170)
                Picker(selection: $textSize) {
                    ForEach([TextSize.small, .medium, .large, .extraLarge]) {
                        Text(verbatim: $0.rawValue.uppercased()).tag($0)
                    }
                } label: {
                    Text(verbatim: "Text size")
                }
                .frame(width: 150)
                if mode == .pictures { Toggle(isOn: $fullMatrix) { Text(verbatim: "Full matrix") } }
                Spacer()
                Text(
                    verbatim:
                        "Language: \(GalleryRenderer.processLanguage) (start with -AppleLanguages \"(pl)\" for Polish)"
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(scene.states) { state in
                        GalleryStateCard(
                            state: state, mode: mode, appearance: appearance, textSize: textSize, fullMatrix: fullMatrix
                        )
                    }
                }
                .padding(20)
            }
        }
    }
}

private struct GalleryStateCard: View {
    let state: GalleryState
    let mode: GalleryBrowserView.Mode
    let appearance: GalleryVariant.Appearance
    let textSize: TextSize
    let fullMatrix: Bool

    @State private var pictures: [String: NSImage] = [:]
    @State private var errors: [String: String] = [:]

    private var language: String { GalleryRenderer.processLanguage }

    private var variants: [GalleryVariant] {
        let all = fullMatrix ? GalleryVariant.fullMatrix : state.variants
        return all.filter { $0.language == language }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: state.id).font(.system(.headline, design: .monospaced))
            Text(verbatim: state.summary).foregroundStyle(.secondary)
            if let caveat = state.presentation.caveat {
                Text(verbatim: caveat).font(.caption).foregroundStyle(.orange)
            }
            switch mode {
            case .live:
                GalleryRenderer.liveView(
                    state, GalleryVariant(appearance: appearance, textSize: textSize, language: language)
                )
                .border(Color.secondary.opacity(0.3))
            case .pictures:
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(variants, id: \.name) { variant in
                            VStack(alignment: .leading) {
                                Text(verbatim: variant.name).font(.caption).foregroundStyle(.secondary)
                                if let image = pictures[variant.name] {
                                    Image(nsImage: image).border(Color.secondary.opacity(0.3))
                                } else if let error = errors[variant.name] {
                                    Text(verbatim: error).foregroundStyle(.red)
                                } else {
                                    ProgressView()
                                }
                            }
                        }
                    }
                }
                .task(id: variants.map(\.name)) { await render() }
            }
        }
    }

    private func render() async {
        for variant in variants where pictures[variant.name] == nil {
            do {
                let bitmap = try await GalleryRenderer.render(state, variant)
                let image = NSImage(size: bitmap.size)
                image.addRepresentation(bitmap)
                pictures[variant.name] = image
            } catch {
                errors[variant.name] = "\(error)"
            }
        }
    }
}
#endif

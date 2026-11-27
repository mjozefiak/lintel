#if DEBUG
import AppKit
import LintelUI
import SwiftUI

/// DEBUG only (`--qa-pill-spike <log file>`, spec `2026-11-25-minimal-hud` Phase 1, risks R2 and R3): one HUD pill in a
/// panel built like the HUD panels (borderless, non-activating, status-bar level, clear, never key) with the fixed
/// transparent 580 × 56 pt frame of the pill family, hosted by `PillHoverHost`. Nothing of the app starts: no data
/// root, no plugin, no microphone, no sound. Every hover change, every press and the frames go to the log file with a
/// time in milliseconds, so a driver that posts real mouse events can measure the 300 / 500 ms delays and see whether a
/// click on the transparent part reached the window below. Not a contract.
@MainActor
final class QAPillSpike {
    private let log: URL
    private let started = ContinuousClock.now
    private var panel: NSPanel?
    private let hover = PillHoverModel()
    private var lines: [String] = []

    init(log: URL) {
        self.log = log
    }

    /// The pill the spike shows: the meeting suggestion (a primary button, a hover-only link and a ✕), the widest
    /// hovered pill of the spec, so the transparent area and the hover expansion are both tested.
    static var content: PillContent {
        PillContent(
            glyph: .person, text: "Meeting in Google Chrome",
            action: PillAction(id: "record", title: "Record", style: .primary),
            hoverActions: [
                PillAction(
                    id: "mute", title: "Don't ask again", accessibilityName: "Don't ask again for Google Chrome",
                    style: .link)
            ],
            close: PillClose(id: "notNow", accessibilityName: "Not now"),
            accessibilityLabel: "Meeting in Google Chrome")
    }

    func show(appearance: NSAppearance.Name?, textSize: TextSize) {
        hover.onEvent = { [weak self] event in self?.write("hover \(event)") }
        let root = PillHoverRoot(Self.content, hover: hover) { [weak self] id in self?.write("action \(id)") }
            .lintelTextSize(textSize)
        let host = PillHoverHost(rootView: root, hover: hover)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: PillMetrics.panelSize),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        if let appearance { panel.appearance = NSAppearance(named: appearance) }
        panel.contentView = host
        // Bottom centre of the main screen, where the dictation pill sits.
        if let frame = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(
                NSPoint(x: (frame.midX - PillMetrics.panelSize.width / 2).rounded(), y: frame.minY + 48))
        }
        panel.orderFrontRegardless()
        self.panel = panel
        write("panel frame \(Self.text(panel.frame)) ignoresMouseEvents \(panel.ignoresMouseEvents)")
        write("screen frame \(Self.text(NSScreen.main?.frame ?? .zero))")
        write("app active \(NSApp.isActive)")
        Task { @MainActor [weak self] in
            // The pill's frame is known after the first layout.
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, let panel = self.panel else { return }
            let pill = self.hover.pillFrame
            // SwiftUI's frame is top-left in the panel; the screen's origin is bottom-left.
            let screen = NSRect(
                x: panel.frame.minX + pill.minX, y: panel.frame.maxY - pill.maxY, width: pill.width,
                height: pill.height)
            self.write("pill frame \(Self.text(screen))")
            self.write("ready")
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.write("app became active") }
        }
    }

    private func write(_ line: String) {
        let milliseconds = started.duration(to: .now).components
        let ms = milliseconds.seconds * 1000 + milliseconds.attoseconds / 1_000_000_000_000_000
        lines.append("\(ms) \(line)")
        try? Data((lines.joined(separator: "\n") + "\n").utf8).write(to: log)
    }

    private static func text(_ rect: NSRect) -> String {
        "\(Int(rect.minX)) \(Int(rect.minY)) \(Int(rect.width)) \(Int(rect.height))"
    }
}
#endif

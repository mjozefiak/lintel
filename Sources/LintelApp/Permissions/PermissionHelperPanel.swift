import AppKit
import LintelUI
import SwiftUI

/// The floating window of the permission helper (spec 2026-11-24, "Floating helper panel"): a non-activating panel
/// that stays above System Settings on every Space and never takes the focus from it. It holds the SwiftUI
/// `PermissionHelperView` and does only what the controller tells it: show, update, move, close.
///
/// It cannot become key: a click on it must not make Lintel the active app, because the user is working in System
/// Settings. A drag from the tile and the buttons work without that, and VoiceOver reaches the buttons.
@MainActor final class PermissionHelperPanel: NSPanel, PermissionHelperPresenting {
    static let fadeDuration: TimeInterval = 0.15
    static let slideDuration: TimeInterval = 0.25

    var onShowInFinder: (() -> Void)?
    var onDone: (() -> Void)?

    private let bundleURL: URL
    private let icon: () -> AnyView
    private let host = NSHostingView(rootView: AnyView(EmptyView()))
    private var sizes: [PermissionHelperContent: CGSize] = [:]

    init(bundleURL: URL, icon: @escaping () -> AnyView) {
        self.bundleURL = bundleURL
        self.icon = icon
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: PermissionHelperLayout.width, height: 120),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        // The default hides a panel while another app is active, which System Settings is the whole time.
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        isMovableByWindowBackground = false
        contentView = host
        host.sizingOptions = []
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The real panel's icon is the app's own.
    static func live(bundleURL: URL = Bundle.main.bundleURL) -> PermissionHelperPanel {
        PermissionHelperPanel(bundleURL: bundleURL) {
            AnyView(Image(nsImage: NSApp.applicationIconImage).resizable().scaledToFit())
        }
    }

    private func view(for content: PermissionHelperContent) -> AnyView {
        AnyView(
            PermissionHelperView(
                content: content, bundleURL: bundleURL,
                showInFinder: { [weak self] in self?.onShowInFinder?() },
                done: { [weak self] in self?.onDone?() },
                icon: { icon() }
            )
            .lintelTextSize(AppTextSize.current()))
    }

    func size(for content: PermissionHelperContent) -> CGSize {
        if let known = sizes[content] { return known }
        let measuring = NSHostingView(rootView: view(for: content))
        let size = measuring.fittingSize
        sizes[content] = size
        return size
    }

    func show(content: PermissionHelperContent, frame: CGRect, motion: PermissionHelperMotion) {
        sizes = [:]
        host.rootView = view(for: content)
        switch motion {
        case .fade:
            setFrame(frame, display: false)
            alphaValue = 0
            orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeDuration
                animator().alphaValue = 1
            }
        case .slide(let start):
            setFrame(start, display: false)
            alphaValue = 0
            orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.slideDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().setFrame(frame, display: true)
                animator().alphaValue = 1
            }
        }
    }

    func update(content: PermissionHelperContent) {
        host.rootView = view(for: content)
        let new = size(for: content)
        // Keep the panel's top left corner where it is: the "Allowed" state is smaller than the content it replaces.
        var frame = self.frame
        frame.origin.y += frame.height - new.height
        frame.size = new
        setFrame(frame, display: true)
    }

    func move(to frame: CGRect) {
        // No animation: following the Settings window has to keep up with a drag.
        setFrame(frame, display: true)
    }

    override func close() {
        orderOut(nil)
        onShowInFinder = nil
        onDone = nil
        super.close()
    }
}

/// Opens the helper and makes sure there is only one: showing a new one closes the one before it, with no
/// reason, because it is replaced and not finished. Nothing calls it yet; wiring it to the Allow buttons is a
/// separate step that waits for the owner's approval of the gallery sheet.
@MainActor final class PermissionHelperPresenter {
    typealias Factory = @MainActor (PermissionHelperContent) -> (any PermissionHelperPresenting)
    typealias EnvironmentFactory =
        @MainActor (_ isGranted: @escaping @MainActor () -> Bool) -> PermissionHelperEnvironment

    private let makePanel: Factory
    private let makeEnvironment: EnvironmentFactory
    private(set) var current: PermissionHelperController?

    init(
        makePanel: @escaping Factory = { _ in PermissionHelperPanel.live() },
        makeEnvironment: @escaping EnvironmentFactory = {
            PermissionHelperEnvironment.live(isGranted: $0, bundleURL: Bundle.main.bundleURL)
        }
    ) {
        self.makePanel = makePanel
        self.makeEnvironment = makeEnvironment
    }

    /// Shows the helper for `content`. `isGranted` is read on every poll (a permission that is granted closes it).
    @discardableResult
    func show(
        _ content: PermissionHelperContent, isGranted: @escaping @MainActor () -> Bool,
        onClose: @escaping (PermissionHelperSession.CloseReason) -> Void = { _ in }
    ) -> PermissionHelperController {
        current?.stop()
        let controller = PermissionHelperController(
            content: content, environment: makeEnvironment(isGranted), panel: makePanel(content), onClose: onClose)
        current = controller
        controller.start()
        return controller
    }

    /// Closes the open helper, if any.
    func dismiss() {
        current?.stop()
        current = nil
    }
}

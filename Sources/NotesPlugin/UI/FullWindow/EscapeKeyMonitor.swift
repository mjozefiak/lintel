import AppKit
import SwiftUI

/// Sees every Esc key press of its window before the responder chain does and offers it to `handler` with
/// whether the first responder is text (a text view, which includes the field editor of a text field). `handler`
/// returns `true` when it used the key, which is then consumed; otherwise the key goes on as usual, so a text
/// view, the palette or a popover still get their Esc. Sheets and popovers are other windows and are not seen.
struct EscapeKeyMonitor: NSViewRepresentable {
    let handler: @MainActor (_ textHasFocus: Bool) -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.view = view
        context.coordinator.handler = handler
        context.coordinator.install()
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.handler = handler
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        weak var view: NSView?
        var handler: (@MainActor (Bool) -> Bool)?
        private var monitor: Any?

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                // AppKit calls a local monitor on the main thread; `NSEvent` is not `Sendable`, so it is carried over.
                nonisolated(unsafe) let event = event
                let consumed = MainActor.assumeIsolated { self?.consumes(event) ?? false }
                return consumed ? nil : event
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        /// Plain Esc (no ⌘, ⌃ or ⌥) in this view's window.
        private func consumes(_ event: NSEvent) -> Bool {
            guard event.keyCode == 53, let window = view?.window, event.window === window else { return false }
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
            let textHasFocus = window.firstResponder is NSText
            // A held key repeats: the first press decided, so a repeat outside text is swallowed, not asked again.
            if event.isARepeat { return !textHasFocus }
            return handler?(textHasFocus) ?? false
        }
    }
}

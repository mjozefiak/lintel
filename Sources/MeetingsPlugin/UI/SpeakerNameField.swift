import AppKit
import LintelUI
import SwiftUI

/// The field a speaker's name turns into when it is clicked. An `NSTextField`, because SwiftUI's `TextField` with
/// `@FocusState` set in `onAppear` did not take the keyboard: the field was not in the window yet, and AppKit gave the
/// focus to the first key view, the meeting's title (QA of #352, B1). This field makes itself the first responder once
/// it is in a window, Return saves, Escape cancels, and losing the focus saves like Return.
struct SpeakerNameField: NSViewRepresentable {
    let text: String
    let font: NSFont
    var onChange: (String) -> Void = { _ in }
    var onReturn: () -> Void = {}
    var onEscape: () -> Void = {}
    var onFocusLost: () -> Void = {}

    func makeNSView(context: Context) -> SpeakerNameTextField {
        let field = SpeakerNameTextField()
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.cell?.usesSingleLineMode = true
        field.stringValue = text
        field.delegate = context.coordinator
        field.setAccessibilityLabel(
            String(localized: "Speaker name", comment: "Meeting window: label of a speaker name field"))
        field.setAccessibilityHelp(
            String(
                localized: "Type the name, then press Return. Escape cancels.",
                comment: "Meeting window: hint of the speaker name field"))
        field.onFocusLost = { [weak coordinator = context.coordinator] in coordinator?.parent.onFocusLost() }
        return field
    }

    func updateNSView(_ field: SpeakerNameTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.font = font
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SpeakerNameTextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 160, height: nsView.intrinsicContentSize.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SpeakerNameField

        init(_ parent: SpeakerNameField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.onChange(field.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onReturn()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape()
                return true
            default:
                return false
            }
        }
    }
}

/// Takes the keyboard once it is in a window, and says when it loses it.
final class SpeakerNameTextField: NSTextField {
    var onFocusLost: () -> Void = {}
    private var tookFocus = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !tookFocus else { return }
        tookFocus = true
        // The next turn of the run loop: SwiftUI is still placing the view in this one.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        onFocusLost()
    }
}

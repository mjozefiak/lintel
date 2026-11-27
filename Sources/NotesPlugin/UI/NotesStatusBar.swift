import LintelKit
import LintelUI
import SwiftUI

/// The status bar (prototype `.sbar`): what is true of the whole section, in words.
struct NotesStatusBar: View {
    let model: NotesWorkspaceModel
    @Environment(\.lintelTextSize) private var textSize

    var body: some View {
        VStack(spacing: 0) {
            LintelDivider()
            HStack(spacing: 14) {
                if let line = model.statusLine { StatusLineView(line: line) }
                if model.showsEncryptionNote {
                    Label {
                        Text("Encrypted on this Mac", comment: "Notes status bar: where the notes are stored")
                    } icon: {
                        Image(systemName: "lock")
                    }
                }
                Spacer(minLength: 0)
                Text(verbatim: model.statusRight)
            }
            .font(textSize.font(.footnote))
            .foregroundStyle(LintelBrand.secondaryText)
            .padding(.horizontal, 12 * textSize.scale)
            .frame(height: 26 * textSize.scale)
            .background(LintelBrand.sidebarBackground)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The dot or the spinner, the words and, while the length is known, the progress bar (prototype `.pb`).
struct StatusLineView: View {
    let line: NotesWorkspaceModel.StatusLine
    @Environment(\.lintelTextSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            switch line.kind {
            case .busy:
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(LintelBrand.accentText)
                    .accessibilityHidden(true)
            default:
                Circle().fill(color).frame(width: 7 * textSize.scale, height: 7 * textSize.scale)
                    .accessibilityHidden(true)
            }
            Text(verbatim: line.text)
            if case .busy(let progress?) = line.kind {
                ZStack(alignment: .leading) {
                    Capsule().fill(LintelBrand.hairline)
                    GeometryReader { proxy in
                        Capsule().fill(LintelBrand.accent).frame(width: proxy.size.width * progress)
                    }
                }
                .frame(width: 8 * 12.5 * textSize.scale, height: 4)
                .padding(.leading, 2)
                .accessibilityHidden(true)
            }
        }
    }

    private var color: Color {
        switch line.kind {
        case .ok: LintelBrand.statusOk
        case .attention: LintelBrand.statusAttention
        case .error: LintelBrand.statusError
        default: LintelBrand.hairline
        }
    }
}

/// What the "New note" button shows and whether it works. Built from the same `canCreateNote` as the ⌘N menu item, so
/// they are on and off together (read-only mode, no store, a note being created).
struct NewNoteAffordance: Equatable {
    /// The key hint shown on the explorer's button (the menu item's shortcut).
    static let shortcutHint = "⌘N"
    let isEnabled: Bool
}

extension NotesWorkspaceModel {
    var newNoteAffordance: NewNoteAffordance { NewNoteAffordance(isEnabled: canCreateNote) }
}

/// "New note" (⌘N): the list header's plus button. It runs `NotesWorkspaceModel.newNote`, like the menu item. It is
/// not filled: Record Meeting is the window's only filled button (C3).
struct NewNoteButton: View {
    enum Style { case icon }
    let model: NotesWorkspaceModel
    let style: Style
    @Environment(\.lintelTextSize) private var textSize

    var body: some View {
        let isEnabled = model.newNoteAffordance.isEnabled
        Button {
            Task { await model.newNote() }
        } label: {
            switch style {
            case .icon:
                Image(systemName: "plus")
                    .font(textSize.font(.callout, weight: .semibold))
                    .foregroundStyle(LintelBrand.ink)
                    .frame(width: 26 * textSize.scale, height: 26 * textSize.scale)
                    .background(LintelBrand.fill, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(RoundedRectangle(cornerRadius: 7))
                    .opacity(isEnabled ? 1 : 0.45)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(Text("New note", comment: "Accessibility label of the new-note button"))
        .accessibilityHint(
            Text("Creates a note and opens it for writing", comment: "Accessibility hint of the new-note button")
        )
        .help(Text("New note (⌘N)", comment: "Tooltip of the new-note button"))
    }
}

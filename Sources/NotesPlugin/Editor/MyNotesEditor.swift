import LintelKit
import LintelUI
import SwiftUI

/// My notes (spec step 3.5, states table "Preview: meeting"): a plain pad over the note editor, in the preview's
/// My notes tab and in the full window. The line above it says that only the user writes here; an empty pad says
/// what it is for. A write that failed shows the strip "Your notes weren't saved. Lintel keeps trying." with Try
/// Now, and the text stays in the pad. No comments and no agent: nothing of Lintel's writes My notes.
struct MyNotesEditor: View {
    let model: NotesWorkspaceModel
    let document: NoteDocumentModel
    let pad: MyNotesPad
    @State private var buffer: String
    @Environment(\.lintelTextSize) private var textSize

    init(model: NotesWorkspaceModel, document: NoteDocumentModel, pad: MyNotesPad) {
        self.model = model
        self.document = document
        self.pad = pad
        _buffer = State(initialValue: pad.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if pad.saveFailed {
                NoteStripView(strip: Self.failedStrip, model: model)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8 * textSize.scale) {
                Text(verbatim: Self.line(pad.readOnlyReason))
                    .font(textSize.font(.callout))
                    .foregroundStyle(LintelBrand.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if pad.isSaving && !pad.saveFailed {
                    Text("Saving…", comment: "My notes: what was typed is being written")
                        .font(textSize.font(.footnote))
                        .foregroundStyle(LintelBrand.secondaryText)
                }
            }
            .padding(.leading, 5.4 * 12.5 * textSize.scale)
            .padding(.trailing, 24 * textSize.scale)
            .padding(.vertical, 8 * textSize.scale)
            if pad.isEditable || !buffer.isEmpty {
                editor
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The pad's text changes only through this editor, or through QA; keep the two the same.
        .onChange(of: pad.text) { _, text in
            if buffer != text { buffer = text }
        }
    }

    private var editor: some View {
        var surface = NoteEditorSurface(
            text: $buffer, pasteboard: model.environment.pasteboard, isReadOnly: !pad.isEditable,
            wrapsLines: true, mode: .formatted,
            onFocusChange: { focused in
                // Losing focus is a save point.
                if !focused { Task { await pad.flush() } }
            },
            onEdit: { pad.edit($0) },
            header: { EmptyView() })
        surface.showsFormatBar = false
        return
            surface
            .overlay(alignment: .topLeading) {
                if buffer.isEmpty {
                    Text(
                        "Type your own notes. Lintel keeps them exactly as you write them.",
                        comment: "My notes: the empty pad"
                    )
                    .font(textSize.font(.body))
                    .foregroundStyle(LintelBrand.secondaryText)
                    .padding(.leading, 5.4 * 12.5 * textSize.scale)
                    // The editor's right inset (`NoteEditorRepresentable`): the sentence wraps before the scroll bar.
                    .padding(.trailing, 40 * textSize.scale)
                    .padding(.top, 6 * textSize.scale)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .accessibilityLabel(Text("My notes", comment: "Preview: the tab with your own notes"))
            .accessibilityHint(
                buffer.isEmpty
                    ? Text(
                        "Type your own notes. Lintel keeps them exactly as you write them.",
                        comment: "My notes: the empty pad") : Text(verbatim: ""))
    }

    /// The line above the pad: who writes here, or why nobody can now.
    static func line(_ reason: MyNotesPad.ReadOnlyReason?) -> String {
        switch reason {
        case nil:
            String(
                localized: "Only you write here. Lintel never changes these notes.",
                comment: "My notes: the line above the pad")
        case .readOnly:
            String(
                localized: "Notes are read-only on this Mac, so My notes can’t be changed now.",
                comment: "My notes: plugins.notes.readOnly is on")
        case .unavailable:
            String(
                localized: "Lintel can’t open your notes right now, so My notes can’t be changed. Nothing was deleted.",
                comment: "My notes: the notes library cannot be opened")
        case .recordingRemoved:
            String(
                localized: "The recording was removed. Your notes are kept as you wrote them.",
                comment: "My notes: the kept copy of a removed recording")
        }
    }

    static var failedStrip: NotesWorkspaceModel.Strip {
        NotesWorkspaceModel.Strip(
            id: "mine.save", tone: .error,
            text: String(
                localized: "Your notes weren’t saved. Lintel keeps trying.",
                comment: "My notes: a write failed; the text stays in the pad"),
            actions: [
                NotesWorkspaceModel.Strip.Action(
                    id: "mine.retry",
                    title: String(localized: "Try Now", comment: "My notes: writes the unsaved text at once"))
            ])
    }
}

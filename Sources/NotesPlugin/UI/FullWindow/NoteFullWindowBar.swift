import LintelKit
import LintelUI
import SwiftUI

/// The bar of the full window (notes explorer spec, phase 3b): "‹ All notes" back to the list (⌘[, Esc), then the
/// actions of the open note that the path bar had: the editor mode, the pen, Make note, Copy Markdown (⌘⇧C), the
/// inspector button and Save .md…. The strips of the note run under it.
struct NoteFullWindowBar: View {
    let model: NotesWorkspaceModel
    @Environment(\.lintelTextSize) private var textSize

    /// "‹ All notes": the button's title, also the menu item's and VoiceOver's.
    static let backTitle = LocalizedStringResource(
        "All notes", comment: "Full window: goes back to the list of notes (the button shows a ‹ before it)")
    static let backShortcut = KeyShortcut(key: "[", modifiers: [.command])

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                backButton
                if let count = model.currentDocument?.totalPendingProposals, count > 0 {
                    // The tab's proposal dot of the old tab bar (step 6.3), now beside the way back.
                    Text(verbatim: "●")
                        .font(textSize.font(.caption1))
                        .foregroundStyle(LintelBrand.statusAttention)
                        .accessibilityLabel(
                            Text("Has a proposal", comment: "Accessibility: a version of the note waits for Apply"))
                }
                Spacer(minLength: 0)
                if let feedback = model.feedback, !feedback.isStrip {
                    Text(verbatim: Self.text(feedback))
                        .font(textSize.font(.footnote))
                        .foregroundStyle(LintelBrand.accentText)
                        .accessibilityHidden(true)
                        .notesFade(.strip)
                }
                if model.currentDocument?.markdown != nil { actions }
            }
            .padding(.leading, 8 * textSize.scale)
            .padding(.trailing, 12 * textSize.scale)
            .frame(minHeight: 32.5 * textSize.scale)
            LintelDivider()
            ForEach(model.strips) { strip in
                NoteStripView(strip: strip, model: model).notesFade(.strip)
            }
        }
        .notesAnimation(.strip, value: model.strips.map(\.id))
        .notesAnimation(.strip, value: model.feedbackSerial)
        .accessibilityElement(children: .contain)
        .task(id: model.feedbackSerial) {
            guard let feedback = model.feedback else { return }
            AccessibilityNotification.Announcement(Self.text(feedback)).post()
            // The save-error strip stays until it is dismissed or the save is tried again.
            guard !feedback.isStrip else { return }
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { model.dismissFeedback() }
        }
    }

    /// A plain, neutral button (links stay neutral, C19): the chevron and "All notes".
    private var backButton: some View {
        Button {
            model.closeFullWindow()
        } label: {
            HStack(spacing: 4 * textSize.scale) {
                Image(systemName: "chevron.left")
                    .font(textSize.font(.callout, weight: .semibold))
                    .accessibilityHidden(true)
                Text(Self.backTitle)
                    .font(textSize.font(.callout))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(LintelBrand.ink)
            .padding(.horizontal, 8 * textSize.scale)
            .frame(minHeight: 26.25 * textSize.scale)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("[", modifiers: [.command])
        .help(Text("Back to all notes (⌘[ or Esc)", comment: "Full window: tooltip of the way back to the list"))
        .accessibilityLabel(Text(Self.backTitle))
        .accessibilityHint(Text("Goes back to the list of notes.", comment: "Full window: hint of the way back"))
    }

    private var actions: some View {
        HStack(spacing: 2) {
            if model.canSwitchEditorMode { NoteEditorModeSwitch(model: model) }
            if let document = model.currentDocument, model.canEdit(document) || document.isEditing {
                // Prototype `.ib.on`: the pen is lit while the note is in the editor.
                iconButton(
                    "pencil",
                    label: document.isEditing
                        ? Text("Done editing", comment: "Full window: leaves the editor")
                        : Text("Edit", comment: "Full window: opens the note in the editor"),
                    tint: document.isEditing ? LintelBrand.accentText : LintelBrand.secondaryText
                ) {
                    model.toggleEditing()
                }
                .background(
                    document.isEditing ? LintelBrand.windowSelectionTint : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .accessibilityAddTraits(document.isEditing ? .isSelected : [])
                .notesAnimation(.pen, value: document.isEditing)
            }
            if let document = model.currentDocument, NoteCollection.isDictation(document.id) {
                iconButton(
                    "note.text.badge.plus",
                    label: Text("Make note", comment: "Full window and explorer: copies a dictation into a new note")
                ) {
                    Task { await model.makeNote(from: document.id) }
                }
                .disabled(!model.canMakeNote(document.id) || document.phase != .loaded)
            }
            iconButton("doc.on.doc", label: Text("Copy Markdown", comment: "Full window: copies the note as Markdown"))
            {
                model.copyMarkdown()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            if !model.inspectorVisible {
                iconButton(
                    "sidebar.right", label: Text("Show the inspector", comment: "Full window: shows the inspector")
                ) {
                    model.setInspectorVisible(true)
                }
            }
            iconButton(
                "square.and.arrow.down",
                label: Text("Save .md…", comment: "Full window: saves the note as a Markdown file")
            ) {
                Task { await model.saveMarkdown() }
            }
        }
    }

    private func iconButton(
        _ symbol: String, label: Text, tint: Color = LintelBrand.secondaryText, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(textSize.font(.callout))
                .foregroundStyle(tint)
                .frame(width: 26.25 * textSize.scale, height: 26.25 * textSize.scale)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    static func text(_ feedback: NotesWorkspaceModel.Feedback) -> String {
        switch feedback {
        case .copied: String(localized: "Copied", comment: "Full window: the Markdown was copied")
        case .saved: String(localized: "Saved", comment: "Full window: the Markdown file was saved")
        case .saveFailed:
            String(
                localized: "The .md file couldn’t be saved. Check that the folder is writable.",
                comment: "Notes: saving the Markdown file failed")
        case .createFailed:
            String(localized: "The note couldn’t be created.", comment: "Notes: a new note could not be written")
        case .noteMade:
            String(localized: "Note created", comment: "Full window: a dictation was copied into a new note")
        case .makeNoteFailed:
            String(
                localized: "The note couldn’t be created. The dictation is unchanged.",
                comment: "Notes: Make note on a dictation failed")
        case .titleFailed:
            String(localized: "The title couldn’t be saved.", comment: "Notes: a note's title could not be written")
        case .deleted:
            String(localized: "note.deleted", defaultValue: "Deleted", comment: "Full window: the note was deleted")
        case .deleteFailed:
            String(
                localized: "The note couldn’t be deleted. Nothing was changed.",
                comment: "Notes: deleting a note failed or was refused")
        case .copyNotRemoved:
            String(
                localized: "The note was deleted, but the copy in Notes couldn’t be removed yet.",
                comment: "Notes: the owner deleted the note but its edited copy stayed")
        case .restored:
            String(localized: "Version restored", comment: "Full window: an earlier version became the current text")
        case .restoreChanged:
            String(
                localized: "The note changed in the meantime. Open the history again and restore from there.",
                comment: "Notes: a restore was refused because the note changed meanwhile")
        case .restoreReadOnly:
            String(
                localized: "Notes are read-only, so nothing can be restored.",
                comment: "Notes: a restore was refused because editing is off")
        case .restoreTargetInvalid:
            String(
                localized: "That is not an earlier saved version of this note. Nothing was changed.",
                comment: "Notes: a restore target was not an earlier applied version")
        case .proposalApplied:
            String(localized: "Proposal applied", comment: "Full window: a proposed version became the current text")
        case .proposalDiscarded:
            String(localized: "Proposal discarded", comment: "Full window: a proposed version was set aside")
        case .proposalChanged:
            String(
                localized: "The note changed in the meantime. Compare again before applying.",
                comment: "Notes: Apply was refused because the note changed after the comparison")
        case .proposalFailed:
            String(
                localized: "That proposal couldn’t be applied. Nothing was changed.",
                comment: "Notes: applying or discarding a proposal failed")
        case .commentFailed:
            String(
                localized: "The comment couldn’t be saved. Nothing was changed.",
                comment: "Notes: writing a comment failed")
        case .commentReadOnly:
            String(
                localized: "Notes are read-only, so nothing can be commented.",
                comment: "Notes: a comment was refused because editing is off")
        case .commentChanged:
            String(
                localized: "That text is not in the saved note. Select it again.",
                comment: "Notes: a comment was refused because the selected text is not in the saved note")
        case .commentTooLong:
            String(
                localized: "That comment is too long. Shorten it; nothing was saved.",
                comment: "Notes: a comment was refused because it is longer than the limit")
        case .commentSelectionTooLong:
            String(
                localized: "That passage is too long to comment on. Select a shorter one.",
                comment: "Notes: a comment was refused because the selected passage is too long")
        case .commentSelectionInvalid:
            String(
                localized: "Select some text in the note first, then comment.",
                comment: "Notes: a comment was refused because the selection is empty or outside the note")
        case .restoreFailed:
            String(
                localized: "That version couldn’t be restored. Nothing was changed.",
                comment: "Notes: restoring an earlier version failed")
        }
    }
}

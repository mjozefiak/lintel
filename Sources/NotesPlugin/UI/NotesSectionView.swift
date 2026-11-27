import LintelKit
import LintelUI
import SwiftUI

/// The Notes section of the main window (notes explorer spec): the list and the preview, or one note in the full
/// window with its bar ("‹ All notes"), the document and the inspector (phase 3b), and the status bar under both. The
/// shell owns the title bar and leaves its sidebar out while a note fills the window.
struct NotesSectionView: View {
    let model: NotesWorkspaceModel

    /// Never shown: the sheet is presented only while a request exists.
    private static let placeholder = DestructiveConfirmation(
        prompt: LocalizedStringResource("Delete this note?", comment: "Notes: title of the delete sheet"),
        detail: LocalizedStringResource("This can’t be undone.", comment: "Notes: delete sheet text"),
        confirmTitle: LocalizedStringResource("Delete", comment: "Notes: delete sheet button"))

    @Environment(\.lintelTextSize) private var textSize

    /// The inspector of the open note, when it is loaded.
    private var inspectorDocument: NoteDocumentModel? {
        guard model.inspectorVisible, let document = model.currentDocument, document.phase == .loaded else {
            return nil
        }
        return document
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.isFullWindow {
                fullWindow
            } else {
                ForEach(model.explorerStrips) { strip in NoteStripView(strip: strip, model: model) }
                HStack(spacing: 0) {
                    NoteListView(model: model, width: model.paneWidth(.explorer, textScale: textSize.scale))
                        .transaction(value: model.paneWidth(.explorer, textScale: textSize.scale)) {
                            $0.animation = nil
                        }
                    NotesPaneDivider(model: model, pane: .explorer)
                    NotePreviewView(model: model)
                }
            }
            NotesStatusBar(model: model)
        }
        .background(LintelBrand.windowBackground)
        .overlay {
            if model.palette != nil { NoteCommandPalette(model: model) }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: { width in
            model.updateInspectorFit(sectionWidth: width, textScale: textSize.scale)
        }
        // The text size changes what the centre column needs, so the same width may now be too narrow; the full
        // window has no list beside the document.
        .onChange(of: textSize.scale) {
            model.updateInspectorFit(sectionWidth: model.sectionWidth, textScale: textSize.scale)
        }
        .onChange(of: model.isFullWindow) {
            model.updateInspectorFit(sectionWidth: model.sectionWidth, textScale: textSize.scale)
        }
        .environment(model.preferences)
        .environment(\.notesAnimationsDisabled, model.animationsDisabled)
        .task { await model.run() }
        .destructiveConfirmation(
            isPresented: Binding(
                get: { model.pendingDelete != nil }, set: { if !$0 { model.cancelDelete() } }),
            model.pendingDelete.map(NoteDeleteConfirmation.make) ?? Self.placeholder
        ) {
            // Closing the sheet clears the request, so the task takes it now.
            guard let request = model.pendingDelete else { return }
            Task { await model.confirmDelete(request) }
        }
    }

    /// One note fills the section: its bar, the document and, beside it or over its edge, the inspector.
    private var fullWindow: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                NoteFullWindowBar(model: model)
                NoteCenter(model: model)
                    .hiddenContent(model.hidesContent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LintelBrand.windowBackground)
            // Next to the document when there is room; over its right edge when the section is narrow (the bar's
            // button asked for it), so Comments and History stay reachable at the largest text size.
            .overlay(alignment: .trailing) {
                if let document = inspectorDocument, !model.inspectorFits {
                    NoteInspector(
                        model: model, document: document,
                        width: model.paneWidth(.inspector, textScale: textSize.scale)
                    )
                    .hiddenContent(model.hidesContent)
                    .shadow(color: LintelBrand.ink.opacity(0.2), radius: 14, x: -4)
                    .notesFade(.inspector)
                }
            }
            if let document = inspectorDocument, model.inspectorFits {
                NoteInspector(
                    model: model, document: document,
                    width: model.paneWidth(.inspector, textScale: textSize.scale)
                )
                .hiddenContent(model.hidesContent)
                .notesFade(.inspector)
            }
        }
        .notesAnimation(.inspector, value: inspectorDocument != nil)
        // Esc goes back to the list. The editor, the search and title fields, the palette and the comment popover
        // take Esc first while they have the focus, so it never leaves the note under the user's typing.
        .onExitCommand {
            guard model.palette == nil else { return }
            model.closeFullWindow()
        }
    }
}

/// The document of the note in the full window, or what the section has to say while it cannot be shown.
struct NoteCenter: View {
    let model: NotesWorkspaceModel

    var body: some View {
        centre.notesAnimation(.tab, value: model.currentID)
    }

    @ViewBuilder private var centre: some View {
        if let document = model.currentDocument {
            NoteDocumentView(model: model, document: document)
                .id(document.id)
                .notesFade(.tab)
        } else {
            switch model.screen {
            case .list: Color.clear
            case let screen: NoteScreenView(model: model, screen: screen)
            }
        }
    }
}

/// The colour of a state dot (prototype `.dot`).
extension NoteStateLevel {
    @MainActor var color: Color {
        switch self {
        case .quiet: LintelBrand.hairline
        case .active: LintelBrand.accent
        case .attention: LintelBrand.statusAttention
        case .error: LintelBrand.statusError
        }
    }
}

extension NoteKind {
    /// The document's icon (prototype: people for a meeting, a microphone for a dictation).
    var symbolName: String {
        switch self {
        case .meeting: "person.2"
        case .dictation: "mic"
        default: "note.text"
        }
    }
}

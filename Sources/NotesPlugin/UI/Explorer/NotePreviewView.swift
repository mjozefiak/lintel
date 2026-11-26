import LintelKit
import LintelUI
import SwiftUI

/// The preview of the selected note (spec "Layout", phase 3a): the notes, My notes (read-only for now) and the
/// transcript of a meeting as tabs; the cleaned text of a dictation and the text of a note you wrote without tabs.
/// It reads the same `NoteDocumentModel` a tab would use, so nothing is read twice. A failed or switched-off set of
/// notes says so in words, and "Try Again" appears only when a recorder can really write them again.
struct NotePreviewView: View {
    let model: NotesWorkspaceModel
    @State private var showsMine = false
    @Environment(\.lintelTextSize) private var textSize

    var body: some View {
        Group {
            if let id = model.explorer.selection, let document = model.previewDocument {
                content(id: id, document: document)
                    .id(id)
            } else {
                EmptyStateView(
                    message: Text("Select a note to read it here.", comment: "Preview: nothing is selected"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LintelBrand.windowBackground)
        .hiddenContent(model.hidesContent)
    }

    @ViewBuilder private func content(id: NoteItemID, document: NoteDocumentModel) -> some View {
        switch document.phase {
        case .loading:
            NoteSkeletonDocument()
        case .unavailable:
            EmptyStateView(
                message: Text(
                    "Lintel couldn’t read this note. Nothing was deleted.",
                    comment: "Preview: the source did not answer"),
                actionTitle: Text("Try Again", comment: "Notes: tries the failed step again")
            ) {
                Task { await model.loadContent(id) }
            }
        case .gone:
            EmptyStateView(
                message: Text("This note is no longer there.", comment: "Preview: the note was removed"))
        case .loaded:
            loaded(id: id, document: document)
        }
    }

    private func isMeeting(_ document: NoteDocumentModel) -> Bool {
        document.layers.contains { $0.id == "notes" || $0.id == NoteDocumentModel.transcriptLayerID }
    }

    @ViewBuilder private func loaded(id: NoteItemID, document: NoteDocumentModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(document)
            if isMeeting(document) { tabs(document) }
            if let problem = problem(id: id, document: document) {
                notice(problem)
            } else if showsMine && isMeeting(document) {
                mineBody
            } else {
                blocks(document)
            }
            footer(document)
        }
    }

    // MARK: Header and tabs

    private func header(_ document: NoteDocumentModel) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8 * textSize.scale) {
            Text(verbatim: model.shown(title(document)))
                .font(textSize.font(.title2, weight: .semibold))
                .foregroundStyle(LintelBrand.ink)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button {
                model.open(document.id)
            } label: {
                Text("Open", comment: "Preview: opens the note in the full window")
            }
            .buttonStyle(LintelSecondaryButtonStyle())
            Button {
                if let text = document.markdown { NoteClipboard.copy(text, to: model.environment.pasteboard) }
            } label: {
                Text("Copy", comment: "Preview: copies the note as Markdown")
            }
            .buttonStyle(LintelSecondaryButtonStyle())
            .disabled(document.markdown == nil)
        }
        .padding(.horizontal, 24 * textSize.scale)
        .padding(.top, 16 * textSize.scale)
        .padding(.bottom, 8 * textSize.scale)
    }

    private func title(_ document: NoteDocumentModel) -> String {
        guard let summary = document.summary else { return "" }
        return model.presentation.title(summary)
    }

    private func tabs(_ document: NoteDocumentModel) -> some View {
        HStack(spacing: 4 * textSize.scale) {
            ForEach(tabItems(document), id: \.id) { item in
                let selected = item.id == "mine" ? showsMine : (!showsMine && document.layerID == item.id)
                Button {
                    if item.id == "mine" {
                        showsMine = true
                    } else {
                        showsMine = false
                        document.selectLayer(item.id)
                    }
                } label: {
                    Text(verbatim: item.title)
                        .font(textSize.font(.callout, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? LintelBrand.ink : LintelBrand.secondaryText)
                        .padding(.horizontal, 10 * textSize.scale)
                        .padding(.vertical, 4 * textSize.scale)
                        .background(
                            selected ? LintelBrand.windowSelectionTint : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20 * textSize.scale)
        .padding(.bottom, 6 * textSize.scale)
    }

    private struct TabItem {
        var id: String
        var title: String
    }

    private func tabItems(_ document: NoteDocumentModel) -> [TabItem] {
        var items: [TabItem] = []
        if document.layers.contains(where: { $0.id == "notes" }) {
            items.append(TabItem(id: "notes", title: NoteDocumentModel.title(ofLayer: "notes")))
        }
        items.append(
            TabItem(id: "mine", title: String(localized: "My notes", comment: "Preview: the tab with your own notes")))
        if document.layers.contains(where: { $0.id == NoteDocumentModel.transcriptLayerID }) {
            items.append(
                TabItem(
                    id: NoteDocumentModel.transcriptLayerID,
                    title: NoteDocumentModel.title(ofLayer: NoteDocumentModel.transcriptLayerID)))
        }
        return items
    }

    // MARK: Body

    private func blocks(_ document: NoteDocumentModel) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(document.blocks) { block in
                    NoteBlockRow(
                        document: document, block: block,
                        previous: block.index > 0 && block.index - 1 < document.blocks.count
                            ? document.blocks[block.index - 1] : nil)
                }
                if document.blocks.isEmpty {
                    Text("This note has no text yet.", comment: "Document: the shown layer has no text")
                        .font(textSize.font(.callout))
                        .foregroundStyle(LintelBrand.secondaryText)
                        .padding(.leading, 5.4 * 12.5 * textSize.scale)
                }
            }
            .padding(.vertical, 8 * textSize.scale)
        }
    }

    /// My notes is read-only in this phase: the line says so and what will be here.
    private var mineBody: some View {
        VStack(alignment: .leading, spacing: 6 * textSize.scale) {
            Text(
                "Your own notes about this meeting will appear here.",
                comment: "Preview: the My notes tab, nothing written yet")
            Text(
                "Open the note to write them.", comment: "Preview: where My notes can be written")
        }
        .font(textSize.font(.callout))
        .foregroundStyle(LintelBrand.secondaryText)
        .padding(.horizontal, 24 * textSize.scale)
        .padding(.vertical, 12 * textSize.scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: States of the notes

    /// What replaces the notes: a sentence and maybe one button. Plain values, so the view stays simple.
    private struct Problem {
        var message: String
        var buttonTitle: String?
        var perform: (@MainActor () -> Void)?
        var failed = false
        var isWriting = false
    }

    private func problem(id: NoteItemID, document: NoteDocumentModel) -> Problem? {
        guard isMeeting(document), !showsMine else { return nil }
        guard document.layerID == "notes" || document.layerID == nil else { return nil }
        switch document.state {
        case .failed?:
            let canRetry = model.canRetryNotes(id)
            let text =
                canRetry
                ? String(
                    localized: "Lintel couldn’t write the notes. The transcript is still here.",
                    comment: "Preview: the notes failed and can be written again")
                : String(
                    localized: "Lintel couldn’t write the notes. You can read the transcript.",
                    comment: "Preview: the notes failed and cannot be written from here")
            var result = Problem(message: text, failed: model.previewRetryFailed)
            if canRetry {
                result.buttonTitle = String(localized: "Try Again", comment: "Notes: tries the failed step again")
                result.perform = { Task { await model.retryNotes(id) } }
            }
            return result
        case .needsModel?:
            return Problem(
                message: String(
                    localized: "The notes are written once a model is downloaded to this Mac.",
                    comment: "Preview: the notes wait for a download"),
                buttonTitle: String(localized: "Download", comment: "Preview: opens the model download"),
                perform: { model.environment.openModels() })
        case .writing?, .processing?:
            return Problem(
                message: String(
                    localized: "Lintel is writing the notes.", comment: "Preview: the notes are being written"),
                isWriting: true)
        default:
            guard !document.layers.contains(where: { $0.id == "notes" }) else { return nil }
            return Problem(
                message: String(
                    localized: "Notes are off for this meeting.", comment: "Preview: no notes were written"))
        }
    }

    private func notice(_ problem: Problem) -> some View {
        VStack(alignment: .leading, spacing: 10 * textSize.scale) {
            HStack(spacing: 10 * textSize.scale) {
                if problem.isWriting { LintelRing(.processing(progress: nil), baseSize: 18) }
                Text(verbatim: problem.message)
                    .font(textSize.font(.callout))
                    .foregroundStyle(LintelBrand.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if problem.failed {
                Text(
                    "That didn’t finish. Nothing was changed.",
                    comment: "Notes: strip when an action of the source failed"
                )
                .font(textSize.font(.callout))
                .foregroundStyle(LintelBrand.statusError)
            }
            if let title = problem.buttonTitle, let perform = problem.perform {
                Button(action: perform) { Text(verbatim: title) }
                    .buttonStyle(LintelSecondaryButtonStyle())
            }
        }
        .padding(.horizontal, 24 * textSize.scale)
        .padding(.vertical, 12 * textSize.scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    // MARK: Footer

    @ViewBuilder private func footer(_ document: NoteDocumentModel) -> some View {
        if let text = footerText(document) {
            LintelDivider()
            Text(verbatim: text)
                .font(textSize.font(.footnote))
                .foregroundStyle(LintelBrand.secondaryText)
                .padding(.horizontal, 24 * textSize.scale)
                .padding(.vertical, 8 * textSize.scale)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func footerText(_ document: NoteDocumentModel) -> String? {
        if showsMine { return nil }
        if NoteCollection.isDictation(document.id) { return nil }
        guard document.layerID == "notes", let writer = document.selectedLayer?.writer else { return nil }
        switch writer {
        case .thisMac:
            return String(
                localized: "Written on this Mac. Nothing left your Mac.", comment: "Preview footer: built-in model")
        case .claude:
            return String(
                localized: "Written by Claude. The transcript was sent to Claude.",
                comment: "Preview footer: the external provider")
        }
    }
}

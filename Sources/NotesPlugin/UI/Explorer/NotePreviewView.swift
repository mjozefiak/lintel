import LintelKit
import LintelUI
import SwiftUI

/// The preview of the selected note (spec "Layout", phase 3a): the notes, My notes (read-only for now) and the
/// transcript of a meeting as tabs; the cleaned text of a dictation and the text of a note you wrote without tabs.
/// It reads the same `NoteDocumentModel` a tab would use, so nothing is read twice. A failed or switched-off set of
/// notes says so in words, and "Try Again" appears only when a recorder can really write them again.
struct NotePreviewView: View {
    let model: NotesWorkspaceModel
    /// The preview sits under the list in a narrow section (`NotesPaneLayout.isCompact`): smaller side margins and
    /// the title's buttons under it, so nothing is cut off.
    var compact = false
    @Environment(\.lintelTextSize) private var textSize

    /// The side margin of everything in the preview.
    private var gutter: CGFloat { (compact ? 14 : 24) * textSize.scale }

    var body: some View {
        Group {
            if let id = model.explorer.selection {
                Group {
                    if let document = model.previewDocument {
                        content(id: id, document: document)
                    } else {
                        NoteSkeletonDocument()
                    }
                }
                .id(id)
                .task(id: id) { await model.loadPreview(id) }
            } else if model.screen == .list {
                EmptyStateView(
                    message: Text("Select a note to read it here.", comment: "Preview: nothing is selected"))
            } else {
                // An empty, loading or locked list says it all; the preview has nothing to add.
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LintelBrand.windowBackground)
        .environment(\.notesCompact, compact)
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

    private func isMeeting(_ document: NoteDocumentModel) -> Bool { NotesWorkspaceModel.isMeeting(document) }

    private func showsMine(_ document: NoteDocumentModel) -> Bool {
        isMeeting(document) && model.previewTab == .mine
    }

    @ViewBuilder private func loaded(id: NoteItemID, document: NoteDocumentModel) -> some View {
        let notice = model.previewNotice(document)
        VStack(alignment: .leading, spacing: 0) {
            header(document, showsText: notice == nil && !showsMine(document))
            if isMeeting(document) { tabs(document) }
            if let notice {
                self.notice(problem(notice, id: id))
            } else if showsMine(document) {
                mineBody
            } else {
                blocks(document)
            }
        }
    }

    // MARK: Header and tabs

    /// - Parameter showsText: Copy is offered only while the text it would copy is the text on screen.
    private func header(_ document: NoteDocumentModel, showsText: Bool) -> some View {
        let titleText = Text(verbatim: model.shown(title(document)))
            .font(textSize.font(.title2, weight: .semibold))
            .foregroundStyle(LintelBrand.ink)
            .fixedSize(horizontal: false, vertical: true)
            .lineLimit(3)
            .accessibilityAddTraits(.isHeader)
        let buttons = HStack(spacing: 8 * textSize.scale) {
            Button {
                model.open(document.id)
            } label: {
                Text("Open", comment: "Preview: opens the note in the full window")
            }
            .buttonStyle(LintelSecondaryButtonStyle())
            // Without text there is nothing to copy; the button is left out rather than shown disabled with no reason.
            if showsText, let text = document.markdown {
                Button {
                    NoteClipboard.copy(text, to: model.environment.pasteboard)
                } label: {
                    Text("Copy", comment: "Preview: copies the note as Markdown")
                }
                .buttonStyle(LintelSecondaryButtonStyle())
            }
        }
        return Group {
            if compact {
                VStack(alignment: .leading, spacing: 8 * textSize.scale) {
                    titleText
                    buttons
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8 * textSize.scale) {
                    titleText
                    Spacer(minLength: 0)
                    buttons
                }
            }
        }
        .padding(.horizontal, gutter)
        .padding(.top, 16 * textSize.scale)
        .padding(.bottom, 8 * textSize.scale)
    }

    private func title(_ document: NoteDocumentModel) -> String {
        guard let summary = document.summary else { return "" }
        return model.presentation.title(summary)
    }

    private func tabs(_ document: NoteDocumentModel) -> some View {
        WrappingRow(spacing: 4 * textSize.scale, lineSpacing: 2 * textSize.scale) {
            ForEach(PreviewTab.allCases, id: \.self) { tab in
                let selected = model.previewTab == tab
                Button {
                    model.selectPreviewTab(tab)
                } label: {
                    Text(verbatim: Self.title(of: tab))
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
        }
        .padding(.horizontal, gutter - 4 * textSize.scale)
        .padding(.bottom, 6 * textSize.scale)
    }

    /// A meeting always has the three tabs: what is missing from one is said inside it.
    static func title(of tab: PreviewTab) -> String {
        switch tab {
        case .notes: NoteDocumentModel.title(ofLayer: "notes")
        case .mine: String(localized: "My notes", comment: "Preview: the tab with your own notes")
        case .transcript: NoteDocumentModel.title(ofLayer: NoteDocumentModel.transcriptLayerID)
        }
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
        .padding(.horizontal, gutter)
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

    /// The words and button of a notice; the choice of notice is `PreviewNotice.make`, tested without a view.
    private func problem(_ notice: PreviewNotice, id: NoteItemID) -> Problem {
        switch notice {
        case .failed(let canRetry):
            let text =
                canRetry
                ? String(
                    localized:
                        "Lintel couldn’t write the notes for this meeting. The recording and transcript are safe. Try again, or read the transcript.",
                    comment: "Preview: the notes failed and can be written again")
                : String(
                    localized:
                        "Lintel couldn’t write the notes for this meeting. The recording and transcript are safe. You can read the transcript.",
                    comment: "Preview: the notes failed and cannot be written from here")
            var result = Problem(message: text, failed: model.previewRetryFailed)
            if canRetry {
                result.buttonTitle = String(localized: "Try Again", comment: "Notes: tries the failed step again")
                result.perform = { Task { await model.retryNotes(id) } }
            }
            return result
        case .needsModel:
            return Problem(
                message: String(
                    localized: "Notes are written once Lintel has downloaded what it needs.",
                    comment: "Preview: the notes wait for a download"),
                buttonTitle: String(localized: "Download", comment: "Preview: opens the model download"),
                perform: { model.environment.openModels() })
        case .writing:
            return Problem(
                message: String(
                    localized: "Lintel is writing the notes.", comment: "Preview: the notes are being written"),
                isWriting: true)
        case .notesOff(let canWrite):
            // Without a recorder nothing here can write them; the sentence names the switch for new meetings.
            // There is no route from Notes to the Meetings pane yet (an owner question on #348).
            var result = Problem(
                message: canWrite
                    ? String(localized: "Notes are off for this meeting.", comment: "Preview: no notes were written")
                    : String(
                        localized:
                            "Notes are off for this meeting. For new meetings, turn on “Write notes after each meeting” in Settings → Meetings.",
                        comment: "Preview: no notes were written and they cannot be written from here"),
                failed: model.previewRetryFailed)
            if canWrite {
                result.buttonTitle = String(
                    localized: "Write Notes", comment: "Preview: writes the notes of a meeting that has none")
                result.perform = { Task { await model.retryNotes(id) } }
            }
            return result
        case .noText:
            return Problem(
                message: String(
                    localized: "This note has no text yet.", comment: "Document: the shown layer has no text"))
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
        .padding(.horizontal, gutter)
        .padding(.vertical, 12 * textSize.scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }
}

/// A row that wraps onto more lines when its children do not fit the width, left aligned. It measures like an
/// `HStack` while everything fits, so the wide layout does not change.
struct WrappingRow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    private func lines(_ subviews: Subviews, width: CGFloat) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return (frames, CGSize(width: widest, height: y + lineHeight))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = lines(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: min(result.size.width, proposal.width ?? .infinity), height: result.size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = lines(subviews, width: bounds.width)
        for (subview, frame) in zip(subviews, result.frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: .unspecified)
        }
    }
}

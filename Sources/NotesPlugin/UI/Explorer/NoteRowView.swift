import LintelKit
import LintelUI
import SwiftUI

/// One note in the list (spec "Layout"): the type ring, the title (up to three lines, never cut to one), the meta
/// line with the word for the kind, the time at the right and, for a note that is being worked on or needs
/// attention, the state in words beside its ring. Verdigris marks only the selection and live rings.
struct NoteRowView: View {
    let model: NotesWorkspaceModel
    let row: NoteRow
    @Environment(\.lintelTextSize) private var textSize

    private var isSelected: Bool { model.explorer.selection == row.id }

    var body: some View {
        let text = ExplorerRowText(presentation: model.presentation)
        let state = text.state(row.badge)
        let snippet = model.snippetText(of: row)
        HStack(alignment: .top, spacing: 10 * textSize.scale) {
            LintelRing(state.ring, mark: ExplorerRowText.mark(row.summary), baseSize: 18)
                .padding(.top, 1 * textSize.scale)
            VStack(alignment: .leading, spacing: 2 * textSize.scale) {
                Text(verbatim: model.shownTitle(of: row))
                    .font(textSize.font(.callout, weight: .medium))
                    .foregroundStyle(LintelBrand.ink)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let snippet {
                    Text(HighlightedSnippet.make(snippet, query: model.searchQuery?.raw ?? ""))
                        .font(textSize.font(.footnote))
                        .foregroundStyle(LintelBrand.secondaryText)
                        .lineLimit(2)
                } else {
                    Text(verbatim: text.meta(row.summary))
                        .font(textSize.font(.footnote))
                        .foregroundStyle(LintelBrand.secondaryText)
                        .lineLimit(2)
                }
                if let words = state.text {
                    Text(verbatim: words)
                        .font(textSize.font(.footnote, weight: .medium))
                        .foregroundStyle(stateColor(state.level))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            Text(verbatim: text.time(row.summary))
                .font(textSize.font(.footnote))
                .foregroundStyle(LintelBrand.secondaryText)
                .padding(.top, 2 * textSize.scale)
        }
        .padding(.horizontal, 10 * textSize.scale)
        .padding(.vertical, 7 * textSize.scale)
        .background(
            isSelected ? LintelBrand.windowSelectionTint : Color.clear, in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(Rectangle())
        .padding(.horizontal, 6 * textSize.scale)
        .padding(.vertical, 1)
        .onTapGesture(count: 2) { model.open(row.id) }
        .onTapGesture { model.select(row: row.id) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(verbatim: text.accessibilityLabel(row, snippet: snippet, title: model.shownTitle(of: row)))
        )
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(Text("Shows the note. Return opens it.", comment: "Accessibility hint of a list row"))
        .accessibilityAction { model.select(row: row.id) }
        .accessibilityAction(named: Text("Open", comment: "Opens the note in the full window")) {
            model.open(row.id)
        }
        .contextMenu {
            Button {
                model.open(row.id)
            } label: {
                Text("Open", comment: "Opens the note in the full window")
            }
            if NoteCollection.isDictation(row) {
                Button {
                    Task { await model.makeNote(from: row.id) }
                } label: {
                    Text("Make note", comment: "Path bar and explorer: copies a dictation into a new note")
                }
                .disabled(!model.canMakeNote(row.id))
            }
            if model.canDelete(row.id) {
                Button(role: .destructive) {
                    Task { await model.requestDelete(row.id) }
                } label: {
                    Text("Delete…", comment: "Explorer: deletes the note after a confirmation")
                }
            }
        }
    }

    private func stateColor(_ level: NoteStateLevel) -> Color {
        switch level {
        case .quiet, .active: LintelBrand.secondaryText
        case .attention: LintelBrand.statusAttention
        case .error: LintelBrand.statusError
        }
    }
}

/// A search hit's snippet with the query's words marked (the selection tint, accent text, bold).
enum HighlightedSnippet {
    @MainActor
    static func make(_ snippet: String, query: String) -> AttributedString {
        var text = AttributedString(snippet)
        for range in NoteRowPresentation.highlightRanges(in: snippet, query: query) {
            guard let lower = AttributedString.Index(range.lowerBound, within: text),
                let upper = AttributedString.Index(range.upperBound, within: text)
            else { continue }
            text[lower..<upper].backgroundColor = LintelBrand.windowSelectionTint
            text[lower..<upper].foregroundColor = LintelBrand.accentText
            text[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
        }
        return text
    }
}

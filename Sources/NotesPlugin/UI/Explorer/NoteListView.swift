import LintelKit
import LintelUI
import SwiftUI

/// The list column of the explorer (spec "Layout"): the collection's name, the search field and "New note", the day
/// groups with their rows, and what the list says when there is nothing to list. ↑ / ↓ move the selection, Return
/// opens the note in the full window, ⌘⌫ deletes the selected note, Esc ends a search (`handleListKey`). Hide content
/// masks titles and drops snippets.
struct NoteListView: View {
    let model: NotesWorkspaceModel
    @Environment(\.lintelTextSize) private var textSize
    @FocusState private var listFocused: Bool

    /// Set by the section from `NotesWorkspaceModel.paneWidth` (a dragged width, else the default); `nil` in a narrow
    /// section, where the list takes the whole width.
    let width: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            header
            ExplorerSearchField(model: model)
            list
        }
        .frame(width: width)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .background(LintelBrand.windowBackground)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(verbatim: NoteListView.title(of: model.collection))
                .font(textSize.font(.title3, weight: .semibold))
                .foregroundStyle(LintelBrand.ink)
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            NewNoteButton(model: model, style: .icon)
        }
        .padding(.horizontal, 14 * textSize.scale)
        .padding(.top, 12 * textSize.scale)
        .padding(.bottom, 2 * textSize.scale)
    }

    /// The heading of a collection, as the sidebar names it.
    static func title(of collection: NoteCollection) -> String {
        switch collection {
        case .all: String(localized: "All notes", comment: "Sidebar and list heading: every note")
        case .meetings: String(localized: "Meetings", comment: "Explorer: group of meeting notes")
        case .dictations:
            String(localized: "Dictations", comment: "Explorer: the switch and the label above the list of dictations")
        }
    }

    private func result(_ key: ExplorerListKey) -> KeyPress.Result {
        model.handleListKey(key) ? .handled : .ignored
    }

    @ViewBuilder private var list: some View {
        let screen = model.screen
        switch screen {
        case .list:
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if model.isSearching {
                            ForEach(model.rows) { row in NoteRowView(model: model, row: row).id(row.id) }
                        } else {
                            ForEach(model.groups) { group in
                                Text(verbatim: model.title(of: group))
                                    .font(textSize.font(.footnote, weight: .semibold))
                                    .foregroundStyle(LintelBrand.secondaryText)
                                    .padding(.horizontal, 16 * textSize.scale)
                                    .padding(.top, 10 * textSize.scale)
                                    .padding(.bottom, 2 * textSize.scale)
                                    .accessibilityAddTraits(.isHeader)
                                ForEach(group.rows) { row in NoteRowView(model: model, row: row).id(row.id) }
                            }
                        }
                        if model.hasMore {
                            Color.clear.frame(height: 1).task(id: model.pageToken) { await model.loadMore() }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .hiddenContent(model.hidesContent)
                .onChange(of: model.explorer.selection) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
            .focusable()
            .focused($listFocused)
            // The system ring would frame the whole column; the selected row draws its own (`NoteRowView`).
            .focusEffectDisabled()
            .environment(\.explorerListFocused, listFocused)
            .onChange(of: model.listFocusRequests) { listFocused = true }
            .onKeyPress(.upArrow) { result(.up) }
            .onKeyPress(.downArrow) { result(.down) }
            .onKeyPress(.return) { result(.open) }
            .onKeyPress(.escape) { result(.escape) }
            // ⌘⌫ deletes the selected note; in the editor it stays "delete to the start of the line".
            .onKeyPress(.delete, phases: .down) { press in
                press.modifiers == .command ? result(.delete) : .ignored
            }
            .accessibilityLabel(Text(verbatim: Self.title(of: model.collection)))
        case .loading:
            ExplorerSkeleton()
        case .locked:
            ExplorerEmptyView(content: .locked, model: model)
        case .empty:
            ExplorerEmptyView(content: model.emptyContent, model: model)
        case .noResults(let query):
            ExplorerEmptyView(content: .noResults(query: query, collection: model.collection), model: model)
        }
    }
}

/// An empty list as `EmptyStateView`, its action wired to the model.
struct ExplorerEmptyView: View {
    let content: ExplorerEmptyContent
    let model: NotesWorkspaceModel

    var body: some View {
        ScrollView {
            EmptyStateView(
                message: Text(verbatim: content.message), hint: content.hint.map { Text(verbatim: $0) },
                actionTitle: content.action.map { Text(verbatim: ExplorerEmptyContent.title(of: $0)) }
            ) {
                guard let action = content.action else { return }
                Task { await model.perform(action) }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// Grey bars where the rows will be, while the first page is read.
struct ExplorerSkeleton: View {
    @Environment(\.lintelTextSize) private var textSize

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { _ in
                HStack(alignment: .top, spacing: 10 * textSize.scale) {
                    LintelRing(.idle, mark: .dictation, baseSize: 18).opacity(0.4)
                    VStack(alignment: .leading, spacing: 0) {
                        NoteSkeletonBar(width: 0.75)
                        NoteSkeletonBar(width: 0.45)
                    }
                }
                .padding(.horizontal, 16 * textSize.scale)
                .padding(.vertical, 6 * textSize.scale)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading notes", comment: "Accessibility label while the notes are read"))
    }
}

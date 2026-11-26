import LintelUI
import SwiftUI

/// The "Speakers" list of the meeting window (mockup `.ai/specs/assets/meeting-speaker-names/speakers-list.html`):
/// a circle with the initials or the number, the name, "You" at the user's own speaker; a click on a name edits it
/// in place; a suggestion is one line under the name ("Marek?", the time it was heard, Yes, No); a name another
/// speaker has turns into one line asking whether to merge. It draws a value (`State`) and calls back
/// (`Actions`), so the gallery can show every state without a store. Colours come from `LintelBrand` only.
struct MeetingSpeakersList: View {
    struct Suggestion: Equatable {
        var name: String
        /// "03:12"; `nil` when no evidence points at a time.
        var heardAt: String?
        /// The segment the time scrolls to; `nil` draws the time as plain text.
        var segmentID: Int64?
    }

    struct Row: Equatable, Identifiable {
        var id: Int64
        var name: String
        /// The initials of a name, or the number of a default label.
        var badge: String
        var isSelf: Bool
        var canMarkSelf: Bool
        /// The tooltip of an automatic name ("Introduced themselves at 03:12"); `nil` shows none.
        var origin: String?
        var suggestion: Suggestion?
    }

    struct State: Equatable {
        var rows: [Row]
        var edit: MeetingWindowModel.SpeakerEdit?
        var mergeOffer: MeetingWindowModel.MergeOffer?
    }

    struct Actions {
        var beginEditing: (Int64) -> Void = { _ in }
        var updateDraft: (String) -> Void = { _ in }
        var commitEdit: () -> Void = {}
        var cancelEdit: () -> Void = {}
        var confirm: (Int64) -> Void = { _ in }
        var reject: (Int64) -> Void = { _ in }
        var showEvidence: (Int64) -> Void = { _ in }
        var markSelf: (Int64) -> Void = { _ in }
        var merge: () -> Void = {}
        var keepSeparate: () -> Void = {}
        var cancelMerge: () -> Void = {}
    }

    let state: State
    let actions: Actions

    @Environment(\.lintelTextSize) private var textSize
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Speakers", comment: "Meeting window: heading of the speaker list")
                .font(textSize.font(.callout, weight: .semibold))
                .foregroundStyle(LintelBrand.secondaryText)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
            ForEach(state.rows) { row in
                LintelDivider()
                speakerRow(row)
                if let offer = state.mergeOffer, offer.speakerID == row.id {
                    mergeLine(offer)
                } else if let suggestion = row.suggestion, state.edit?.speakerID != row.id {
                    suggestionLine(suggestion, of: row)
                }
            }
        }
        .lintelBrand()
    }

    // MARK: Rows

    private func speakerRow(_ row: Row) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: row.badge)
                .font(textSize.font(.caption1, weight: .semibold))
                // The mockup's grey disc with light letters: the muted text colour as the fill, the card as the text.
                .foregroundStyle(LintelBrand.card)
                .frame(width: 22 * textSize.scale, height: 22 * textSize.scale)
                .background(LintelBrand.secondaryText, in: Circle())
                .accessibilityHidden(true)
            if state.edit?.speakerID == row.id {
                nameField(row)
            } else {
                nameButton(row)
            }
            Spacer(minLength: 0)
            if row.isSelf {
                Text("You", comment: "Meeting window: marks the speaker who is the user")
                    .font(textSize.font(.callout))
                    .foregroundStyle(LintelBrand.secondaryText)
            }
        }
        .padding(.vertical, 7)
    }

    private func nameButton(_ row: Row) -> some View {
        Button {
            actions.beginEditing(row.id)
        } label: {
            Text(verbatim: row.name)
                .font(textSize.font(.body))
                .foregroundStyle(LintelBrand.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state.mergeOffer != nil)
        .help(row.origin ?? "")
        .contextMenu {
            Button {
                actions.beginEditing(row.id)
            } label: {
                Text("Rename", comment: "Meeting window: context menu item that edits a speaker's name")
            }
            if row.canMarkSelf {
                Button {
                    actions.markSelf(row.id)
                } label: {
                    Text("This is me", comment: "Meeting window button: mark this speaker as the user")
                }
            }
        }
        .accessibilityLabel(Text(verbatim: row.name))
        .accessibilityHint(Text("Rename this speaker", comment: "Meeting window: hint of a speaker's name"))
        .accessibilityAction(named: Text("This is me", comment: "Meeting window button: mark this speaker as the user"))
        {
            if row.canMarkSelf { actions.markSelf(row.id) }
        }
    }

    private func nameField(_ row: Row) -> some View {
        TextField(
            text: Binding(get: { state.edit?.draft ?? row.name }, set: { actions.updateDraft($0) })
        ) {
            Text("Speaker name", comment: "Meeting window: label of a speaker name field")
        }
        .textFieldStyle(.roundedBorder)
        .font(textSize.font(.body))
        .focused($fieldFocused)
        .onAppear { fieldFocused = true }
        .onSubmit { actions.commitEdit() }
        .onExitCommand { actions.cancelEdit() }
        // Clicking elsewhere saves, like Return; Esc has already closed the edit, so it saves nothing.
        .onChange(of: fieldFocused) { _, focused in if !focused { actions.commitEdit() } }
        .accessibilityLabel(Text("Speaker name", comment: "Meeting window: label of a speaker name field"))
        .accessibilityHint(
            Text(
                "Type the name, then press Return. Escape cancels.",
                comment: "Meeting window: hint of the speaker name field"))
    }

    // MARK: Lines under a row

    private func suggestionLine(_ suggestion: Suggestion, of row: Row) -> some View {
        HStack(spacing: 8) {
            Text("\(suggestion.name)?", comment: "Meeting window: a suggested speaker name; the name")
                .font(textSize.font(.callout))
                .foregroundStyle(LintelBrand.ink)
            if let time = suggestion.heardAt {
                if suggestion.segmentID != nil {
                    Button {
                        actions.showEvidence(row.id)
                    } label: {
                        Text("heard at \(time)", comment: "Meeting window: link to where a name was heard; the time")
                            .font(textSize.font(.callout))
                            .foregroundStyle(LintelBrand.accentText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(
                        Text("Shows where the name was heard", comment: "Meeting window: hint of the heard-at link"))
                } else {
                    Text("heard at \(time)", comment: "Meeting window: link to where a name was heard; the time")
                        .font(textSize.font(.callout))
                        .foregroundStyle(LintelBrand.secondaryText)
                }
            }
            Button {
                actions.confirm(row.id)
            } label: {
                Text("Yes", comment: "Meeting window: confirms a suggested speaker name")
            }
            .buttonStyle(LintelPrimaryButtonStyle())
            .accessibilityLabel(Text("Confirm", comment: "Meeting window: accessibility label of Yes on a suggestion"))
            Button {
                actions.reject(row.id)
            } label: {
                Text("No", comment: "Meeting window: rejects a suggested speaker name")
            }
            .buttonStyle(LintelSecondaryButtonStyle())
            .accessibilityLabel(Text("Reject", comment: "Meeting window: accessibility label of No on a suggestion"))
            Spacer(minLength: 0)
        }
        .padding(.leading, 32 * textSize.scale)
        .padding(.bottom, 6)
        .focusable()
        .onKeyPress(.return) {
            actions.confirm(row.id)
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            Text(
                "Name suggestion: \(suggestion.name). Confirm or Reject",
                comment: "Meeting window: VoiceOver label of a suggested speaker name; the name"))
    }

    private func mergeLine(_ offer: MeetingWindowModel.MergeOffer) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { mergeContent(offer) }
            VStack(alignment: .leading, spacing: 6) {
                mergeQuestion(offer)
                HStack(spacing: 8) { mergeButtons }
            }
        }
        .padding(.leading, 32 * textSize.scale)
        .padding(.bottom, 6)
        // Esc on the line (a button in it has the focus) is Cancel.
        .onExitCommand { actions.cancelMerge() }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func mergeContent(_ offer: MeetingWindowModel.MergeOffer) -> some View {
        mergeQuestion(offer)
        mergeButtons
        Spacer(minLength: 0)
    }

    private func mergeQuestion(_ offer: MeetingWindowModel.MergeOffer) -> some View {
        Text(
            "\(offer.name) is already in this meeting. Merge?",
            comment: "Meeting window: a typed name belongs to another speaker; the name"
        )
        .font(textSize.font(.callout))
        .foregroundStyle(LintelBrand.ink)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var mergeButtons: some View {
        Button {
            actions.merge()
        } label: {
            Text(
                LocalizedStringResource(
                    "Merge (speakers)", defaultValue: "Merge", comment: "Meeting window: merges two speakers into one"))
        }
        .buttonStyle(LintelPrimaryButtonStyle())
        .accessibilityHint(
            Text("Both speakers become one person", comment: "Meeting window: hint of Merge"))
        Button {
            actions.keepSeparate()
        } label: {
            Text("Keep Separate", comment: "Meeting window: keeps two speakers with the same name")
        }
        .buttonStyle(LintelSecondaryButtonStyle())
        .accessibilityHint(
            Text("Two people with the same name", comment: "Meeting window: hint of Keep Separate"))
        Button {
            actions.cancelMerge()
        } label: {
            Text("Cancel", comment: "Meeting window: cancels renaming a speaker")
        }
        .buttonStyle(LintelSecondaryButtonStyle())
    }
}

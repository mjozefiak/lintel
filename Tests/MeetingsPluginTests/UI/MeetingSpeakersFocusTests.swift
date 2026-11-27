import AppKit
import LintelTestSupport
import LintelUI
import SwiftUI
import Testing

@testable import MeetingsPlugin

/// QA of #352: the speaker name field in a real window (B1, focus), the list's state rules (m1) and the
/// accessibility of the list (m3, m4) and of Settings → Meetings' switches (#361).
@MainActor
@Suite(.serialized) struct MeetingSpeakersFocusTests {
    @MainActor @Observable final class Box {
        var state: MeetingSpeakersList.State
        var title = "Przegląd wdrożenia"
        var drafts: [String] = []
        var commits: [Int64] = []
        var cancels = 0
        var mergeCancels = 0

        init(_ state: MeetingSpeakersList.State) { self.state = state }

        var actions: MeetingSpeakersList.Actions {
            MeetingSpeakersList.Actions(
                beginEditing: { [unowned self] id in state.edit = .init(speakerID: id, draft: "Mówca 3") },
                updateDraft: { [unowned self] in drafts.append($0) },
                commitEdit: { [unowned self] in commits.append($0) },
                cancelEdit: { [unowned self] in cancels += 1 },
                cancelMerge: { [unowned self] in mergeCancels += 1 })
        }
    }

    /// The meeting window's order: the title field first (the first key view), then the speakers.
    struct Host: View {
        @Bindable var box: Box

        var body: some View {
            VStack(alignment: .leading) {
                TextField("Title", text: $box.title)
                MeetingSpeakersList(state: box.state, actions: box.actions)
            }
            .padding(16)
            .frame(width: 420)
        }
    }

    private static let rows: [MeetingSpeakersList.Row] = [
        .init(id: 1, name: "Anna Kowalska", badge: "AK", isSelf: true, canMarkSelf: false, origin: nil),
        .init(
            id: 2, name: "Bartek Nowak", badge: "BN", isSelf: false, canMarkSelf: true,
            origin: "Introduced themselves at 02:50"),
        .init(
            id: 3, name: "Mówca 2", badge: "2", isSelf: false, canMarkSelf: true, origin: nil,
            suggestion: .init(name: "Marek", heardAt: "03:12", segmentID: 7)),
        .init(id: 4, name: "Mówca 3", badge: "3", isSelf: false, canMarkSelf: true, origin: nil),
    ]

    private func window(_ box: Box) -> (NSWindow, NSHostingView<Host>) {
        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 460, height: 400), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: Host(box: box))
        window.contentView = host
        window.orderFrontRegardless()
        return (window, host)
    }

    /// The field editor of the speaker name field, when it has the keyboard.
    private func speakerEditor(in window: NSWindow) -> NSTextView? {
        guard let editor = window.firstResponder as? NSTextView else { return nil }
        let delegate: AnyObject? = editor.delegate
        return delegate is SpeakerNameTextField ? editor : nil
    }

    // MARK: B1

    @Test func aClickedNameTakesTheKeyboardAndReturnSavesItNotTheTitle() async throws {
        let box = Box(.init(rows: Self.rows))
        let (window, host) = window(box)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        box.actions.beginEditing(4)
        let focused = await pollUntil("the speaker field to take the keyboard", guard: .seconds(10)) {
            host.layoutSubtreeIfNeeded()
            return speakerEditor(in: window) != nil
        }
        #expect(focused)
        let editor = try #require(speakerEditor(in: window))
        editor.selectAll(nil)
        editor.insertText("Ola", replacementRange: editor.selectedRange())
        #expect(box.drafts.last == "Ola")
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(!box.commits.isEmpty)
        #expect(box.commits.allSatisfy { $0 == 4 })
        #expect(box.cancels == 0)
        #expect(box.title == "Przegląd wdrożenia")
    }

    @Test func escapeInTheFieldCancelsTheEdit() async throws {
        let box = Box(.init(rows: Self.rows))
        let (window, host) = window(box)
        defer { window.close() }
        box.actions.beginEditing(4)
        let focused = await pollUntil("the speaker field to take the keyboard", guard: .seconds(10)) {
            host.layoutSubtreeIfNeeded()
            return speakerEditor(in: window) != nil
        }
        #expect(focused)
        let editor = try #require(speakerEditor(in: window))
        let commitsBefore = box.commits
        editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        #expect(box.cancels == 1)
        #expect(box.commits == commitsBefore)
        #expect(box.title == "Przegląd wdrożenia")
    }

    /// Review m1 of rv6: the old field leaving the window when another name opens says which speaker it was, so its
    /// focus loss saves that speaker's name and never closes the next field.
    @Test func theOldFieldsFocusLossNamesItsOwnSpeaker() async throws {
        let box = Box(.init(rows: Self.rows))
        let (window, host) = window(box)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        box.actions.beginEditing(4)
        let first = await pollUntil("the first speaker field to take the keyboard", guard: .seconds(10)) {
            host.layoutSubtreeIfNeeded()
            return speakerEditor(in: window) != nil
        }
        #expect(first)
        let editor = try #require(speakerEditor(in: window))
        editor.insertText("Ola", replacementRange: editor.selectedRange())
        box.actions.beginEditing(2)
        let moved = await pollUntil("the second speaker field to take the keyboard", guard: .seconds(10)) {
            host.layoutSubtreeIfNeeded()
            return !box.commits.isEmpty && speakerEditor(in: window) != nil
        }
        #expect(moved)
        #expect(box.commits == [4])
        #expect(box.state.edit?.speakerID == 2)
    }

    // MARK: m1, m2

    @Test func yesOnASuggestionWaitsWhileAMergeQuestionIsShown() {
        var state = MeetingSpeakersList.State(rows: Self.rows)
        #expect(state.answersSuggestions)
        state.mergeOffer = .init(speakerID: 4, targetID: 2, name: "Bartek Nowak", origin: .rename)
        #expect(!state.answersSuggestions)
    }

    @Test func escapeAnywhereInTheWindowCancelsTheMergeQuestion() async throws {
        var state = MeetingSpeakersList.State(rows: Self.rows)
        state.mergeOffer = .init(speakerID: 4, targetID: 2, name: "Bartek Nowak", origin: .rename)
        let box = Box(state)
        let (window, host) = window(box)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        // Nothing in the list has the keyboard: the window itself is the first responder.
        window.makeFirstResponder(nil)
        let escape = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false,
                keyCode: 53))
        let handled = await pollUntil("Esc to reach the merge question's Cancel", guard: .seconds(10)) {
            host.layoutSubtreeIfNeeded()
            return window.performKeyEquivalent(with: escape)
        }
        #expect(handled)
        #expect(box.mergeCancels == 1)
    }

    // MARK: m3, m4, #361 (accessibility)
    //
    // SwiftUI builds its accessibility tree only for a running assistive client, so an in-process walk of an
    // `NSHostingView` finds no rows and no switches; these read the sources instead. The live check is in the QA of
    // #352 (Accessibility Inspector, System Events).

    private static func source(_ name: String) throws -> String {
        try String(contentsOf: TestPaths.meetingsSource(named: name), encoding: .utf8)
    }

    @Test func thisIsMeIsOfferedOnlyWhereItWorksAndTheOriginIsSpoken() throws {
        let list = try Self.source("MeetingSpeakersList.swift")
        // The VoiceOver action exists only on a row that can be marked (not the user's own, not an unsupported one).
        #expect(!list.contains(".accessibilityAction(named:"))
        let actions = try #require(list.range(of: ".accessibilityActions {"))
        let body = list[actions.upperBound...].prefix(200)
        #expect(body.contains("if row.canMarkSelf {"))
        // `.help` and `.accessibilityHint` are both AXHelp: the origin is the value, so VoiceOver reads it.
        #expect(list.contains(".accessibilityValue(Text(verbatim: row.origin ?? \"\"))"))
    }

    @Test func everySwitchInSettingsMeetingsHasItsRowsLabel() throws {
        let pane = try Self.source("MeetingsSettingsPane.swift")
        let parts = pane.components(separatedBy: "Toggle(").dropFirst()
        #expect(parts.count >= 6)
        for part in parts {
            // The modifiers right after the switch's label, up to the next view.
            let chain = try #require(part.range(of: ".toggleStyle(.switch)")).upperBound
            let after = part[chain...].prefix(160)
            #expect(after.contains(".accessibilityLabel("), "a switch without its row's label: \(part.prefix(80))")
        }
    }
}

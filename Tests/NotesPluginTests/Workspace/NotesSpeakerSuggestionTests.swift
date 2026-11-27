import AppKit
import Foundation
import LintelKit
import LintelTestSupport
import LintelUI
import SwiftUI
import Testing

@testable import NotesPlugin

/// A source that lists and reads notes but cannot edit them (no `NoteSourceEditing`).
private struct ReadOnlySource: NoteSource {
    let base: ScriptedNoteSource
    var pluginID: PluginID { base.pluginID }
    func list(matching query: NormalizedQuery?, after: NoteCursor?, limit: Int) async throws -> NotePage {
        try await base.list(matching: query, after: after, limit: limit)
    }
    func exists(_ keys: [NoteKey]) async throws -> Set<NoteKey> { try await base.exists(keys) }
    func content(for key: NoteKey) async throws -> NoteContent? { try await base.content(for: key) }
    func delete(_ key: NoteKey) async throws {}
    func actions(for key: NoteKey) -> [NoteSourceAction] { [] }
    func makeChanges() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

@MainActor
private final class SpeakerRig {
    static let key = Fixtures.key("meetings", "orchard")
    static let segments: [(speaker: String, text: String)] = [
        ("1", "Let us start."), ("2", "I will send the build."), ("2", "Today."), ("1", "Thanks."),
    ]

    let source = ScriptedNoteSource(
        "meetings", items: [Fixtures.summary("meetings", "orchard", secondsAgo: 60, title: "Orchard")])
    var model: NotesWorkspaceModel
    var confirmCalls: [(NoteKey, String, String)] = []
    var rejectCalls: [(NoteKey, String, String)] = []
    var failure: (any Error)?
    let answerGate = Gate()
    let answers = CountLatch()

    init(
        speakers: [NoteSpeaker] = SpeakerRig.suggesting, editable: Bool = true,
        heads: [OverlayLayerHead] = []
    ) {
        source.contents[Self.key] = Self.content(speakers: speakers, summary: source.items[0])
        let box = SourceBox(editable ? [source] : [ReadOnlySource(base: source)])
        var environment = NotesWorkspaceModel.Environment(
            library: NoteLibrary(box: box), pasteboard: RecordingPasteboard())
        environment.overlayHeads = { _ in heads }
        model = NotesWorkspaceModel(environment: environment)
        var wired = environment
        wired.confirmSpeakerName = { [unowned self] key, speakerID, name in
            self.confirmCalls.append((key, speakerID, name))
            self.answers.increment()
            await self.answerGate.pass()
            if let failure = self.failure { throw failure }
        }
        wired.rejectSpeakerName = { [unowned self] key, speakerID, name in
            self.rejectCalls.append((key, speakerID, name))
            self.answers.increment()
            if let failure = self.failure { throw failure }
        }
        model = NotesWorkspaceModel(environment: wired)
    }

    static let suggesting = [
        NoteSpeaker(id: "1", name: "Kasia"),
        NoteSpeaker(id: "2", name: "Speaker 2", nameStatus: .suggested, suggestion: "Marek"),
    ]

    static func content(speakers: [NoteSpeaker], summary: NoteSummary) -> NoteContent {
        NoteContent(
            summary: summary,
            layers: [
                // The notes layer names a speaker too: a suggestion still belongs to the transcript only.
                NoteLayer(
                    id: "notes", author: .agent, markdown: "Ship it.",
                    provenance: [NoteBlockProvenance(blockIndex: 0, speakerID: "2")], version: "1"),
                NoteLayer(
                    id: "transcript", author: .stt, markdown: segments.map(\.text).joined(separator: "\n\n"),
                    provenance: segments.enumerated().map { index, segment in
                        NoteBlockProvenance(
                            blockIndex: index, speakerID: segment.speaker, startMs: index * 1000,
                            segmentRef: "\(index)")
                    }, version: "1"),
            ], speakers: speakers)
    }

    /// Opens the meeting on its transcript.
    func open() async throws -> NoteDocumentModel {
        await model.refresh()
        let item = NoteItemID.live(Self.key)
        model.open(item)
        await model.loadContent(item)
        let document = try #require(model.documents[item])
        document.selectLayer("transcript")
        return document
    }

    /// The speaker ids whose suggestion is shown, by block.
    static func shown(_ document: NoteDocumentModel) -> [Int: String] {
        var result: [Int: String] = [:]
        for block in document.blocks {
            if let suggestion = document.speakerSuggestion(at: block) { result[block.index] = suggestion.name }
        }
        return result
    }
}

@MainActor
@Suite("Notes: speaker name suggestions in the transcript (speaker names 1.6b)")
struct NotesSpeakerSuggestionTests {
    @Test func theSuggestionIsShownOnceUnderTheSpeakersFirstWords() async throws {
        let rig = SpeakerRig()
        let document = try await rig.open()
        #expect(document.canEditSpeakers)
        #expect(SpeakerRig.shown(document) == [1: "Marek"])
        // Not on the notes layer.
        document.selectLayer("notes")
        #expect(SpeakerRig.shown(document).isEmpty)
    }

    @Test(arguments: [
        NoteSpeaker(id: "2", name: "Marek", nameStatus: .applied),
        NoteSpeaker(id: "2", name: "Marek", nameStatus: .confirmed, suggestion: "Marek"),
        NoteSpeaker(id: "2", name: "Speaker 2", nameStatus: .suggested),
        NoteSpeaker(id: "2", name: "Speaker 2", nameStatus: .suggested, suggestion: "  "),
    ])
    func onlyASuggestedNameWithASuggestionAsks(_ speaker: NoteSpeaker) async throws {
        let rig = SpeakerRig(speakers: [NoteSpeaker(id: "1", name: "Kasia"), speaker])
        let document = try await rig.open()
        #expect(SpeakerRig.shown(document).isEmpty)
    }

    @Test func aSourceThatCannotEditShowsNoSuggestion() async throws {
        let rig = SpeakerRig(editable: false)
        let document = try await rig.open()
        #expect(!document.canEditSpeakers)
        #expect(document.answerSpeakerSuggestion == nil)
        #expect(SpeakerRig.shown(document).isEmpty)
    }

    @Test func aDocumentNobodyWiredShowsNoSuggestion() {
        // A document loaded outside the workspace (a preview, the old call of the transcript views) shows the
        // transcript as before: no suggestion line.
        let document = NoteDocumentModel(id: .live(SpeakerRig.key))
        document.apply(
            SpeakerRig.content(
                speakers: SpeakerRig.suggesting,
                summary: Fixtures.summary("meetings", "orchard", secondsAgo: 60)))
        document.selectLayer("transcript")
        document.canEditSpeakers = true
        #expect(SpeakerRig.shown(document).isEmpty)
        // The views keep their inputs: the old calls still build.
        let block = try? #require(document.blocks.first)
        if let block {
            _ = NoteBlockRow(document: document, block: block, previous: nil)
            _ = TranscriptLine(document: document, block: block)
        }
    }

    @Test func aHandlerWithoutAnEditingSourceShowsNoSuggestion() {
        let document = NoteDocumentModel(id: .live(SpeakerRig.key))
        document.apply(
            SpeakerRig.content(
                speakers: SpeakerRig.suggesting,
                summary: Fixtures.summary("meetings", "orchard", secondsAgo: 60)))
        document.selectLayer("transcript")
        document.answerSpeakerSuggestion = { _, _, _ in }
        #expect(SpeakerRig.shown(document).isEmpty)
        document.canEditSpeakers = true
        #expect(SpeakerRig.shown(document) == [1: "Marek"])
    }

    @Test func aDetachedNoteShowsNoSuggestion() {
        let document = NoteDocumentModel(id: .detached(SpeakerRig.key, startedAtMs: 1))
        document.apply(
            SpeakerRig.content(
                speakers: SpeakerRig.suggesting,
                summary: Fixtures.summary("meetings", "orchard", secondsAgo: 60)))
        document.selectLayer("transcript")
        document.canEditSpeakers = true
        document.answerSpeakerSuggestion = { _, _, _ in }
        #expect(SpeakerRig.shown(document).isEmpty)
    }

    @Test func aTranscriptWithAnOverlayStillShowsTheSourcesSuggestion() async throws {
        // The overlay's seed keeps speakers without a status; a live note takes them from the source.
        let head = OverlayLayerHead(
            layerID: "transcript", markdown: "Let us start.\n\nI will send the build, edited.\n\nToday.\n\nThanks.",
            provenance: SpeakerRig.segments.enumerated().map { index, segment in
                NoteBlockProvenance(blockIndex: index, speakerID: segment.speaker, startMs: index * 1000)
            },
            seedSpeakers: [NoteSpeaker(id: "1", name: "Kasia"), NoteSpeaker(id: "2", name: "Speaker 2")])
        let rig = SpeakerRig(heads: [head])
        let document = try await rig.open()
        #expect(document.blocks[1].source.contains("edited"))
        #expect(SpeakerRig.shown(document) == [1: "Marek"])
    }

    @Test func yesSendsTheShownNameAndReadsTheNoteAgain() async throws {
        let rig = SpeakerRig()
        let document = try await rig.open()
        let suggestion = try #require(document.speakerSuggestion(at: document.blocks[1]))
        rig.source.contents[SpeakerRig.key] = SpeakerRig.content(
            speakers: [NoteSpeaker(id: "1", name: "Kasia"), NoteSpeaker(id: "2", name: "Marek")],
            summary: rig.source.items[0])
        let reads = rig.source.contentCalls
        await rig.model.answerSpeakerSuggestion(
            .live(SpeakerRig.key), document: document, speakerID: suggestion.speakerID, name: suggestion.name,
            confirm: true)
        #expect(rig.confirmCalls.map { "\($0.0.rawValue)|\($0.1)|\($0.2)" } == ["meetings:orchard|2|Marek"])
        #expect(rig.rejectCalls.isEmpty)
        #expect(rig.source.contentCalls == reads + 1)
        #expect(document.speakerName(of: document.blocks[1]) == "Marek")
        #expect(SpeakerRig.shown(document).isEmpty)
        #expect(!document.actionFailed)
        #expect(document.answeringSpeaker == nil)
    }

    @Test func noSendsTheShownNameAndKeepsTheLabel() async throws {
        let rig = SpeakerRig()
        let document = try await rig.open()
        rig.source.contents[SpeakerRig.key] = SpeakerRig.content(
            speakers: [NoteSpeaker(id: "1", name: "Kasia"), NoteSpeaker(id: "2", name: "Speaker 2")],
            summary: rig.source.items[0])
        await rig.model.answerSpeakerSuggestion(
            .live(SpeakerRig.key), document: document, speakerID: "2", name: "Marek", confirm: false)
        #expect(rig.rejectCalls.map { "\($0.1)|\($0.2)" } == ["2|Marek"])
        #expect(rig.confirmCalls.isEmpty)
        #expect(document.speakerName(of: document.blocks[1]) == "Speaker 2")
        #expect(SpeakerRig.shown(document).isEmpty)
    }

    @Test func aFailedAnswerShowsTheStripAndChangesNothing() async throws {
        let rig = SpeakerRig()
        rig.failure = NoteEditingError.unsupported
        let document = try await rig.open()
        let reads = rig.source.contentCalls
        await rig.model.answerSpeakerSuggestion(
            .live(SpeakerRig.key), document: document, speakerID: "2", name: "Marek", confirm: true)
        #expect(document.actionFailed)
        #expect(rig.source.contentCalls == reads, "nothing is read again")
        #expect(SpeakerRig.shown(document) == [1: "Marek"])
        #expect(rig.model.strips.contains { $0.id == "actionFailed" })
        #expect(document.answeringSpeaker == nil)
    }

    @Test func theLinesButtonsSendOneAnswerWhileItIsOnItsWay() async throws {
        let rig = SpeakerRig()
        let document = try await rig.open()
        let suggestion = try #require(document.speakerSuggestion(at: document.blocks[1]))
        rig.answerGate.hold(next: 1)
        document.answer(suggestion, confirm: true)
        #expect(document.answeringSpeaker == "2")
        document.answer(suggestion, confirm: true)
        document.answer(suggestion, confirm: false)
        await rig.answers.wait(atLeast: 1)
        rig.answerGate.release()
        let finished = await pollUntil("the answer to finish", guard: .seconds(10)) {
            document.answeringSpeaker == nil
        }
        #expect(finished)
        #expect(rig.confirmCalls.count == 1)
        #expect(rig.rejectCalls.isEmpty)
    }

    @Test func theLibrarySendsTheAnswerToTheOwner() async throws {
        let source = ScriptedNoteSource("meetings")
        let library = NoteLibrary(box: SourceBox([source]))
        try await library.answerSpeakerName(SpeakerRig.key, speakerID: "2", name: "Marek", confirm: true)
        try await library.answerSpeakerName(SpeakerRig.key, speakerID: "3", name: "Ola", confirm: false)
        #expect(
            source.speakerAnswers == [
                .init(key: SpeakerRig.key, speakerID: "2", name: "Marek", confirm: true),
                .init(key: SpeakerRig.key, speakerID: "3", name: "Ola", confirm: false),
            ])
        let plain = NoteLibrary(box: SourceBox([ReadOnlySource(base: ScriptedNoteSource("meetings"))]))
        await #expect(throws: NoteEditingError.unsupported) {
            try await plain.answerSpeakerName(SpeakerRig.key, speakerID: "2", name: "Marek", confirm: true)
        }
    }

    // MARK: Speaker column (#362)

    @Test func theSpeakerColumnFitsTheLongestNameWithinItsLimits() {
        let font = NSFont.systemFont(ofSize: 13, weight: .bold)
        let minimum = NoteDocumentModel.minimumSpeakerColumn(scale: 1)
        let maximum = NoteDocumentModel.maximumSpeakerColumn(scale: 1)
        #expect(NoteDocumentModel.speakerColumnWidth(names: ["Ola"], font: font, scale: 1) == minimum)
        #expect(NoteDocumentModel.speakerColumnWidth(names: [], font: font, scale: 1) == minimum)
        let full = NoteDocumentModel.speakerColumnWidth(names: ["Ola", "Anna Kowalska"], font: font, scale: 1)
        let measured = ("Anna Kowalska" as NSString).size(withAttributes: [.font: font]).width
        #expect(full >= measured)
        #expect(full > minimum && full < maximum)
        let long = NoteDocumentModel.speakerColumnWidth(
            names: ["Konstantyna Wierzbicka-Przybylska z Domu"], font: font, scale: 1)
        #expect(long == maximum)
        // At XL the limits grow with the text.
        #expect(NoteDocumentModel.maximumSpeakerColumn(scale: 1.3) > maximum)
    }

    @Test func theColumnIsMeasuredForTheShownSpeakers() {
        let document = NoteDocumentModel(id: .live(SpeakerRig.key))
        document.apply(
            SpeakerRig.content(
                speakers: [NoteSpeaker(id: "1", name: "Ola")],
                summary: Fixtures.summary("meetings", "orchard", secondsAgo: 60)))
        let narrow = document.speakerColumnWidth(textSize: .medium)
        document.apply(
            SpeakerRig.content(
                speakers: [NoteSpeaker(id: "1", name: "Katarzyna Nowakowska")],
                summary: Fixtures.summary("meetings", "orchard", secondsAgo: 60)))
        let wide = document.speakerColumnWidth(textSize: .medium)
        #expect(wide > narrow)
        #expect(document.speakerColumnWidth(textSize: .extraLarge) > wide)
    }
}

#if DEBUG
@Suite("Notes QA: speaker name suggestion fixture")
struct NotesQASpeakerNamesTests {
    @Test func yesAndNoAnswerInMemoryAndAStaleAnswerIsRefused() async throws {
        let sources = NotesQASpeakerNames.editable(NotesQAFixtureSource.all())
        let meetings = try #require(sources.first { $0.pluginID == "meetings" } as? any NoteSourceEditing)
        #expect(!(sources.first { $0.pluginID == "dictation" } is any NoteSourceEditing))
        let key = NotesQAFixtures.meetingID
        let before = try #require(try await meetings.content(for: key)).speakers
        #expect(before.first { $0.id == "2" }?.suggestion == "Marek")
        #expect(before.first { $0.id == "1" }?.name == "Katarzyna Nowakowska")
        await #expect(throws: (any Error).self) {
            try await meetings.confirmSpeakerName(key, speakerID: "2", name: "Ola")
        }
        try await meetings.confirmSpeakerName(key, speakerID: "2", name: "Marek")
        let after = try #require(try await meetings.content(for: key)).speakers.first { $0.id == "2" }
        #expect(after?.name == "Marek" && after?.nameStatus == .confirmed && after?.suggestion == nil)

        let other = NotesQASpeakerNames.editable(NotesQAFixtureSource.all())
        let fresh = try #require(other.first { $0.pluginID == "meetings" } as? any NoteSourceEditing)
        try await fresh.rejectSpeakerName(key, speakerID: "2", name: "Marek")
        let rejected = try #require(try await fresh.content(for: key)).speakers.first { $0.id == "2" }
        #expect(rejected?.name == "Speaker 2" && rejected?.nameStatus == .confirmed && rejected?.suggestion == nil)
    }
}
#endif

/// Return on the focused suggestion line says Yes, in a real (off-screen) window.
@MainActor
@Suite(.serialized) struct NotesSpeakerSuggestionKeyTests {
    @Test func returnOnTheFocusedLineConfirms() async throws {
        let document = NoteDocumentModel(id: .live(SpeakerRig.key))
        document.apply(
            SpeakerRig.content(
                speakers: SpeakerRig.suggesting,
                summary: Fixtures.summary("meetings", "orchard", secondsAgo: 60)))
        document.selectLayer("transcript")
        var answers: [(String, String, Bool)] = []
        document.answerSpeakerSuggestion = { answers.append(($0, $1, $2)) }
        document.canEditSpeakers = true
        let suggestion = try #require(document.speakerSuggestion(at: document.blocks[1]))
        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 460, height: 120), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: SpeakerSuggestionLine(document: document, suggestion: suggestion).padding(16))
        window.orderFrontRegardless()
        window.makeKey()
        defer { window.close() }
        func key(_ code: UInt16, _ characters: String) {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                if let event = NSEvent.keyEvent(
                    with: type, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                    context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
                    keyCode: code)
                {
                    window.sendEvent(event)
                }
            }
        }
        let focused = await pollUntil("the line to take the focus", guard: .seconds(10)) {
            if window.firstResponder === window { key(48, "\t") }
            return window.firstResponder !== window
        }
        #expect(focused)
        key(36, "\r")
        let answered = await pollUntil("Return to answer", guard: .seconds(10)) { !answers.isEmpty }
        #expect(answered)
        #expect(answers.map { "\($0.0)|\($0.1)|\($0.2)" } == ["2|Marek|true"])
    }
}

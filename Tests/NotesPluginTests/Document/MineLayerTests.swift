import Foundation
import LintelKit
import Testing

@testable import NotesPlugin

/// My notes (`mine`, notes explorer spec, Data Model): only `human` revisions are written to the layer
/// (`NotesError.mineIsHumanOnly`), and the agent never revises it. All text is synthetic.
@MainActor
@Suite(.finishesRigs, .timeLimit(.minutes(1))) struct MineLayerTests {
    private func mineDocument(_ rig: DocRig, body: String = ReviseFixtures.note) throws -> Int64 {
        try rig.store.insertDocument(.overlay("m1", layer: NotesStore.mineLayer, body: body, author: "human")).docID
    }

    private func revisionCount(_ rig: DocRig, _ docID: Int64) throws -> Int {
        try rig.store.revisions(of: docID).count
    }

    @Test func theUserWritesMyNotes() async throws {
        let rig = try DocRig()
        let docID = try mineDocument(rig)
        let writer = rig.writer(.existing(docID: docID))
        writer.submit("My own line.")
        try await writer.flush(closingSession: true)
        #expect(try rig.head(docID).body == "My own line.")
        #expect(try rig.head(docID).author == "human")
    }

    @Test func noOtherAuthorIsWrittenToMyNotes() async throws {
        let rig = try DocRig()
        let docID = try mineDocument(rig)
        let writer = rig.writer(.existing(docID: docID))
        let before = try revisionCount(rig, docID)
        let head = try rig.head(docID).id
        await #expect(throws: NotesError.mineIsHumanOnly) {
            try await writer.appendApplied(author: .agent, body: "rewritten", expectingHead: head)
        }
        await #expect(throws: NotesError.mineIsHumanOnly) {
            try await writer.appendApplied(author: .stt, body: "heard")
        }
        await #expect(throws: NotesError.mineIsHumanOnly) {
            try await writer.appendProposal(author: .agent, body: "a proposal")
        }
        // A source never offers `mine`; if one did, the reconciliation writes nothing either.
        await #expect(throws: NotesError.mineIsHumanOnly) {
            try await writer.reconcile(
                layer: NoteLayer(id: NotesStore.mineLayer, author: .agent, markdown: "source text", version: "v2"))
        }
        #expect(try revisionCount(rig, docID) == before)
        #expect(rig.log.errors.contains { $0.contains("mineIsHumanOnly") })
        #expect(!rig.log.all.contains { $0.contains("rewritten") || $0.contains("Decisions") })
    }

    @Test func aProposalByAnotherAuthorIsNeverAppliedToMyNotes() async throws {
        let rig = try DocRig()
        let docID = try mineDocument(rig)
        let head = try rig.head(docID).id
        let proposal = try rig.store.appendRevision(
            NewNoteRevision(docID: docID, author: "agent", state: .proposed, body: "agent text", now: Date()))
        let writer = rig.writer(.existing(docID: docID))
        await #expect(throws: NotesError.mineIsHumanOnly) {
            try await writer.applyProposal(id: proposal, expectingHead: head)
        }
        #expect(try rig.head(docID).id == head)
        // A human proposal (text kept after a conflict) still applies.
        let own = try rig.store.appendRevision(
            NewNoteRevision(docID: docID, author: "human", state: .proposed, body: "my kept text", now: Date()))
        try await writer.applyProposal(id: own, expectingHead: head)
        #expect(try rig.head(docID).body == "my kept text")
    }

    @Test func aSeedOfMyNotesByAnotherAuthorIsRefused() async throws {
        let rig = try DocRig()
        let writer = rig.writer(.seed(try rig.plan(rig.layer("seed", id: NotesStore.mineLayer, author: .agent))))
        await #expect(throws: NotesError.mineIsHumanOnly) { try await writer.ensureDocument() }
        #expect(try rig.store.liveDocument(key: rig.meeting, layer: NotesStore.mineLayer) == nil)
    }

    @Test func otherLayersKeepTheirAuthors() async throws {
        let rig = try DocRig()
        let doc = try rig.seededDocument(rig.layer("notes text", id: "notes"))
        let writer = rig.writer(.existing(docID: doc.id))
        try await writer.appendApplied(author: .agent, body: "revised by the agent")
        #expect(try rig.head(doc.id).author == "agent")
    }

    @Test func theAgentNeverPlansAUnitOnMyNotesAndNeverAsksForTheModel() async throws {
        let rig = try DocRig()
        let docID = try mineDocument(rig)
        let writer = rig.writer(.existing(docID: docID))
        let comments = CommentService(store: rig.store, now: { Date(timeIntervalSince1970: 1_800_000_100) })
        let text = ReviseFixtures.note as NSString
        _ = try await comments.add(
            body: "Add an owner.", selection: text.range(of: "next sprint"), buffer: ReviseFixtures.note,
            writer: writer)
        let lease = ScriptedReviseLease([.handle(ScriptedReviseHandle([.answer("[[unit 1]]\nchanged")]))])
        var deps = ReviseService.Dependencies(
            clock: RunClock(rig.clock), model: { ResolvedReviseModel(id: "qwen3-test", leasing: lease) })
        deps.log = rig.log
        let service = ReviseService(deps)
        let head = try rig.head(docID).id
        let outcome = await service.start(
            ReviseRequest(item: .live(rig.meeting), writer: writer, lock: EditLock(), store: rig.store, threads: nil))
        #expect(outcome == .nothingToRevise(skipped: []))
        #expect(lease.acquires.count == 0)
        #expect(try rig.head(docID).id == head)
    }
}

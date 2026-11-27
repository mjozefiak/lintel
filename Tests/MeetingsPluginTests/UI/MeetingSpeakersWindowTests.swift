import Foundation
import LintelKit
import LintelTestSupport
import Testing

@testable import MeetingsPlugin

/// The "Speakers" list of the meeting window (spec `2026-11-25-meeting-speaker-names`, step 1.6) over
/// `SpeakerNamesRig`: Anna (own), Bartek (`applied`), "Mówca 2" suggesting Marek, "Mówca 3".
@MainActor
@Suite struct MeetingSpeakersWindowTests {
    private func model(_ rig: SpeakerNamesRig) async -> MeetingWindowModel {
        let model = MeetingWindowModel(
            meetingID: rig.meetingID, store: rig.store, spool: RecordingSpool(existing: []),
            pasteboard: RecordingPasteboard(), saver: FakeFileSaver(), labels: .english, timeZone: ExportFixtures.utc)
        await model.load()
        return model
    }

    // MARK: Reading

    @Test func theListShowsNamesBadgesTheSuggestionAndTheOrigin() async throws {
        let rig = try await SpeakerNamesRig.make()
        let list = await model(rig).speakerList
        #expect(list.rows.map(\.name) == ["Anna Kowalska", "Bartek Nowak", "Mówca 2", "Mówca 3"])
        #expect(list.rows.map(\.badge) == ["AK", "BN", "2", "3"])
        #expect(list.rows.map(\.isSelf) == [true, false, false, false])
        #expect(
            list.rows[2].suggestion
                == MeetingSpeakersList.Suggestion(name: "Marek", heardAt: "03:12", segmentID: rig.marekSegment))
        #expect(list.rows.filter { $0.suggestion != nil }.count == 1)
        #expect(list.rows[1].origin == "Introduced themselves at 02:50")
        #expect(list.rows[0].origin == nil)
        #expect(list.rows[2].origin == nil)
    }

    @Test func theTimeOfASuggestionScrollsToItsSegment() async throws {
        let rig = try await SpeakerNamesRig.make()
        let model = await model(rig)
        model.showEvidence(of: rig.second)
        #expect(model.scrollRequest?.segmentID == rig.marekSegment)
        let first = try #require(model.scrollRequest?.serial)
        model.showEvidence(of: rig.second)
        #expect(model.scrollRequest?.serial == first + 1)
        model.showEvidence(of: rig.third)
        #expect(model.scrollRequest?.serial == first + 1)
    }

    // MARK: Editing in place

    @Test func returnSavesTheTypedName() async throws {
        let rig = try await SpeakerNamesRig.make()
        let model = await model(rig)
        await model.beginEditing(rig.third)
        #expect(model.speakerEdit == .init(speakerID: rig.third, draft: "Mówca 3"))
        model.updateDraft("  Ola  ")
        await model.commitEdit(of: rig.third)
        #expect(model.speakerEdit == nil)
        #expect(try rig.state(rig.third)?.label == "Ola")
        #expect(try rig.state(rig.third)?.source == .user)
        #expect(model.speakerList.rows[3].name == "Ola")
    }

    @Test func anAppliedNameIsEditableToo() async throws {
        let rig = try await SpeakerNamesRig.make()
        let model = await model(rig)
        await model.beginEditing(rig.bartek)
        model.updateDraft("Bartosz Nowak")
        await model.commitEdit(of: rig.bartek)
        #expect(try rig.state(rig.bartek)?.label == "Bartosz Nowak")
        #expect(try rig.state(rig.bartek)?.source == .user)
    }

    @Test func escapeSavesNothingEvenWhenTheFieldLosesFocusAfterwards() async throws {
        let rig = try await SpeakerNamesRig.make()
        let model = await model(rig)
        await model.beginEditing(rig.third)
        model.updateDraft("Ola")
        model.cancelEdit()
        // The field losing focus after Esc commits through the same path, which finds no open edit.
        await model.commitEdit(of: rig.third)
        #expect(try rig.state(rig.third)?.label == "Mówca 3")
        #expect(try rig.store.notesStatus(of: rig.meetingID) == .ok)
    }

    @Test func aBlankOrUnchangedNameSavesNothing() async throws {
        let rig = try await SpeakerNamesRig.make()
        let model = await model(rig)
        for draft in ["   ", "\u{200B}", "Mówca 3"] {
            await model.beginEditing(rig.third)
            model.updateDraft(draft)
            await model.commitEdit(of: rig.third)
        }
        #expect(try rig.state(rig.third)?.label == "Mówca 3")
        #expect(try rig.store.notesStatus(of: rig.meetingID) == .ok)
    }

    // MARK: Moving to another name (review m1 of rv6)

    @Test func clickingAnotherNameSavesTheOpenDraftAndEditsThatName() async throws {
        let rig = try await SpeakerNamesRig.make()
        let model = await model(rig)
        await model.beginEditing(rig.third)
        model.updateDraft("Ola")
        await model.beginEditing(rig.second)
        #expect(try rig.state(rig.third)?.label == "Ola")
        #expect(try rig.state(rig.third)?.source == .user)
        #expect(model.speakerEdit == .init(speakerID: rig.second, draft: "Mówca 2"))
        #expect(model.mergeOffer == nil)
    }

    @Test func aBlankOrUnchangedDraftIsDroppedWhenAnotherNameIsClicked() async throws {
        let rig = try await SpeakerNamesRig.make()
        let model = await model(rig)
        for draft in ["   ", "Mówca 3"] {
            await model.beginEditing(rig.third)
            model.updateDraft(draft)
            await model.beginEditing(rig.second)
            #expect(model.speakerEdit == .init(speakerID: rig.second, draft: "Mówca 2"))
            model.cancelEdit()
        }
        #expect(try rig.state(rig.third)?.label == "Mówca 3")
        #expect(try rig.store.notesStatus(of: rig.meetingID) == .ok)
    }

    @Test func aDraftWithAnotherSpeakersNameAsksBeforeTheNextNameOpens() async throws {
        let rig = try await SpeakerNamesRig.make()
        let model = await model(rig)
        await model.beginEditing(rig.third)
        model.updateDraft("Bartek Nowak")
        await model.beginEditing(rig.second)
        #expect(
            model.mergeOffer
                == .init(speakerID: rig.third, targetID: rig.bartek, name: "Bartek Nowak", origin: .rename))
        #expect(model.speakerEdit == nil)
        #expect(try rig.state(rig.third)?.label == "Mówca 3")
    }

    @Test func theOldFieldsLateFocusLossLeavesTheNextEditOpen() async throws {
        let rig = try await SpeakerNamesRig.make()
        let model = await model(rig)
        await model.beginEditing(rig.third)
        model.updateDraft("Ola")
        await model.beginEditing(rig.second)
        model.updateDraft("Ewa")
        // The first field leaves the window only now and says it lost the keyboard.
        await model.commitEdit(of: rig.third)
        #expect(model.speakerEdit == .init(speakerID: rig.second, draft: "Ewa"))
        #expect(try rig.state(rig.second)?.label == "Mówca 2")
        #expect(try rig.state(rig.third)?.label == "Ola")
        await model.commitEdit(of: rig.second)
        #expect(try rig.state(rig.second)?.label == "Ewa")
        #expect(model.speakerEdit == nil)
    }

    /// The window's wiring: a save from the list names its speaker, so the old field's focus loss arriving after a
    /// click on another name neither closes nor saves the new edit.
    @Test func theWindowsActionsSaveOnlyTheSpeakerTheyName() async throws {
        let rig = try await SpeakerNamesRig.make()
        let model = await model(rig)
        let actions = MeetingWindowView.speakerActions(for: model)
        actions.beginEditing(rig.third)
        #expect(await pollUntil("the first edit", guard: .seconds(10)) { model.speakerEdit?.speakerID == rig.third })
        actions.updateDraft("Ola")
        actions.beginEditing(rig.second)
        #expect(await pollUntil("the second edit", guard: .seconds(10)) { model.speakerEdit?.speakerID == rig.second })
        actions.updateDraft("Ewa")
        // The first field's focus loss, late.
        actions.commitEdit(rig.third)
        let saved = await pollUntil("the first name to be saved", guard: .seconds(10)) {
            (try? rig.state(rig.third)?.label) == "Ola" && model.speakerList.rows[3].name == "Ola"
        }
        #expect(saved)
        #expect(model.speakerEdit?.speakerID == rig.second)
        #expect(try rig.state(rig.second)?.label == "Mówca 2")
    }

    // MARK: The merge question

    @Test func aNameAnotherSpeakerHasAsksToMergeInsteadOfSaving() async throws {
        let rig = try await SpeakerNamesRig.make()
        let model = await model(rig)
        await model.beginEditing(rig.third)
        model.updateDraft("bartek nowak")
        await model.commitEdit(of: rig.third)
        #expect(
            model.mergeOffer
                == .init(speakerID: rig.third, targetID: rig.bartek, name: "bartek nowak", origin: .rename))
        #expect(model.speakerList.mergeOffer == model.mergeOffer)
        #expect(try rig.state(rig.third)?.label == "Mówca 3")
        // While the question waits, another edit does not start.
        await model.beginEditing(rig.second)
        #expect(model.speakerEdit == nil)
    }

    @Test func mergeJoinsTheTwoSpeakers() async throws {
        let rig = try await SpeakerNamesRig.make()
        let model = await model(rig)
        await model.beginEditing(rig.third)
        model.updateDraft("Bartek Nowak")
        await model.commitEdit(of: rig.third)
        await model.mergeSpeakers()
        #expect(model.mergeOffer == nil)
        #expect(try rig.state(rig.third) == nil)
        #expect(try rig.segmentSpeakers() == [rig.bartek, rig.second, rig.bartek])
        #expect(try rig.store.notesStatus(of: rig.meetingID) == .stale)
        #expect(model.speakerList.rows.map(\.name) == ["Anna Kowalska", "Bartek Nowak", "Mówca 2"])
    }

    @Test func keepSeparateSavesTheNameAtBoth() async throws {
        let rig = try await SpeakerNamesRig.make()
        let model = await model(rig)
        await model.beginEditing(rig.third)
        model.updateDraft("Bartek Nowak")
        await model.commitEdit(of: rig.third)
        await model.keepSeparate()
        #expect(model.mergeOffer == nil)
        #expect(try rig.state(rig.third)?.label == "Bartek Nowak")
        #expect(try rig.state(rig.bartek)?.label == "Bartek Nowak")
        #expect(try rig.segmentSpeakers() == [rig.bartek, rig.second, rig.third])
    }

    @Test func cancelLeavesEverythingAsItWas() async throws {
        let rig = try await SpeakerNamesRig.make()
        let model = await model(rig)
        await model.beginEditing(rig.third)
        model.updateDraft("Bartek Nowak")
        await model.commitEdit(of: rig.third)
        model.cancelMerge()
        #expect(model.mergeOffer == nil)
        #expect(try rig.state(rig.third)?.label == "Mówca 3")
        #expect(try rig.store.notesStatus(of: rig.meetingID) == .ok)
    }

    @Test func aDefaultLabelNeverAsksToMerge() async throws {
        let rig = try await SpeakerNamesRig.make()
        let model = await model(rig)
        await model.beginEditing(rig.third)
        model.updateDraft("Mówca 2")
        await model.commitEdit(of: rig.third)
        #expect(model.mergeOffer == nil)
        #expect(try rig.state(rig.third)?.label == "Mówca 2")
    }

    @Test func aMeetingBeingProcessedRenamesWithoutAsking() async throws {
        let rig = try await SpeakerNamesRig.make(status: .processing)
        let model = await model(rig)
        await model.beginEditing(rig.third)
        model.updateDraft("Bartek Nowak")
        await model.commitEdit(of: rig.third)
        #expect(model.mergeOffer == nil)
        #expect(try rig.state(rig.third)?.label == "Bartek Nowak")
    }

    // MARK: Suggestions

    @Test func yesConfirmsTheSuggestion() async throws {
        let rig = try await SpeakerNamesRig.make()
        let model = await model(rig)
        await model.confirmSuggestion(rig.second)
        let state = try #require(try rig.state(rig.second))
        #expect(state.label == "Marek")
        #expect(state.source == .user)
        #expect(state.suggestedName == nil)
        #expect(try rig.store.notesStatus(of: rig.meetingID) == .stale)
        #expect(model.speakerList.rows[2].suggestion == nil)
        #expect(model.speakerList.rows[2].name == "Marek")
    }

    @Test func noRejectsTheSuggestion() async throws {
        let rig = try await SpeakerNamesRig.make()
        let model = await model(rig)
        await model.rejectSuggestion(rig.second)
        let state = try #require(try rig.state(rig.second))
        #expect(state.label == "Mówca 2")
        #expect(state.rejectedNames == ["Marek"])
        #expect(try rig.store.notesStatus(of: rig.meetingID) == .ok)
        #expect(model.speakerList.rows[2].suggestion == nil)
    }

    @Test func yesOnANameAnotherSpeakerHasAsksToMerge() async throws {
        let rig = try await SpeakerNamesRig.make()
        try rig.store.renameSpeaker(rig.third, label: "Marek")
        let model = await model(rig)
        await model.confirmSuggestion(rig.second)
        #expect(model.mergeOffer == .init(speakerID: rig.second, targetID: rig.third, name: "Marek", origin: .confirm))
        #expect(try rig.state(rig.second)?.suggestedName == "Marek")
        await model.keepSeparate()
        #expect(try rig.state(rig.second)?.label == "Marek")
        #expect(try rig.state(rig.third)?.label == "Marek")
    }

    @Test func aFailedEditSaysSo() async throws {
        let rig = try await SpeakerNamesRig.make()
        let model = await model(rig)
        try rig.store.write { db in
            try db.execute(
                sql: "UPDATE meeting_speaker SET suggested_name = 'Mariusz' WHERE id = ?", arguments: [rig.second])
        }
        // The screen still shows Marek: the store refuses, the feedback says so and the reload shows Mariusz.
        await model.confirmSuggestion(rig.second)
        #expect(model.feedback == .actionFailed)
        #expect(model.speakerList.rows[2].suggestion?.name == "Mariusz")
    }

    // MARK: Pure helpers

    @Test func badgesAreInitialsOrTheNumber() {
        #expect(MeetingWindowModel.badge(for: "Anna Kowalska") == "AK")
        #expect(MeetingWindowModel.badge(for: "ola") == "O")
        #expect(MeetingWindowModel.badge(for: "Anna Maria Kowalska") == "AM")
        #expect(MeetingWindowModel.badge(for: "Mówca 12") == "12")
        #expect(MeetingWindowModel.badge(for: "Speaker 2") == "2")
        #expect(MeetingWindowModel.badge(for: "") == "?")
    }

    @Test func theTimeIsShortUnderAnHour() {
        #expect(MeetingWindowModel.shortClock(milliseconds: 192_000) == "03:12")
        #expect(MeetingWindowModel.shortClock(milliseconds: 0) == "00:00")
        #expect(MeetingWindowModel.shortClock(milliseconds: 3_792_000) == "1:03:12")
    }
}

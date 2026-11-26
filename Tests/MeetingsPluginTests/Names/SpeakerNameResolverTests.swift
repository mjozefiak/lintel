import Foundation
import Testing

@testable import MeetingsPlugin

/// The pure name resolution (spec `2026-11-25-meeting-speaker-names`, step 1.4a): priority of the sources, the
/// untouchable names the user gave, one name per cluster and one cluster per name, and the thresholds of the
/// platform share. Every name here is fictional; nothing touches the database, the model or the network.
@Suite struct SpeakerNameResolverTests {
    private func cluster(
        _ id: Int, label: String = "Mówca 1", channel: AudioChannel = .system, isSelf: Bool = false,
        source: NameSource = .default, status: SpeakerNameStatus = .suggested, rejected: [String] = [],
        suggestion: String? = nil
    ) -> SpeakerNameCluster {
        SpeakerNameCluster(
            id: id, channel: channel, isSelf: isSelf, label: label, source: source, status: status,
            rejectedNames: rejected, suggestedName: suggestion)
    }

    private func evidence(
        _ name: String, source: NameSource = .transcript, kind: NameEvidenceKind? = .introduction,
        confidence: NameEvidenceConfidence? = .high, speaker: String = "Mówca 1", segment: Int? = nil,
        strength: Double = 1
    ) -> NameEvidence {
        NameEvidence(
            source: source, name: name, speaker: speaker, kind: kind, segment: segment, startMs: nil, endMs: nil,
            strength: strength, confidence: confidence)
    }

    private func resolve(
        _ clusters: [SpeakerNameCluster], selfName: String = "", evidence: [NameEvidence] = [],
        known: [String] = [], calendar: SpeakerNameCalendar? = nil, segments: [Int: Int] = [:],
        mode: SpeakerMode = .diarized
    ) -> [SpeakerNameResolution] {
        SpeakerNameResolver.resolve(
            SpeakerNameRequest(
                mode: mode, clusters: clusters, selfName: selfName, evidence: evidence, knownNames: known,
                calendar: calendar, segmentClusters: segments))
    }

    private func result(_ id: Int, _ results: [SpeakerNameResolution]) -> SpeakerNameResolution? {
        results.first { $0.cluster == id }
    }

    // MARK: Priority of the sources

    @Test func aUserNameBeatsEverythingTheAutomaticSourcesSay() {
        let name = cluster(1, label: "Marek", source: .user, status: .confirmed)
        let results = resolve(
            [name],
            evidence: [
                evidence("Anna", speaker: "Marek"),
                evidence("Anna", source: .platform, kind: nil, confidence: nil, speaker: "Marek", strength: 0.9),
            ])
        #expect(result(1, results)?.name == "Marek")
        #expect(result(1, results)?.source == .user)
        #expect(result(1, results)?.status == .confirmed)
        #expect(result(1, results)?.evidence.isEmpty == true)
    }

    @Test func theOwnersNameBeatsANameSaidInTheConversation() {
        let owner = cluster(1, label: SpeakerLabels.me, channel: .mic, isSelf: true, source: .me, status: .applied)
        let results = resolve(
            [owner], selfName: "Marek", evidence: [evidence("Anna", speaker: SpeakerLabels.me)])
        #expect(result(1, results)?.name == "Marek")
        #expect(result(1, results)?.source == .me)
        #expect(result(1, results)?.status == .applied)
    }

    @Test func thePlatformBeatsTheConversation() {
        let first = cluster(1)
        let results = resolve(
            [first],
            evidence: [
                evidence("Anna", speaker: "Mówca 1"),
                evidence("Marek", source: .platform, kind: nil, confidence: nil, strength: 0.7),
            ])
        #expect(result(1, results)?.name == "Marek")
        #expect(result(1, results)?.source == .platform)
    }

    @Test func anAppliedNameFromALowerSourceBeatsASuggestionFromAHigherOne() {
        // A weak platform share (suggested) against a sure self-introduction (applied): the state decides first.
        let results = resolve(
            [cluster(1)],
            evidence: [
                evidence("Zofia"),
                evidence("Ala", source: .platform, kind: nil, confidence: nil, strength: 0.35),
            ])
        #expect(result(1, results)?.name == "Zofia")
        #expect(result(1, results)?.source == .transcript)
        #expect(result(1, results)?.status == .applied)
        #expect(result(1, results)?.suggestedName == nil)
    }

    @Test func withinOneStateTheHigherSourceWins() {
        // Two suggestions: a weak platform share and a vocative. The platform outranks the conversation.
        let results = resolve(
            [cluster(1)],
            evidence: [
                evidence("Zofia", kind: .addressed),
                evidence("Ala", source: .platform, kind: nil, confidence: nil, strength: 0.35),
            ])
        #expect(result(1, results)?.name == nil)
        #expect(result(1, results)?.status == .suggested)
        #expect(result(1, results)?.suggestedName == "Ala")
        #expect(result(1, results)?.source == .platform)
    }

    @Test func aVocativeNamesTheClusterThatAnswersNotTheCaller() {
        // Segment 0: Mówca 1 calls "Zofia, ..."; segment 1: Mówca 2 answers. The quote's segment is the caller's.
        let results = resolve(
            [cluster(1, label: "Mówca 1"), cluster(2, label: "Mówca 2")],
            evidence: [evidence("Zofia", kind: .addressed, speaker: "Mówca 2", segment: 0)],
            segments: [0: 1, 1: 2])
        #expect(result(1, results)?.suggestedName == nil)
        #expect(result(2, results)?.suggestedName == "Zofia")
    }

    @Test func anAnnouncementNamesTheNextSpeakerEvenWithASharedLabel() {
        // Two people kept apart under one label: the segment after the quote decides which one is meant.
        let known = ["Zofia"]
        let results = resolve(
            [cluster(1, label: "Mówca 1"), cluster(2, label: "Mówca 2"), cluster(3, label: "Mówca 2")],
            evidence: [evidence("Zofia", kind: .announced, speaker: "Mówca 2", segment: 1)],
            known: known, segments: [0: 2, 1: 1, 2: 3])
        #expect(result(3, results)?.name == "Zofia")
        #expect(result(2, results)?.name == nil)
        #expect(result(1, results)?.name == nil)
    }

    @Test func aVocativeWithoutAnAnswerIsDropped() {
        let results = resolve(
            [cluster(1, label: "Mówca 1"), cluster(2, label: "Mówca 2")],
            evidence: [evidence("Zofia", kind: .addressed, speaker: "Mówca 2", segment: 1)],
            segments: [0: 2, 1: 1])
        #expect(results.allSatisfy { $0.name == nil && $0.suggestedName == nil })
    }

    @Test func theConversationBeatsTheCalendar() {
        let owner = cluster(1, label: SpeakerLabels.me, channel: .mic, isSelf: true)
        let other = cluster(2, label: "Mówca 1")
        let results = resolve(
            [owner, other],
            evidence: [evidence("Marek", speaker: "Mówca 1")],
            calendar: SpeakerNameCalendar(attendeeNames: ["Anna"], includesOwner: true))
        #expect(result(2, results)?.name == "Marek")
        #expect(result(2, results)?.source == .transcript)
        #expect(result(2, results)?.suggestedName == nil)
    }

    @Test func thePlatformBeatsTheCalendar() {
        let owner = cluster(1, label: SpeakerLabels.me, channel: .mic, isSelf: true)
        let other = cluster(2, label: "Mówca 1")
        let results = resolve(
            [owner, other],
            evidence: [
                evidence("Marek", source: .platform, kind: nil, confidence: nil, speaker: "Mówca 1", strength: 0.8)
            ],
            calendar: SpeakerNameCalendar(attendeeNames: ["Anna"], includesOwner: true))
        #expect(result(2, results)?.name == "Marek")
        #expect(result(2, results)?.source == .platform)
    }

    @Test func anAutomaticNameNeverTakesAUserName() {
        let name = cluster(1, label: "Marek", source: .user, status: .confirmed)
        let other = cluster(2)
        let results = resolve(
            [name, other],
            evidence: [
                evidence("Marek", source: .platform, kind: nil, confidence: nil, speaker: "Mówca 1", strength: 0.9)
            ])
        #expect(result(2, results)?.name == nil)
        #expect(result(2, results)?.suggestedName == nil)
    }

    @Test func anAutomaticNameNeverTakesTheOwnersName() {
        let owner = cluster(1, label: SpeakerLabels.me, channel: .mic, isSelf: true)
        let other = cluster(2)
        let results = resolve(
            [owner, other], selfName: "Marek",
            evidence: [
                evidence("Marek", source: .platform, kind: nil, confidence: nil, speaker: "Mówca 1", strength: 0.9)
            ])
        #expect(result(1, results)?.name == "Marek")
        #expect(result(2, results)?.name == nil)
        #expect(result(2, results)?.suggestedName == nil)
    }

    // MARK: Names the user gave or confirmed

    @Test func aUserNameComesBackUnchanged() {
        let name = cluster(1, label: "Marek", source: .user, status: .confirmed)
        let request = [name]
        #expect(resolve(request) == resolve(request))
        // A second run with evidence for another name changes nothing either.
        let results = resolve(request, evidence: [evidence("Anna", speaker: "Marek")])
        #expect(result(1, results) == result(1, resolve(request)))
        #expect(result(1, results)?.name == "Marek")
    }

    @Test func aConfirmedNameComesBackUnchanged() {
        let confirmed = cluster(1, label: "Anna", source: .platform, status: .confirmed)
        let results = resolve([confirmed], evidence: [evidence("Marek", speaker: "Mówca 1")])
        #expect(result(1, results)?.name == "Anna")
        #expect(result(1, results)?.source == .platform)
        #expect(result(1, results)?.status == .confirmed)
    }

    @Test func theSuggestionOfAnUntouchedClusterStays() {
        let confirmed = cluster(1, label: "Anna", status: .confirmed, suggestion: "Marek")
        let results = resolve([confirmed])
        #expect(result(1, results)?.suggestedName == "Marek")
    }

    // MARK: Rejected names

    @Test func aRejectedNameDoesNotComeBackFromTheConversation() {
        let speaker = cluster(1, rejected: ["Marek"])
        let results = resolve([speaker], evidence: [evidence("Marek", speaker: "Mówca 1")])
        #expect(result(1, results)?.name == nil)
        #expect(result(1, results)?.suggestedName == nil)
    }

    @Test func aRejectedNameDoesNotComeBackFromThePlatform() {
        let speaker = cluster(1, rejected: ["Marek"])
        let results = resolve(
            [speaker],
            evidence: [
                evidence("Marek", source: .platform, kind: nil, confidence: nil, strength: 0.9)
            ])
        #expect(result(1, results)?.name == nil)
        #expect(result(1, results)?.suggestedName == nil)
    }

    @Test func aRejectedNameDoesNotComeBackAsTheOwnersName() {
        let owner = cluster(1, label: SpeakerLabels.me, channel: .mic, isSelf: true, rejected: ["Marek"])
        let results = resolve([owner], selfName: "Marek")
        #expect(result(1, results)?.name == nil)
        #expect(result(1, results)?.suggestedName == nil)
    }

    // MARK: One name per cluster, one cluster per name

    @Test func theStrongerClaimWinsTheName() {
        let first = cluster(1)
        let second = cluster(2, label: "Mówca 2")
        let results = resolve(
            [first, second],
            evidence: [
                evidence("Marek", source: .platform, kind: nil, confidence: nil, speaker: "Mówca 1", strength: 0.8),
                evidence("Marek", source: .platform, kind: nil, confidence: nil, speaker: "Mówca 2", strength: 0.5),
            ])
        #expect(result(1, results)?.name == "Marek")
        #expect(result(1, results)?.status == .applied)
        #expect(result(2, results)?.name == nil)
        #expect(result(2, results)?.suggestedName == nil)
    }

    @Test func aTieLeavesTheNameAsASuggestionAtBothClusters() {
        let first = cluster(1)
        let second = cluster(2, label: "Mówca 2")
        let results = resolve(
            [first, second],
            evidence: [
                evidence("Marek", source: .platform, kind: nil, confidence: nil, speaker: "Mówca 1", strength: 0.7),
                evidence("Marek", source: .platform, kind: nil, confidence: nil, speaker: "Mówca 2", strength: 0.7),
            ])
        for id in [1, 2] {
            #expect(result(id, results)?.name == nil)
            #expect(result(id, results)?.status == .suggested)
            #expect(result(id, results)?.suggestedName == "Marek")
        }
    }

    // MARK: Names said in the conversation

    @Test func aSureSelfIntroductionIsApplied() {
        let results = resolve([cluster(1)], evidence: [evidence("Marek")])
        #expect(result(1, results)?.name == "Marek")
        #expect(result(1, results)?.source == .transcript)
        #expect(result(1, results)?.status == .applied)
    }

    @Test func anUnsureSelfIntroductionIsSuggested() {
        let results = resolve([cluster(1)], evidence: [evidence("Marek", confidence: .low)])
        #expect(result(1, results)?.name == nil)
        #expect(result(1, results)?.suggestedName == "Marek")
        #expect(result(1, results)?.status == .suggested)
    }

    @Test func anAnnouncementOnTheKnownListIsApplied() {
        let results = resolve([cluster(1)], evidence: [evidence("Marek", kind: .announced)], known: ["Marek"])
        #expect(result(1, results)?.name == "Marek")
        #expect(result(1, results)?.status == .applied)
    }

    @Test func anAnnouncementOutsideTheKnownListIsSuggested() {
        let results = resolve([cluster(1)], evidence: [evidence("Marek", kind: .announced)], known: ["Anna"])
        #expect(result(1, results)?.name == nil)
        #expect(result(1, results)?.suggestedName == "Marek")
    }

    @Test func anAnnouncementWithoutAListIsSuggested() {
        let results = resolve([cluster(1)], evidence: [evidence("Marek", kind: .announced)])
        #expect(result(1, results)?.name == nil)
        #expect(result(1, results)?.suggestedName == "Marek")
    }

    @Test func aVocativeIsSuggested() {
        let results = resolve([cluster(1)], evidence: [evidence("Marek", kind: .addressed)], known: ["Marek"])
        #expect(result(1, results)?.name == nil)
        #expect(result(1, results)?.suggestedName == "Marek")
    }

    @Test func aSelfIntroductionOutsideTheListIsStillApplied() {
        let results = resolve([cluster(1)], evidence: [evidence("Marek")], known: ["Anna"])
        #expect(result(1, results)?.name == "Marek")
        #expect(result(1, results)?.status == .applied)
    }

    @Test func aNameOutsideTheListHasLessStrength() {
        // Two sure names for one cluster: "Marek" stands on the list and keeps 1.0, "Anna" is outside it and
        // keeps half of its strength, so the listed name wins even though "Anna" comes first alphabetically.
        let results = resolve(
            [cluster(1)],
            evidence: [evidence("Anna"), evidence("Marek", kind: .announced)],
            known: ["Marek"])
        #expect(result(1, results)?.name == "Marek")
    }

    // MARK: The owner

    @Test func theOwnersClusterGetsSelfName() {
        let owner = cluster(1, label: SpeakerLabels.me, channel: .mic, isSelf: true)
        let results = resolve([owner], selfName: "Marek")
        #expect(result(1, results)?.name == "Marek")
        #expect(result(1, results)?.source == .me)
        #expect(result(1, results)?.status == .applied)
        #expect(result(1, results)?.evidence.first?.source == .me)
    }

    @Test func withoutSelfNameTheOwnersClusterGetsNoName() {
        let owner = cluster(1, label: SpeakerLabels.me, channel: .mic, isSelf: true, source: .me)
        let results = resolve([owner])
        #expect(result(1, results)?.name == nil)
        #expect(result(1, results)?.source == .me)
    }

    @Test func aPlaceholderSelfNameIsIgnored() {
        let owner = cluster(1, label: SpeakerLabels.me, channel: .mic, isSelf: true)
        let results = resolve([owner], selfName: "Mówca 2")
        #expect(result(1, results)?.name == nil)
    }

    // MARK: The platform share

    @Test func aShareOfPointFiveNineIsSuggestedNotApplied() {
        let results = resolve([cluster(1)], evidence: [platform("Marek", share: 0.59)])
        #expect(result(1, results)?.name == nil)
        #expect(result(1, results)?.suggestedName == "Marek")
        #expect(result(1, results)?.status == .suggested)
    }

    @Test func aShareOfPointSixIsApplied() {
        let results = resolve([cluster(1)], evidence: [platform("Marek", share: 0.6)])
        #expect(result(1, results)?.name == "Marek")
        #expect(result(1, results)?.status == .applied)
    }

    @Test func aLeadOfPointOneNineIsNotEnough() {
        let results = resolve(
            [cluster(1)], evidence: [platform("Marek", share: 0.6), platform("Anna", share: 0.41)])
        #expect(result(1, results)?.name == nil)
        #expect(result(1, results)?.suggestedName == "Marek")
    }

    @Test func aLeadOfPointTwoIsEnough() {
        let results = resolve(
            [cluster(1)], evidence: [platform("Marek", share: 0.8), platform("Anna", share: 0.6)])
        #expect(result(1, results)?.name == "Marek")
        #expect(result(1, results)?.status == .applied)
    }

    @Test func aShareOfPointTwoNineIsIgnored() {
        let results = resolve([cluster(1)], evidence: [platform("Marek", share: 0.29)])
        #expect(result(1, results)?.name == nil)
        #expect(result(1, results)?.suggestedName == nil)
    }

    @Test func aShareOfPointThreeIsSuggested() {
        let results = resolve([cluster(1)], evidence: [platform("Marek", share: 0.3)])
        #expect(result(1, results)?.suggestedName == "Marek")
        #expect(result(1, results)?.name == nil)
    }

    @Test func thePlatformNamesOnlyTheSystemChannel() {
        let results = resolve(
            [cluster(1, channel: .mic)], evidence: [platform("Marek", share: 0.9, speaker: "Mówca 1")])
        #expect(result(1, results)?.name == nil)
        #expect(result(1, results)?.suggestedName == nil)
    }

    private func platform(_ name: String, share: Double, speaker: String = "Mówca 1") -> NameEvidence {
        evidence(name, source: .platform, kind: nil, confidence: nil, speaker: speaker, strength: share)
    }

    // MARK: The calendar

    @Test func theOnlyOtherAttendeeNamesTheOnlyOtherCluster() {
        let owner = cluster(1, label: SpeakerLabels.me, channel: .mic, isSelf: true)
        let other = cluster(2, label: "Mówca 1")
        let results = resolve(
            [owner, other], calendar: SpeakerNameCalendar(attendeeNames: ["Anna"], includesOwner: true))
        #expect(result(2, results)?.name == nil)
        #expect(result(2, results)?.suggestedName == "Anna")
        #expect(result(2, results)?.source == .calendar)
        #expect(result(2, results)?.status == .suggested)
    }

    @Test func theCalendarNamesNobodyWithoutTheOwnerInTheEvent() {
        let owner = cluster(1, label: SpeakerLabels.me, channel: .mic, isSelf: true)
        let other = cluster(2, label: "Mówca 1")
        let results = resolve(
            [owner, other], calendar: SpeakerNameCalendar(attendeeNames: ["Anna"], includesOwner: false))
        #expect(result(2, results)?.suggestedName == nil)
    }

    @Test func theCalendarNamesNobodyWithTwoOtherClusters() {
        let owner = cluster(1, label: SpeakerLabels.me, channel: .mic, isSelf: true)
        let first = cluster(2, label: "Mówca 1")
        let second = cluster(3, label: "Mówca 2")
        let results = resolve(
            [owner, first, second], calendar: SpeakerNameCalendar(attendeeNames: ["Anna"], includesOwner: true))
        #expect(results.allSatisfy { $0.suggestedName == nil })
        #expect(results.allSatisfy { $0.source != .calendar })
    }

    @Test func theCalendarNamesNobodyWithThreeAttendees() {
        let owner = cluster(1, label: SpeakerLabels.me, channel: .mic, isSelf: true)
        let other = cluster(2, label: "Mówca 1")
        let results = resolve(
            [owner, other],
            calendar: SpeakerNameCalendar(attendeeNames: ["Anna", "Marek", "Ewa"], includesOwner: true))
        #expect(result(2, results)?.suggestedName == nil)
    }

    @Test func theCalendarNamesNobodyWithoutAClusterOfTheOwner() {
        let other = cluster(2, label: "Mówca 1")
        let results = resolve(
            [other], calendar: SpeakerNameCalendar(attendeeNames: ["Anna"], includesOwner: true))
        #expect(result(2, results)?.suggestedName == nil)
    }

    // MARK: Placeholders and names the user typed

    @Test func aPlaceholderIsNeverAName() {
        let results = resolve([cluster(1)], evidence: [evidence("Speaker 2")])
        #expect(result(1, results)?.name == nil)
        #expect(result(1, results)?.suggestedName == nil)
    }

    @Test func twoUserClustersMayShareAName() {
        let first = cluster(1, label: "Marek", source: .user, status: .confirmed)
        let second = cluster(2, label: "Marek", source: .user, status: .confirmed)
        let results = resolve([first, second])
        #expect(result(1, results)?.name == "Marek")
        #expect(result(2, results)?.name == "Marek")
    }

    // MARK: Matching evidence to a cluster

    @Test func theSegmentMapPicksTheCluster() {
        let first = cluster(1, label: "Mówca 1")
        let second = cluster(2, label: "Mówca 1")
        let results = resolve(
            [first, second],
            evidence: [evidence("Marek", speaker: "Mówca 1", segment: 5)], segments: [5: 2])
        #expect(result(1, results)?.name == nil)
        #expect(result(2, results)?.name == "Marek")
    }

    @Test func evidenceWithoutASegmentMatchesAnUniqueLabel() {
        let results = resolve([cluster(1)], evidence: [evidence("Marek", speaker: "Mówca 1")])
        #expect(result(1, results)?.name == "Marek")
    }

    @Test func anAmbiguousLabelDropsTheEvidence() {
        let first = cluster(1, label: "Mówca 1")
        let second = cluster(2, label: "Mówca 1")
        let results = resolve([first, second], evidence: [evidence("Marek", speaker: "Mówca 1")])
        #expect(results.allSatisfy { $0.name == nil })
    }

    @Test func anUnknownSegmentDropsTheEvidence() {
        let results = resolve(
            [cluster(1)], evidence: [evidence("Marek", speaker: "Mówca 1", segment: 4)], segments: [5: 1])
        #expect(result(1, results)?.name == nil)
    }

    // MARK: The meeting's mode

    @Test func channelsModeChangesNothing() {
        let owner = cluster(1, label: SpeakerLabels.me, channel: .mic, isSelf: true)
        let others = cluster(2, label: SpeakerLabels.others)
        let results = resolve(
            [owner, others], selfName: "Marek",
            evidence: [
                evidence("Anna", speaker: SpeakerLabels.me),
                platform("Anna", share: 0.9, speaker: SpeakerLabels.others),
            ],
            mode: .channels)
        #expect(result(1, results)?.name == nil)
        #expect(result(1, results)?.source == .default)
        #expect(result(2, results)?.name == nil)
        #expect(result(2, results)?.suggestedName == nil)
    }

    @Test func noneModeChangesNothing() {
        // No speakers at all in that mode: evidence has no cluster to name.
        let results = resolve([cluster(1)], evidence: [evidence("Marek")], mode: .none)
        #expect(result(1, results)?.name == nil)
        #expect(result(1, results)?.suggestedName == nil)
    }

    @Test func repeatedClusterIdsAssignNothing() {
        let first = cluster(1)
        let second = cluster(1, label: "Mówca 2")
        let results = resolve(
            [first, second],
            evidence: [
                evidence("Marek", speaker: "Mówca 1"),
                evidence("Anna", speaker: "Mówca 2"),
            ])
        #expect(results.allSatisfy { $0.name == nil })
    }
}

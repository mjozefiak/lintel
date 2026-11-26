import Foundation

/// The store calls one name refresh makes. `MeetingsStore` is the only real one; the seam exists so a test can make
/// one read fail (a failing read must abort the write, and the real store cannot be made to fail on one read only).
protocol SpeakerNameStore: Sendable {
    func loadDocument(id: Int64, includingTrashed: Bool) throws -> MeetingDocument?
    func speakerNameStates(meetingID: Int64) throws -> [MeetingsStore.SpeakerNameState]
    func nameEvidence(meetingID: Int64) throws -> [MeetingsStore.StoredNameEvidence]
    @discardableResult
    func saveSpeakerNames(
        _ updates: [MeetingsStore.SpeakerNameUpdate], evidence: [MeetingsStore.StoredNameEvidence], meetingID: Int64
    ) throws -> Set<Int64>
}

extension MeetingsStore: SpeakerNameStore {}

/// The speakers' names of one meeting, between the store and the pure name layer (spec
/// `2026-11-25-meeting-speaker-names`, step 1.4b). Reads the speakers and the transcript, runs `SpeakerNamePass` when
/// one is given, resolves with `SpeakerNameResolver` and writes the result through `saveSpeakerNames`, whose SQL
/// guard never overwrites a name the user gave or confirmed, the owner's own speaker or a value of a newer build.
///
/// Where it runs (F1): at the start of a notes job (`NotesService`), before the notes' transcript is built and
/// before `beginNotes`, with the job's own writer. So the first notes already carry the `applied` names as speaker
/// labels, a "Regenerate" asks again, and with notes off no model is loaded for names. The finalizer keeps the
/// place for the sources that exist only at the end of a recording (platform, calendar: F2, F3).
///
/// The model may read for a minute, and the user may rename, confirm, refuse or merge speakers meanwhile. So the
/// pass gets the transcript of the moment it starts, and the resolution is made on the meeting as it is after the
/// pass: the speakers and their names are read again, the pass's evidence is mapped onto the fresh transcript by
/// its segments, and only then is anything written. A read that fails writes nothing.
///
/// - Only a `diarized` meeting is named: `channels` speakers are tracks ("Ja", "Inni"), `none` has none.
/// - An `applied` name becomes the speaker's `label`, which the transcript and the notes read. A `suggested` name
///   stays in `suggested_name` and the label is the default one ("Mówca N"), so the notes never see it.
/// - The owner's speaker is never written: `NotesUtterance.make(from:selfName:)` already shows `selfName` for its
///   "Ja", and the resolver only reserves that name so no other speaker can take it.
/// - A pass that failed (an error, the time limit, a cancellation) writes nothing: the names the meeting had stay.
///   A pass that answered resolves again from what it found, so a name the conversation no longer supports goes
///   back to the default label. A resolve without an answered pass (the switch off, no excerpt, no pass at all)
///   knows nothing new about the conversation: the names it gave earlier (`transcript`, applied or suggested) and
///   their evidence stay as they are (orchestrator decision 2026-11-26).
///
/// Nothing here logs; `Report` holds counts and closed codes only (for `NotesTrace`).
enum MeetingSpeakerNames {
    /// What one refresh did, as counts. No name, quote or label.
    struct Report: Equatable, Sendable {
        /// Why nothing was written, as a closed code (for the log line, no text).
        enum WriteFailure: String, Equatable, Sendable {
            /// The meeting or its speakers could not be read again after the pass.
            case stateRead
            /// The stored evidence could not be read: the write would delete what it could not see.
            case evidenceRead
            /// The store refused the write.
            case save
        }

        var pass = SpeakerNamePass.Outcome()
        /// The speakers of the meeting.
        var speakers = 0
        /// Whether the result was written (false: not diarized, a failed pass, a store error).
        var written = false
        /// Why nothing was written, when a store step failed.
        var writeFailure: WriteFailure?
        /// Names shown as labels, per source (`NameSource.rawValue`).
        var applied: [String: Int] = [:]
        /// Names waiting as "Marek?", per source.
        var suggested: [String: Int] = [:]

        var trace: NotesTraceSpeakerNames {
            NotesTraceSpeakerNames(
                passStatus: pass.status, elapsedMs: pass.elapsedMs, excerpts: pass.excerpts,
                droppedExcerpts: pass.droppedExcerpts, answers: pass.answers,
                rejections: Dictionary(
                    uniqueKeysWithValues: pass.rejections.map { ($0.key.rawValue, $0.value) }),
                acceptedEvidence: pass.accepted.count, speakers: speakers, written: written, applied: applied,
                suggested: suggested)
        }
    }

    /// Resolves and writes the names of `document`'s meeting. `pass` is the conversation source; `nil` runs only the
    /// sources without a model. Returns `nil` when the meeting is not diarized (nothing is read or written then).
    @concurrent
    static func refresh(
        store: any SpeakerNameStore, document: MeetingDocument, selfName: String, pass: SpeakerNamePass?,
        conditions: SpeakerNamePass.Conditions
    ) async -> Report? {
        guard document.speakerMode == .diarized, !document.speakers.isEmpty else { return nil }
        var report = Report(speakers: document.speakers.count)
        guard let pass else {
            guard let snapshot = Snapshot(store: store, meetingID: document.id) else {
                report.writeFailure = .stateRead
                return report
            }
            report.speakers = snapshot.document.speakers.count
            return resolveAndWrite(
                store: store, snapshot: snapshot, evidence: [], selfName: selfName,
                conversationAnswered: false, report: report)
        }

        // The transcript the model reads carries the default numbered labels ("Mówca N"), never a name a run or
        // the user gave: the prompt says a label is never a name, and a name in a label would make the answer
        // ambiguous. The answer's labels are mapped back to speakers after the pass, by segment.
        let before = Snapshot(document: document)
        report.pass = await pass.run(segments: before.passSegments, conditions: conditions)
        // No answer says nothing about the transcript: the names the meeting had stay.
        guard report.pass.status != .failed, !Task.isCancelled else { return report }

        // The meeting as it is now: the user may have renamed, confirmed, refused or merged speakers while the
        // model was reading. The resolution below is made on this state, never on the snapshot from before.
        guard let snapshot = Snapshot(store: store, meetingID: document.id) else {
            report.writeFailure = .stateRead
            return report
        }
        report.speakers = snapshot.document.speakers.count
        let evidence = snapshot.remapping(report.pass.accepted, from: before)
        return resolveAndWrite(
            store: store, snapshot: snapshot, evidence: evidence, selfName: selfName,
            conversationAnswered: report.pass.status == .answered, report: report)
    }

    /// Resolves `snapshot`'s speakers and writes the result. `evidence` is already mapped onto `snapshot`'s
    /// transcript. A read that fails before the write leaves everything as it was: the stored evidence is only
    /// replaced by `saveSpeakerNames` after it was read.
    private static func resolveAndWrite(
        store: any SpeakerNameStore, snapshot: Snapshot, evidence: [NameEvidence], selfName: String,
        conversationAnswered: Bool, report initial: Report
    ) -> Report {
        var report = initial
        let byID = snapshot.statesByID
        let clusters = snapshot.document.speakers.map { cluster(for: $0, state: byID[$0.id]) }
        // Without an answer the conversation's own names are not this run's to change.
        let writable = Set(
            snapshot.document.speakers.filter { speaker in
                guard let state = byID[speaker.id], isWritable(state) else { return false }
                return conversationAnswered || state.source != .transcript
            }.map(\.id))
        let resolutions = SpeakerNameResolver.resolve(
            SpeakerNameRequest(
                mode: .diarized, clusters: clusters, selfName: selfName, evidence: evidence,
                segmentClusters: snapshot.segmentClusters))

        // The labels of the speakers left without a name, in the order `SpeakerAssigner` numbers them.
        let defaults = defaultLabels(
            for: snapshot.document,
            reverting: Set(
                resolutions.filter { $0.status != .applied || $0.name == nil }.map { Int64($0.cluster) }
                    .filter(writable.contains)))

        var updates: [MeetingsStore.SpeakerNameUpdate] = []
        var fresh: [MeetingsStore.StoredNameEvidence] = []
        for resolution in resolutions {
            let speakerID = Int64(resolution.cluster)
            guard writable.contains(speakerID) else { continue }
            let label = snapshot.labels[speakerID] ?? ""
            if resolution.status == .applied, let name = resolution.name {
                updates.append(
                    .init(
                        speakerID: speakerID, label: name, source: resolution.source, status: .applied,
                        suggestedName: nil))
                report.applied[resolution.source.rawValue, default: 0] += 1
            } else if let suggestion = resolution.suggestedName {
                updates.append(
                    .init(
                        speakerID: speakerID, label: defaults[speakerID] ?? label, source: resolution.source,
                        status: .suggested, suggestedName: suggestion))
                report.suggested[resolution.source.rawValue, default: 0] += 1
            } else {
                // No name: the default label, the state a fresh speaker has.
                updates.append(
                    .init(
                        speakerID: speakerID, label: defaults[speakerID] ?? label, source: .default,
                        status: .confirmed, suggestedName: nil))
            }
            for item in resolution.evidence where item.source != .me {
                fresh.append(
                    .init(
                        speakerID: speakerID, source: item.source, name: item.name, kind: item.kind,
                        segmentID: item.segment.flatMap { snapshot.segmentIDs[$0] }, startMs: item.startMs,
                        endMs: item.endMs, strength: item.strength))
            }
        }

        // `saveSpeakerNames` replaces the meeting's evidence: the rows of the speakers this run does not write (a
        // name the user confirmed keeps where it came from) stay, pointed again at their speaker by their segment
        // when a new speaker plan left them without one. A read error aborts the write — the save would delete the
        // evidence it could not see — and the notes go on with the names the meeting had.
        let kept: [MeetingsStore.StoredNameEvidence]
        do {
            kept = try store.nameEvidence(meetingID: snapshot.document.id).compactMap {
                stored -> MeetingsStore.StoredNameEvidence? in
                guard stored.source != .me,
                    let speaker = stored.speakerID ?? stored.segmentID.flatMap({ snapshot.segmentSpeakers[$0] }),
                    byID[speaker] != nil, !writable.contains(speaker)
                else { return nil }
                var item = stored
                item.speakerID = speaker
                return item
            }
        } catch {
            report.writeFailure = .evidenceRead
            return report
        }
        do {
            try store.saveSpeakerNames(updates, evidence: kept + fresh, meetingID: snapshot.document.id)
            report.written = true
        } catch {
            report.writeFailure = .save
        }
        return report
    }

    // MARK: Store rows and clusters

    /// The cluster the resolver sees for a stored speaker. The store's "no name" state (`default`, `confirmed`: the
    /// column default, and what "To nie Marek" leaves) is not a confirmed name, so it goes in as `suggested`. The
    /// owner's speaker still called "Ja" goes in unprotected, so the resolver reserves `selfName` for it (it is
    /// never written). A value of a newer build goes in as the user's: untouched, and its name reserved.
    static func cluster(for speaker: MeetingDocument.Speaker, state: MeetingsStore.SpeakerNameState?)
        -> SpeakerNameCluster
    {
        var cluster = SpeakerNameCluster(
            id: Int(speaker.id), channel: speaker.channel, isSelf: speaker.isSelf, label: speaker.label,
            source: .user, status: .confirmed, rejectedNames: state?.rejectedNames ?? [],
            suggestedName: state?.suggestedName)
        guard let state, let source = state.source, let status = state.status else { return cluster }
        if speaker.isSelf {
            let generic = NotesGuard.isGenericLabel(speaker.label)
            (cluster.source, cluster.status) = generic ? (.me, .suggested) : (.user, .confirmed)
            return cluster
        }
        switch source {
        case .default: (cluster.source, cluster.status) = (.default, .suggested)
        case .user, .me: (cluster.source, cluster.status) = (.user, .confirmed)
        case .platform, .calendar, .transcript: (cluster.source, cluster.status) = (source, status)
        }
        return cluster
    }

    /// The same test as the store's SQL guard (`MeetingsStore.overwritableSpeakerNameSQL`), so the run never asks
    /// the store to write a row it refuses.
    static func isWritable(_ state: MeetingsStore.SpeakerNameState) -> Bool {
        guard !state.isSelf, let source = state.source, let status = state.status else { return false }
        switch source {
        case .default: return true
        case .platform, .calendar, .transcript: return status == .applied || status == .suggested
        case .user, .me: return false
        }
    }

    /// The default label ("Mówca N") of each speaker in `reverting`. A label that is still a placeholder stays as it
    /// is. A speaker whose label was an automatic name gets its number back as `SpeakerAssigner` gives it: the order
    /// of first appearance among the speakers other than the owner's; when another speaker already shows that
    /// label, the lowest free number.
    static func defaultLabels(for document: MeetingDocument, reverting: Set<Int64>) -> [Int64: String] {
        var first: [Int64: Int] = [:]
        for segment in document.segments {
            guard let speaker = segment.speakerID else { continue }
            first[speaker] = min(first[speaker] ?? .max, segment.startMs)
        }
        let others = document.speakers.filter { !$0.isSelf }.sorted {
            (first[$0.id] ?? .max, $0.id) < (first[$1.id] ?? .max, $1.id)
        }
        var result: [Int64: String] = [:]
        var renumber: [(speaker: Int64, rank: Int)] = []
        for (index, speaker) in others.enumerated() where reverting.contains(speaker.id) {
            if NotesGuard.isGenericLabel(speaker.label) {
                result[speaker.id] = speaker.label
            } else {
                renumber.append((speaker.id, index + 1))
            }
        }
        guard !renumber.isEmpty else { return result }
        let renumbered = Set(renumber.map(\.speaker))
        var used = Set(document.speakers.filter { !renumbered.contains($0.id) }.map(\.label))
        for (speaker, rank) in renumber {
            var label = SpeakerLabels.numbered(rank)
            if used.contains(label) {
                var number = 1
                while used.contains(SpeakerLabels.numbered(number)) { number += 1 }
                label = SpeakerLabels.numbered(number)
            }
            used.insert(label)
            result[speaker] = label
        }
        return result
    }

    /// The label the name pass reads for each speaker: the default numbered label by the speaker's place among the
    /// speakers other than the owner's (`SpeakerAssigner`'s order), never a name. The owner's speaker keeps its
    /// stored label, as the notes always show it ("Ja", never `selfName`).
    static func passLabels(for document: MeetingDocument) -> [Int: String] {
        var first: [Int64: Int] = [:]
        for segment in document.segments {
            guard let speaker = segment.speakerID else { continue }
            first[speaker] = min(first[speaker] ?? .max, segment.startMs)
        }
        let others = document.speakers.filter { !$0.isSelf }.sorted {
            (first[$0.id] ?? .max, $0.id) < (first[$1.id] ?? .max, $1.id)
        }
        var result: [Int: String] = [:]
        for (index, speaker) in others.enumerated() {
            result[Int(speaker.id)] = SpeakerLabels.numbered(index + 1)
        }
        for speaker in document.speakers where speaker.isSelf {
            result[Int(speaker.id)] = speaker.label
        }
        return result
    }
}

// MARK: - One meeting's speakers and transcript

extension MeetingSpeakerNames {
    /// One meeting as a refresh sees it: the speakers with their stored names, the transcript in time order with
    /// the clusters its segments belong to, and the labels the pass reads. Built from a document (the transcript the
    /// pass gets) or from the store (the state the resolution is made on).
    fileprivate struct Snapshot {
        let document: MeetingDocument
        let statesByID: [Int64: MeetingsStore.SpeakerNameState]
        /// The transcript in time order; the pass's evidence indexes these.
        let ordered: [MeetingDocument.Segment]
        /// The transcript index of each segment id.
        let indexBySegmentID: [Int64: Int]
        /// The transcript index of each segment id, the way `NameEvidence` refers to it.
        let segmentIDs: [Int: Int64]
        /// The speaker of each transcript segment, by the evidence's index.
        let segmentClusters: [Int: Int]
        /// The stored label of each speaker.
        let labels: [Int64: String]
        /// The label the pass reads for each speaker (`passLabels(for:)`).
        let numbered: [Int: String]
        /// The speaker of each segment id, for the evidence rows that lost their speaker.
        let segmentSpeakers: [Int64: Int64]

        init(document: MeetingDocument, states: [MeetingsStore.SpeakerNameState] = []) {
            self.document = document
            statesByID = Dictionary(states.map { ($0.speakerID, $0) }, uniquingKeysWith: { first, _ in first })
            let ordered = document.segments.sorted { ($0.startMs, $0.id) < ($1.startMs, $1.id) }
            self.ordered = ordered
            var indexBySegmentID: [Int64: Int] = [:]
            var segmentIDs: [Int: Int64] = [:]
            var segmentClusters: [Int: Int] = [:]
            var segmentSpeakers: [Int64: Int64] = [:]
            for (index, segment) in ordered.enumerated() {
                indexBySegmentID[segment.id] = index
                segmentIDs[index] = segment.id
                if let speaker = segment.speakerID {
                    segmentClusters[index] = Int(speaker)
                    segmentSpeakers[segment.id] = speaker
                }
            }
            self.indexBySegmentID = indexBySegmentID
            self.segmentIDs = segmentIDs
            self.segmentClusters = segmentClusters
            self.segmentSpeakers = segmentSpeakers
            labels = Dictionary(document.speakers.map { ($0.id, $0.label) }, uniquingKeysWith: { first, _ in first })
            numbered = MeetingSpeakerNames.passLabels(for: document)
        }

        /// The meeting and its speakers as the store holds them now; `nil` when the meeting is gone (deleted or
        /// trashed) or the rows cannot be read — nothing is written then.
        init?(store: any SpeakerNameStore, meetingID: Int64) {
            guard let document = try? store.loadDocument(id: meetingID, includingTrashed: false),
                !document.speakers.isEmpty
            else { return nil }
            guard let states = try? store.speakerNameStates(meetingID: meetingID) else { return nil }
            self.init(document: document, states: states)
        }

        /// The transcript the name pass reads: the default numbered labels, never a name the user or an earlier run
        /// gave. The owner's speaker keeps its stored label.
        var passSegments: [NameSegment] {
            ordered.enumerated().map { index, segment in
                let label = segment.speakerID.flatMap { numbered[Int($0)] } ?? "?"
                return NameSegment(
                    speaker: label, startMs: segment.startMs, endMs: segment.endMs, text: segment.text)
            }
        }

        /// The pass's evidence, pointed at this snapshot's transcript. A quote is followed by its segment: after a
        /// merge the segment belongs to another speaker and the evidence follows it. A vocative or an announcement
        /// names the speaker of the segment right after the quote, followed by that segment too. Evidence whose
        /// segment is gone is dropped.
        func remapping(_ evidence: [NameEvidence], from before: Snapshot) -> [NameEvidence] {
            evidence.compactMap { item in
                var item = item
                guard let oldIndex = item.segment else {
                    // Evidence without a quote (another source than the conversation) is followed by its label.
                    if let speaker = item.speaker.flatMap({ before.speakerID(forPassLabel: $0) }),
                        let label = labels[speaker]
                    {
                        item.speaker = label
                    }
                    return item
                }
                guard let segmentID = before.segmentIDs[oldIndex], let index = indexBySegmentID[segmentID] else {
                    return nil
                }
                item.segment = index
                if item.kind == .addressed || item.kind == .announced {
                    guard let answerIndex = before.answeringIndex(after: oldIndex, label: item.speaker),
                        let answerID = before.segmentIDs[answerIndex],
                        let newAnswerIndex = indexBySegmentID[answerID],
                        let cluster = segmentClusters[newAnswerIndex], let label = labels[Int64(cluster)]
                    else { return nil }
                    item.speaker = label
                } else {
                    guard let cluster = segmentClusters[index], let label = labels[Int64(cluster)] else {
                        return nil
                    }
                    item.speaker = label
                }
                return item
            }
        }

        /// The speaker the pass knew under `label` (the numbered labels are unique among the speakers).
        func speakerID(forPassLabel label: String) -> Int64? {
            for (speaker, passLabel) in numbered where passLabel == label {
                return Int64(speaker)
            }
            return nil
        }

        /// The first segment after `index` whose cluster carries the pass label `label` (the rule
        /// `SpeakerNameResolver` applies to a vocative and an announcement).
        func answeringIndex(after index: Int, label: String?) -> Int? {
            guard let label, index + 1 < ordered.count else { return nil }
            for next in (index + 1)..<ordered.count {
                guard let cluster = segmentClusters[next], numbered[cluster] == label else { continue }
                return next
            }
            return nil
        }
    }
}

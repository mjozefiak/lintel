import Foundation

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
/// - Only a `diarized` meeting is named: `channels` speakers are tracks ("Ja", "Inni"), `none` has none.
/// - An `applied` name becomes the speaker's `label`, which the transcript and the notes read. A `suggested` name
///   stays in `suggested_name` and the label is the default one ("Mówca N"), so the notes never see it.
/// - The owner's speaker is never written: `NotesUtterance.make(from:selfName:)` already shows `selfName` for its
///   "Ja", and the resolver only reserves that name so no other speaker can take it.
/// - A pass that failed (an error, the time limit, a cancellation) writes nothing: the names the meeting had stay.
///   A pass that answered, found no excerpt or was not allowed to ask resolves again from what it found, so names
///   that no longer have evidence (a changed transcript, the switch turned off) go back to the default label.
///
/// Nothing here logs; `Report` holds counts only (for `NotesTrace`).
enum MeetingSpeakerNames {
    /// What one refresh did, as counts. No name, quote or label.
    struct Report: Equatable, Sendable {
        var pass = SpeakerNamePass.Outcome()
        /// The speakers of the meeting.
        var speakers = 0
        /// Whether the result was written (false: not diarized, a failed pass, a store error).
        var written = false
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
        store: MeetingsStore, document: MeetingDocument, selfName: String, pass: SpeakerNamePass?,
        conditions: SpeakerNamePass.Conditions
    ) async -> Report? {
        guard document.speakerMode == .diarized, !document.speakers.isEmpty else { return nil }
        guard let states = try? store.speakerNameStates(meetingID: document.id) else { return nil }
        let byID = Dictionary(states.map { ($0.speakerID, $0) }, uniquingKeysWith: { first, _ in first })
        var report = Report(speakers: document.speakers.count)

        // The transcript in time order; the evidence of the pass points at these indexes.
        let ordered = document.segments.sorted { ($0.startMs, $0.id) < ($1.startMs, $1.id) }
        let labels = Dictionary(document.speakers.map { ($0.id, $0.label) }, uniquingKeysWith: { first, _ in first })
        var segmentClusters: [Int: Int] = [:]
        var segmentIDs: [Int: Int64] = [:]
        let segments = ordered.enumerated().map { index, segment -> NameSegment in
            segmentIDs[index] = segment.id
            if let speaker = segment.speakerID { segmentClusters[index] = Int(speaker) }
            // The stored label, without the `selfName` swap: the owner's name is never sent for names.
            let label = segment.speakerID.flatMap { labels[$0] } ?? "?"
            return NameSegment(speaker: label, startMs: segment.startMs, endMs: segment.endMs, text: segment.text)
        }

        if let pass {
            report.pass = await pass.run(segments: segments, conditions: conditions)
            // No answer says nothing about the transcript: the names the meeting had stay.
            guard report.pass.status != .failed, !Task.isCancelled else { return report }
        }

        let clusters = document.speakers.map { speaker in cluster(for: speaker, state: byID[speaker.id]) }
        let writable = Set(
            document.speakers.filter { speaker in byID[speaker.id].map(isWritable) ?? false }.map(\.id))
        let resolutions = SpeakerNameResolver.resolve(
            SpeakerNameRequest(
                mode: .diarized, clusters: clusters, selfName: selfName, evidence: report.pass.accepted,
                segmentClusters: segmentClusters))

        // The labels of the speakers left without a name, in the order `SpeakerAssigner` numbers them.
        let defaults = defaultLabels(
            for: document,
            reverting: Set(
                resolutions.filter { $0.status != .applied || $0.name == nil }.map { Int64($0.cluster) }
                    .filter(writable.contains)))

        var updates: [MeetingsStore.SpeakerNameUpdate] = []
        var evidence: [MeetingsStore.StoredNameEvidence] = []
        for resolution in resolutions {
            let speakerID = Int64(resolution.cluster)
            guard writable.contains(speakerID) else { continue }
            let label = byID[speakerID]?.label ?? ""
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
                evidence.append(
                    .init(
                        speakerID: speakerID, source: item.source, name: item.name, kind: item.kind,
                        segmentID: item.segment.flatMap { segmentIDs[$0] }, startMs: item.startMs,
                        endMs: item.endMs, strength: item.strength))
            }
        }

        // `saveSpeakerNames` replaces the meeting's evidence: the rows of the speakers this run does not write (a
        // name the user confirmed keeps where it came from) stay, pointed again at their speaker by their segment
        // when a new speaker plan left them without one.
        let segmentSpeakers = Dictionary(
            document.segments.compactMap { segment in segment.speakerID.map { (segment.id, $0) } },
            uniquingKeysWith: { first, _ in first })
        let kept = ((try? store.nameEvidence(meetingID: document.id)) ?? []).compactMap {
            stored -> MeetingsStore.StoredNameEvidence? in
            guard stored.source != .me,
                let speaker = stored.speakerID ?? stored.segmentID.flatMap({ segmentSpeakers[$0] }),
                byID[speaker] != nil, !writable.contains(speaker)
            else { return nil }
            var item = stored
            item.speakerID = speaker
            return item
        }
        do {
            try store.saveSpeakerNames(updates, evidence: kept + evidence, meetingID: document.id)
            report.written = true
        } catch {
            report.written = false
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
}

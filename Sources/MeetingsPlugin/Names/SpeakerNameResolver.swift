import Foundation
import LintelCore

/// One speaker cluster of a meeting, as `SpeakerNameResolver` sees it: the diarization result plus the name the
/// meeting already holds for it (spec `2026-11-25-meeting-speaker-names`, Data Model → `meeting_speaker`). Pure:
/// the id is the caller's (`meeting_speaker.id` at finalization, or the speaker's index in the plan) and the
/// resolver only echoes it — after "Zostaw osobno" two clusters may share a label, so the label alone never
/// identifies a cluster.
struct SpeakerNameCluster: Equatable, Sendable {
    var id: Int
    var channel: AudioChannel
    var isSelf: Bool
    /// `meeting_speaker.label`: "Mówca N", "Ja", "Inni" or a name the user typed.
    var label: String
    var source: NameSource
    var status: SpeakerNameStatus
    /// Names the user rejected for this cluster ("To nie Marek"): none of them ever comes back, neither as a name
    /// nor as a suggestion (spec: Proposed Solution 4).
    var rejectedNames: [String] = []
    /// The suggestion already shown for this cluster; kept untouched only on a cluster the resolver does not
    /// touch.
    var suggestedName: String?
}

/// The calendar event as the calendar source gives it (spec: Architecture → `CalendarAttendees`, phase F3): the
/// attendees' names without the owner and whether the owner is one of them. The resolver only uses the event in
/// the one case the spec allows: a meeting with the owner and exactly one other person.
struct SpeakerNameCalendar: Equatable, Sendable {
    /// The event's attendees other than the owner (`EKParticipant.name`, never e-mail addresses).
    var attendeeNames: [String]
    /// Whether the owner is one of the event's participants (`EKParticipant.isCurrentUser`).
    var includesOwner: Bool
}

/// Everything `SpeakerNameResolver` needs for one meeting. Pure and without I/O: the caller reads the clusters
/// from `meeting_speaker`, the evidence from `meeting_name_evidence` and the sources, and writes the result back.
struct SpeakerNameRequest: Equatable, Sendable {
    /// `meeting.speaker_mode`: names are resolved only for a diarized meeting. In `channels` mode the clusters are
    /// tracks ("Ja", "Inni"), not people, so nothing is assigned; `none` has no speakers.
    var mode: SpeakerMode
    var clusters: [SpeakerNameCluster]
    /// `plugins.meetings.selfName`; empty when the user has not set it.
    var selfName: String = ""
    /// Evidence from every source that ran; `.me`, `.user` and `.default` rows are ignored (the first is
    /// structural, the other two describe clusters, not evidence).
    var evidence: [NameEvidence] = []
    /// The names the meeting app's participant list and the calendar event hold; empty when neither ran. A
    /// transcript name that matches one of them is trusted more (spec: Proposed Solution 2); the list itself never
    /// leaves the Mac for the model.
    var knownNames: [String] = []
    var calendar: SpeakerNameCalendar?
    /// The cluster of every transcript segment, by the index the transcript evidence refers to
    /// (`NameEvidence.segment`, where the quote starts; a vocative or an announcement names the cluster of the
    /// first later segment with its label). Evidence without a segment is matched by its cluster label, and only
    /// when exactly one cluster has that label.
    var segmentClusters: [Int: Int] = [:]
}

/// What the resolver decided for one cluster. `name` is the name to show and store in `label`; a `suggested`
/// result keeps the label ("Mówca N") and puts the name in `suggestedName` ("Marek?"), see spec: Proposed
/// Solution 3.
struct SpeakerNameResolution: Equatable, Sendable {
    /// The cluster's own id (`SpeakerNameCluster.id`), echoed.
    var cluster: Int
    var name: String?
    var source: NameSource
    var status: SpeakerNameStatus
    var suggestedName: String?
    /// The evidence the result rests on, for `meeting_name_evidence` (spec: Data Model: only used evidence is
    /// stored). Empty for a cluster the resolver keeps as it was.
    var evidence: [NameEvidence]
}

/// Picks at most one name per speaker cluster and gives each name to at most one cluster (spec
/// `2026-11-25-meeting-speaker-names`, Proposed Solution 2 and Architecture → `SpeakerNameResolver`). Pure.
///
/// Rules, in the order they are applied:
/// - A cluster the user named (`source == .user`) or confirmed (`status == .confirmed`) is untouchable: it comes
///   back exactly as it went in, on every resolution. Its name also cannot be given to another cluster by an
///   automatic source.
/// - The owner's cluster (`isSelf`, microphone channel) gets `selfName` as `applied` when it is set and not a
///   placeholder — how today's finalizer names it. Without `selfName` the cluster keeps no name.
/// - Automatic sources run only in `diarized` mode and only for the other clusters. One cluster takes the surest
///   candidate first (`applied` beats `suggested`), and among candidates of one state the source with the highest
///   priority: `platform` > `transcript` > `calendar` (orchestrator decision 2026-11-26).
/// - A name the user rejected for a cluster never comes back for that cluster, from any source, neither as a name
///   nor as a suggestion.
/// - Transcript: a self-introduction the model is sure of (`introduction`, `high`) is `applied`, unless the same
///   cluster introduces itself with another name too (then each is only `suggested`); an announcement
///   (`announced`, `high`) is `applied` only when the name stands on the known name list, else `suggested`;
///   everything else (`addressed`, `low`, a name outside a non-empty list) is `suggested`. A name outside a
///   non-empty list carries a smaller strength.
/// - Platform: only the system channel. The best name's share of the cluster's speaking time decides — `applied`
///   at `platformAppliedCoverage` with `platformAppliedLead` over the second name, `suggested` at
///   `platformSuggestedCoverage`, nothing below.
/// - Calendar: never assigns a name, with one exception: a meeting with the owner and exactly one other attendee,
///   in which the owner has exactly one cluster besides their own. The name is `suggested`: the spec lists
///   `applied` only for `self`, a clear platform share, a self-introduction and an announcement confirmed by the
///   list.
/// - One to one, greedily by strength over the chosen candidates: two clusters claiming one name give it to the
///   stronger one; on a tie neither gets the name and both show it as a suggestion (the conflict state of the
///   UI/UX spec).
/// - A placeholder (`NotesGuard.isGenericLabel`: "Speaker 2", "Mówca 1", "Ja") is never a name or a suggestion.
///
/// Every threshold below is a constant of the code, tuned on the development recordings only: the transcript
/// strengths in step 1.5, the platform coverage in step 2.3 (spec: Architecture → `SpeakerNameResolver`).
enum SpeakerNameResolver {
    /// The platform share of a cluster's speaking time from which the best name is `applied`.
    static let platformAppliedCoverage = 0.6
    /// How far the best platform name must stand over the second one to be `applied`.
    static let platformAppliedLead = 0.2
    /// The platform share from which the best name is `suggested`.
    static let platformSuggestedCoverage = 0.3
    /// What a transcript name outside a non-empty known name list keeps of its strength.
    static let offListStrengthFactor = 0.5
    /// What the calendar exception's name is worth in the greedy assignment; it is never `applied`, so it only
    /// matters against another suggestion for the same name.
    static let calendarStrength = 0.5
    /// Two strengths closer than this are a tie (a conflict for one name). Floating-point arithmetic on the
    /// strengths (a share minus a share, a multiplied confidence) must not turn an exact tie into a win.
    static let strengthTieEpsilon = 1e-9

    static func resolve(_ request: SpeakerNameRequest) -> [SpeakerNameResolution] {
        // In `channels` mode the clusters are tracks ("Ja" / "Inni"), not people; `none` has no speakers at all,
        // so both come back exactly as they went in.
        guard request.mode == .diarized, !request.clusters.isEmpty else {
            return request.clusters.map { untouched($0) }
        }
        var results = request.clusters.map { isProtected($0) ? untouched($0) : emptyState($0) }
        guard let indexes = clusterIndexes(of: request.clusters) else { return results }

        var decided: Set<Int> = []
        var reserved: [String] = []
        for cluster in request.clusters where isProtected(cluster) {
            decided.insert(cluster.id)
            if let name = cleanedName(cluster.label) { reserved.append(name) }
        }

        // Self: the owner's cluster gets `selfName`, as today's finalizer names it.
        let selfName = cleanedName(request.selfName)
        for cluster in request.clusters
        where !decided.contains(cluster.id) && cluster.isSelf && cluster.channel == .mic {
            guard let name = selfName, !isRejected(name, by: cluster) else { continue }
            guard let index = indexes[cluster.id] else { continue }
            results[index] = SpeakerNameResolution(
                cluster: cluster.id, name: name, source: .me, status: .applied, suggestedName: nil,
                evidence: [
                    NameEvidence(
                        source: .me, name: name, speaker: cluster.label, kind: nil, segment: nil, startMs: nil,
                        endMs: nil, strength: 1, confidence: nil)
                ])
            decided.insert(cluster.id)
            reserved.append(name)
        }

        var candidates: [Int: [Candidate]] = [:]

        // A cluster that introduces itself with two different names contradicts itself (step 1.5: a greeting of
        // several guests read as introductions): none of those introductions is sure enough to apply.
        var introduced: [Int: [String]] = [:]
        for evidence in request.evidence where evidence.source == .transcript && evidence.kind == .introduction {
            guard let cluster = cluster(for: evidence, in: request, indexes: indexes),
                let name = cleanedName(evidence.name)
            else { continue }
            var names = introduced[cluster.id, default: []]
            if !names.contains(where: { samePerson($0, name) }) { names.append(name) }
            introduced[cluster.id] = names
        }

        // Transcript: names said in the conversation.
        for evidence in request.evidence where evidence.source == .transcript {
            guard let cluster = cluster(for: evidence, in: request, indexes: indexes),
                !decided.contains(cluster.id),
                let name = cleanedName(evidence.name),
                let kind = evidence.kind, kind != .referred,
                !isRejected(name, by: cluster), !isReserved(name, in: reserved)
            else { continue }
            let onList = matchesKnown(name, request.knownNames)
            let offList = !request.knownNames.isEmpty && !onList
            let applied: Bool
            switch (kind, evidence.confidence) {
            // Outside a list it is only a suggestion (step 1.5: an introduction with a misheard surname, the
            // right person under a name the list does not hold, was the one applied false name of the test set).
            case (.introduction, .high): applied = (introduced[cluster.id]?.count ?? 0) <= 1 && !offList
            case (.announced, .high): applied = onList
            default: applied = false
            }
            add(
                Candidate(
                    cluster: cluster.id, name: name, source: .transcript,
                    status: applied ? .applied : .suggested,
                    strength: evidence.strength * (offList ? offListStrengthFactor : 1), evidence: [evidence]),
                to: &candidates)
        }

        // Platform: a share of the cluster's speaking time, the system channel only (phase F2).
        var platformClaims: [Int: [PlatformClaim]] = [:]
        for evidence in request.evidence where evidence.source == .platform {
            guard let cluster = cluster(for: evidence, in: request, indexes: indexes),
                !decided.contains(cluster.id), cluster.channel == .system,
                let name = cleanedName(evidence.name),
                !isRejected(name, by: cluster), !isReserved(name, in: reserved)
            else { continue }
            var claims = platformClaims[cluster.id, default: []]
            if let index = claims.firstIndex(where: { sameName($0.name, name) }) {
                claims[index].strength = max(claims[index].strength, evidence.strength)
                claims[index].evidence.append(evidence)
            } else {
                claims.append(PlatformClaim(name: name, strength: evidence.strength, evidence: [evidence]))
            }
            platformClaims[cluster.id] = claims
        }
        for (cluster, claims) in platformClaims {
            let ordered = claims.sorted { $0.strength > $1.strength }
            guard let best = ordered.first else { continue }
            let second = ordered.dropFirst().first?.strength ?? 0
            let status: SpeakerNameStatus
            if atLeast(best.strength, platformAppliedCoverage),
                atLeast(best.strength - second, platformAppliedLead)
            {
                status = .applied
            } else if atLeast(best.strength, platformSuggestedCoverage) {
                status = .suggested
            } else {
                continue
            }
            add(
                Candidate(
                    cluster: cluster, name: best.name, source: .platform, status: status, strength: best.strength,
                    evidence: best.evidence),
                to: &candidates)
        }

        // Calendar: only the owner and exactly one other attendee, with exactly one other cluster.
        if let calendar = request.calendar, calendar.includesOwner {
            let names = calendar.attendeeNames.compactMap(cleanedName)
            let owners = request.clusters.filter(\.isSelf)
            let others = request.clusters.filter { !$0.isSelf }
            if names.count == 1, owners.count == 1, others.count == 1, let cluster = others.first,
                !decided.contains(cluster.id),
                !isRejected(names[0], by: cluster), !isReserved(names[0], in: reserved)
            {
                add(
                    Candidate(
                        cluster: cluster.id, name: names[0], source: .calendar, status: .suggested,
                        strength: calendarStrength,
                        evidence: [
                            NameEvidence(
                                source: .calendar, name: names[0], speaker: cluster.label, kind: nil, segment: nil,
                                startMs: nil, endMs: nil, strength: calendarStrength, confidence: nil)
                        ]),
                    to: &candidates)
            }
        }

        // One candidate per cluster: the highest-priority source, the strongest evidence within it.
        var chosen: [Candidate] = []
        for cluster in request.clusters where !decided.contains(cluster.id) {
            guard let clusterCandidates = candidates[cluster.id], !clusterCandidates.isEmpty else { continue }
            if let best = clusterCandidates.min(by: isPreferred) { chosen.append(best) }
        }

        // One name per cluster and one cluster per name, greedily by strength; a tie blocks the name for both and
        // leaves it as a suggestion at each.
        var groups: [[Candidate]] = []
        for candidate in chosen.sorted(by: { $0.strength > $1.strength }) {
            if let index = groups.firstIndex(where: { sameName($0[0].name, candidate.name) }) {
                groups[index].append(candidate)
            } else {
                groups.append([candidate])
            }
        }
        for group in groups {
            guard let strongest = group.map(\.strength).max() else { continue }
            let top = group.filter { strongest - $0.strength <= strengthTieEpsilon }
            if top.count > 1 {
                for candidate in top {
                    guard let index = indexes[candidate.cluster] else { continue }
                    results[index] = suggestion(candidate)
                }
            } else if let winner = top.first, let index = indexes[winner.cluster] {
                results[index] = winner.status == .applied ? applied(winner) : suggestion(winner)
            }
        }
        return results
    }

    // MARK: Clusters and names

    /// One piece of evidence for one cluster, after the per-cluster rules (the transcript's strength, the
    /// platform's share) have given it its status and strength.
    private struct Candidate: Equatable {
        var cluster: Int
        var name: String
        var source: NameSource
        var status: SpeakerNameStatus
        var strength: Double
        var evidence: [NameEvidence]
    }

    /// One platform name's claim on a cluster: its share of the cluster's speaking time and the rows it rests on.
    private struct PlatformClaim: Equatable {
        var name: String
        var strength: Double
        var evidence: [NameEvidence]
    }

    /// The cluster a piece of evidence is about: through the segment's own cluster when the evidence names one,
    /// else through its cluster label when exactly one cluster has it. `nil` is unusable evidence.
    ///
    /// The segment of transcript evidence is where its quote starts. A self-introduction is said by the person it
    /// names, so that segment's cluster is the one. A vocative and an announcement are said by somebody else and
    /// name who speaks right after the quote (`NameEvidenceGuard` checks it): their cluster is the first later
    /// segment with the evidence's label.
    private static func cluster(
        for evidence: NameEvidence, in request: SpeakerNameRequest, indexes: [Int: Int]
    ) -> SpeakerNameCluster? {
        if let segment = evidence.segment {
            let named: Int?
            switch evidence.kind {
            case .addressed, .announced: named = answeringCluster(after: segment, label: evidence.speaker, in: request)
            default: named = request.segmentClusters[segment]
            }
            guard let id = named else { return nil }
            return request.clusters.first { $0.id == id }
        }
        guard let label = evidence.speaker else { return nil }
        let matching = request.clusters.filter { $0.label == label }
        return matching.count == 1 ? matching[0] : nil
    }

    /// The cluster of the first segment after `segment` whose cluster has `label`; `nil` when there is none.
    private static func answeringCluster(after segment: Int, label: String?, in request: SpeakerNameRequest) -> Int? {
        guard let label, let last = request.segmentClusters.keys.max(), segment < last else { return nil }
        let labels = Dictionary(request.clusters.map { ($0.id, $0.label) }, uniquingKeysWith: { first, _ in first })
        for index in (segment + 1)...last {
            guard let id = request.segmentClusters[index], labels[id] == label else { continue }
            return id
        }
        return nil
    }

    /// The index of every cluster in the request, by its id. A repeated id makes the whole plan ambiguous: no
    /// names are assigned.
    private static func clusterIndexes(of clusters: [SpeakerNameCluster]) -> [Int: Int]? {
        var indexes: [Int: Int] = [:]
        for (index, cluster) in clusters.enumerated() {
            guard indexes.updateValue(index, forKey: cluster.id) == nil else { return nil }
        }
        return indexes
    }

    /// The cluster comes back exactly as it went in: the user named or confirmed it (spec: Proposed Solution 4
    /// and Edge Cases, "Ponowna finalizacja").
    private static func isProtected(_ cluster: SpeakerNameCluster) -> Bool {
        cluster.source == .user || cluster.status == .confirmed
    }

    /// The resolution an untouched cluster keeps: its label as the name when the label is a real name, the
    /// source and status as stored, and the suggestion it already shows.
    private static func untouched(_ cluster: SpeakerNameCluster) -> SpeakerNameResolution {
        SpeakerNameResolution(
            cluster: cluster.id, name: cleanedName(cluster.label), source: cluster.source,
            status: cluster.status, suggestedName: cluster.suggestedName, evidence: [])
    }

    /// What a cluster no source names comes back as: no name, nothing to suggest. The automatic sources are
    /// recomputed on every resolution, so a name they gave before does not survive on its own (spec: Edge Cases,
    /// "Ponowna finalizacja": only `user` and `confirmed` are kept).
    private static func emptyState(_ cluster: SpeakerNameCluster) -> SpeakerNameResolution {
        SpeakerNameResolution(
            cluster: cluster.id, name: nil, source: cluster.isSelf ? .me : .default, status: .suggested,
            suggestedName: nil, evidence: [])
    }

    private static func applied(_ candidate: Candidate) -> SpeakerNameResolution {
        SpeakerNameResolution(
            cluster: candidate.cluster, name: candidate.name, source: candidate.source, status: .applied,
            suggestedName: nil, evidence: candidate.evidence)
    }

    private static func suggestion(_ candidate: Candidate) -> SpeakerNameResolution {
        SpeakerNameResolution(
            cluster: candidate.cluster, name: nil, source: candidate.source, status: .suggested,
            suggestedName: candidate.name, evidence: candidate.evidence)
    }

    // MARK: Selection

    /// The name as the meeting may use it: cleaned like a model's answer, not a placeholder, at most
    /// `NameEvidence.maximumNameLength` characters. `nil` for "no name".
    private static func cleanedName(_ text: String) -> String? {
        let name = NotesUtterance.sanitized(text)
        guard !name.isEmpty, name.count <= NameEvidence.maximumNameLength, !NotesGuard.isGenericLabel(name)
        else { return nil }
        return name
    }

    /// Two names are the same name for the one-to-one rule when they match by stem (`NotesText.namesMatch`:
    /// `Marek` / `Marku`, `Anna` / `Anno`), case and diacritics folded first.
    private static func sameName(_ first: String, _ second: String) -> Bool {
        NotesText.namesMatch(TextNormalizer.normalize(first), TextNormalizer.normalize(second))
    }

    /// Two introductions name one person when their first names match ("Marek Nowak" and "Marek"), the
    /// contradiction rule only.
    private static func samePerson(_ first: String, _ second: String) -> Bool {
        let firstWords = TextNormalizer.normalize(first).split(separator: " ")
        let secondWords = TextNormalizer.normalize(second).split(separator: " ")
        guard let one = firstWords.first, let other = secondWords.first else { return false }
        return NotesText.namesMatch(String(one), String(other))
    }

    private static func matchesKnown(_ name: String, _ knownNames: [String]) -> Bool {
        knownNames.contains { sameName(name, $0) }
    }

    private static func isRejected(_ name: String, by cluster: SpeakerNameCluster) -> Bool {
        cluster.rejectedNames.contains { sameName($0, name) }
    }

    private static func isReserved(_ name: String, in names: [String]) -> Bool {
        names.contains { sameName($0, name) }
    }

    /// `value >= threshold`, with the tie epsilon so `0.6 - 0.4` still counts as a lead of `0.2`.
    private static func atLeast(_ value: Double, _ threshold: Double) -> Bool {
        value >= threshold - strengthTieEpsilon
    }

    /// Which of two candidates a cluster takes: the surer state first (`applied` beats `suggested`, orchestrator
    /// decision 2026-11-26), then within one state the higher-priority source (spec: Proposed Solution 2), then the
    /// stronger evidence, then the alphabetically first name so a run is reproducible.
    private static func isPreferred(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        if lhs.status != rhs.status { return lhs.status == .applied }
        if lhs.source.priority != rhs.source.priority { return lhs.source.priority < rhs.source.priority }
        if abs(lhs.strength - rhs.strength) > strengthTieEpsilon { return lhs.strength > rhs.strength }
        return lhs.name < rhs.name
    }

    /// Adds a candidate, merging it with the one for the same cluster and name from the same source: the stronger
    /// strength wins and `applied` beats `suggested`.
    private static func add(_ candidate: Candidate, to candidates: inout [Int: [Candidate]]) {
        var clusterCandidates = candidates[candidate.cluster, default: []]
        guard
            let index = clusterCandidates.firstIndex(where: {
                $0.source == candidate.source && sameName($0.name, candidate.name)
            })
        else {
            clusterCandidates.append(candidate)
            candidates[candidate.cluster] = clusterCandidates
            return
        }
        clusterCandidates[index].strength = max(clusterCandidates[index].strength, candidate.strength)
        if candidate.status == .applied { clusterCandidates[index].status = .applied }
        clusterCandidates[index].evidence.append(contentsOf: candidate.evidence)
        candidates[candidate.cluster] = clusterCandidates
    }
}

extension NameSource {
    /// Which source wins a cluster when several have evidence for it (spec: Proposed Solution 2, lower wins).
    var priority: Int {
        switch self {
        case .user: 0
        case .me: 1
        case .platform: 2
        case .transcript: 3
        case .calendar: 4
        case .default: 5
        }
    }
}

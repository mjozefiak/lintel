import Foundation
import LintelSpeech

@testable import MeetingsPlugin

/// The speaker names step of the evaluation (spec `2026-11-25-meeting-speaker-names`, step 1.5): the transcript of
/// the run goes into a real encrypted `MeetingsStore` as a diarized meeting, then `MeetingSpeakerNames.refresh` runs
/// exactly as the notes job runs it (`SpeakerNamePass` on the notes model, `SpeakerNameResolver`,
/// `saveSpeakerNames`). The store lives in a temporary folder that is removed at the end.
///
/// What comes back:
/// - `names`: one `EvalResult.SpeakerName` per speaker that ended with a real name (applied or suggested), keyed by
///   the label the run's segments carry ("Mówca N"), which is how `score.py` joins names to words;
/// - `notesRows`: the rows the notes read, with an `applied` name as the speaker label (what the app's notes see);
///   a `suggested` name stays out of the notes, as in the app;
/// - `trace`: the counts the app puts in `NotesTrace` (no name, no quote).
///
/// `knownNames` simulates the calendar of a later phase (the `speakers` of the gold entry): the extractor and the
/// resolver get it, the model never does.
enum SpeakerNamesEval {
    struct Outcome {
        var names: [EvalResult.SpeakerName]
        var notesRows: [EvalResult.Segment]
        var trace: NotesTraceSpeakerNames?
        /// Per speaker, the stored result, and the evidence the pass accepted (for the out folder only: names).
        var speakers: [Dump.Speaker]
        var accepted: [Dump.Evidence]
        /// The excerpt block the pass sent (out folder only).
        var excerptsBlock = ""
    }

    /// The names file written beside the result with `_DUMP_REJECTIONS=1` (`<name>.names.json`). It holds names
    /// and the model's answer, so it stays in the evaluation's out folder; nothing of it is printed.
    struct Dump: Codable, Equatable {
        /// One piece of evidence the guard accepted: the cluster label of the quoted line, the segment index.
        struct Evidence: Codable, Equatable {
            var speaker: String?
            var name: String
            var kind: String?
            var confidence: String?
            var strength: Double
            var segment: Int?
        }

        struct Speaker: Codable, Equatable {
            var label: String
            var storedLabel: String
            var source: String?
            var status: String?
            var suggestedName: String?
        }

        var recording: String
        var knownNames: Int
        var speakers: [Speaker]
        var accepted: [Evidence]
        var answers: [String]
        /// The excerpt block as the model read it.
        var excerpts: String = ""
    }

    static func run(
        rows: [EvalResult.Segment], knownNames: [String], selfName: String, generator: any NotesGenerating,
        namesFromConversation: Bool = true
    ) async throws -> Outcome {
        let directory = try TemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory.url) }
        let store = try MeetingsStore.open(in: directory.url.appending(path: "meetings"), keys: try testKeys())

        // The speakers in the order of their first segment, as `SpeakerAssigner` numbers them.
        var labels: [String] = []
        for row in rows { if let label = row.speaker, !labels.contains(label) { labels.append(label) } }
        let id = try store.insertMeeting(
            uuid: UUID().uuidString, startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            speechModelID: "eval", status: .ready)
        var assignments: [Int64: Int] = [:]
        for row in rows {
            let segment = try store.insertSegment(
                meetingID: id, channel: AudioChannel(rawValue: row.track) ?? .mic, startMs: row.startMs,
                endMs: row.endMs, text: row.text)
            if let label = row.speaker, let speaker = labels.firstIndex(of: label) { assignments[segment] = speaker }
        }
        let speakers = labels.map { label in
            SpeakerPlan.Speaker(
                label: label, isSelf: label == SpeakerLabels.me,
                channel: rows.first(where: { $0.speaker == label }).flatMap { AudioChannel(rawValue: $0.track) }
                    ?? .mic)
        }
        try store.applySpeakerPlan(
            SpeakerPlan(mode: .diarized, speakers: speakers, assignments: assignments), meetingID: id,
            diarizationModelID: "eval")
        guard let document = try await MeetingLibraryIO.document(store: store, id: id) else {
            return Outcome(names: [], notesRows: rows, trace: nil, speakers: [], accepted: [])
        }

        // Numbers only: how the extractor's excerpts meet the pass's token budget.
        let cleaned = rows.map {
            NameSegment(
                speaker: SpeakerNamePrompt.sanitized($0.speaker ?? "?"), startMs: $0.startMs, endMs: $0.endMs,
                text: SpeakerNamePrompt.sanitized($0.text))
        }
        let all = NameMentionExtractor(knownNames: knownNames).excerpts(from: cleaned)
        let budget = SpeakerNamePass.Configuration().excerptBudget(
            inputBudgetTokens: generator.profile.inputBudgetTokens)
        let phrases = all.excerpts.filter { $0.candidates.contains { $0.kind != nil } }
        print(
            "MEETING-EVAL names-extractor excerpts=\(all.excerpts.count) cut=\(all.droppedExcerpts)"
                + " withPhrase=\(phrases.count) segments=\(all.excerpts.map(\.segments.count).reduce(0, +))"
                + " estTokens=\(all.excerpts.map(NameMentionExtractor.estimatedTokens).reduce(0, +))"
                + " estPhraseTokens=\(phrases.map(NameMentionExtractor.estimatedTokens).reduce(0, +)) budget=\(budget)")
        let sent = SpeakerNamePrompt.excerptsBlock(NameMentionExtractor.fitting(all, budget: budget).excerpts)
        let pass = SpeakerNamePass(generator: generator, knownNames: knownNames)
        let conditions = SpeakerNamePass.Conditions(
            notesEnabled: true, namesFromConversation: namesFromConversation, isChannelMeeting: false)
        let report = await MeetingSpeakerNames.refresh(
            store: store, document: document, selfName: selfName, pass: pass, conditions: conditions,
            knownNames: knownNames)

        // The speakers are written in plan order, so the index of a state is the index of its run label.
        let states = try store.speakerNameStates(meetingID: id)
        var names: [EvalResult.SpeakerName] = []
        var dumped: [Dump.Speaker] = []
        var renamed: [String: String] = [:]
        for (index, state) in states.enumerated() where labels.indices.contains(index) {
            let label = labels[index]
            let source = state.source?.rawValue ?? "unknown"
            switch state.status {
            case .applied:
                names.append(.init(label: label, name: state.label, source: source, status: "applied"))
                renamed[label] = state.label
            case .suggested:
                if let suggestion = state.suggestedName {
                    names.append(.init(label: label, name: suggestion, source: source, status: "suggested"))
                }
            case .confirmed where state.source != .default:
                names.append(.init(label: label, name: state.label, source: source, status: "confirmed"))
                renamed[label] = state.label
            default: break
            }
            dumped.append(
                .init(
                    label: label, storedLabel: state.label, source: state.source?.rawValue,
                    status: state.status?.rawValue, suggestedName: state.suggestedName))
        }
        var notesRows = rows
        for index in notesRows.indices {
            if let label = notesRows[index].speaker, let name = renamed[label] { notesRows[index].speaker = name }
        }
        let accepted = (report?.pass.accepted ?? []).map {
            Dump.Evidence(
                speaker: $0.speaker, name: $0.name, kind: $0.kind?.rawValue, confidence: $0.confidence?.rawValue,
                strength: $0.strength, segment: $0.segment)
        }
        var outcome = Outcome(
            names: names, notesRows: notesRows, trace: report?.trace, speakers: dumped, accepted: accepted)
        outcome.excerptsBlock = sent
        return outcome
    }

    /// The known names of a gold `entry.json` (`speakers[].name`), or of a JSON list of names.
    static func knownNames(at url: URL) throws -> [String] {
        let data = try Data(contentsOf: url)
        if let list = try? JSONDecoder().decode([String].self, from: data) { return list }
        struct Entry: Decodable {
            struct Speaker: Decodable { let name: String? }
            let speakers: [Speaker]
        }
        return try JSONDecoder().decode(Entry.self, from: data).speakers.compactMap(\.name).filter { !$0.isEmpty }
    }
}

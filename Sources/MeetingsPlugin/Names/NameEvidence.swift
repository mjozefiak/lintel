import Foundation

/// Where a speaker's name came from (spec `2026-11-25-meeting-speaker-names`, Proposed Solution and Data Model).
/// The raw values are written to `meeting_speaker.name_source`, so they never change after release.
enum NameSource: String, Sendable, CaseIterable, Codable {
    /// No name yet: the cluster is "Mówca N" (`meeting_speaker.name_source`'s default).
    case `default` = "default"
    /// The microphone's owner: the "To ja" cluster and `plugins.meetings.selfName` (raw value `self`; `me` keeps
    /// the Swift name readable, `self` is how the database and the spec spell it).
    case me = "self"
    /// A name the user typed (`MeetingWindowModel.renameSpeaker`); it is never overwritten by a resolution.
    case user = "user"
    /// The meeting app's participant list (`MeetingWindowReader`, phase F2).
    case platform = "platform"
    /// The attendees of the calendar event (phase F3).
    case calendar = "calendar"
    /// A name said in the conversation, found by `NameMentionExtractor` and checked by `NameEvidenceGuard`.
    case transcript = "transcript"
}

/// How sure Lintel is of a name (`meeting_speaker.name_status`). `confirmed` and `applied` are used in the
/// transcript and in the notes at once; `suggested` is shown as "Marek?" and the notes keep "Mówca N" until the
/// user confirms it (owner decision Q1 and Q3).
enum SpeakerNameStatus: String, Sendable, CaseIterable, Codable {
    /// The user confirmed or typed it.
    case confirmed
    /// Strong evidence from an automatic source (spec: `SpeakerNameResolver`).
    case applied
    /// Weak evidence, waiting for one click.
    case suggested
}

/// The kind of a name found in the conversation, as the notes model returns it (`SpeakerNamePrompt`); `referred`
/// is a third person's name and is refused by `NameEvidenceGuard`.
enum NameEvidenceKind: String, Sendable, CaseIterable, Codable {
    /// "tu Marek", "nazywam się", "mam na imię", "I'm Anna", "my name is", "this is Anna".
    case introduction
    /// "głos ma pan poseł Kowalski", "oddaję głos", "please welcome" — the chair gives the floor to the person
    /// who speaks right after the announcement.
    case announced
    /// A vocative: "Marku, zrobisz to?" names the person who answers.
    case addressed
    /// Somebody talking about a third person ("Marek mówił, że…"): no evidence for who is speaking.
    case referred
}

/// The model's own confidence in one name (`confidence` in the prompt's JSON). Only transcript evidence has it.
enum NameEvidenceConfidence: String, Sendable, CaseIterable, Codable {
    case high
    case low
}

/// One piece of evidence for a speaker's name, shaped like a row of `meeting_name_evidence` (spec: Data Model):
/// the source, the name, the cluster, the kind, the segment the name was heard in and its time. The quote is
/// NOT copied: the evidence points at the segment (`NotesGuard` keeps the transcript text out of anything
/// stored).
struct NameEvidence: Equatable, Sendable {
    /// The longest name a source may give, the same one `plugins.meetings.selfName` uses.
    static let maximumNameLength = MeetingsSettings.maximumSelfNameLength

    var source: NameSource
    /// The name as it will be shown, in the nominative (`Marek`, not `Marku`).
    var name: String
    /// The cluster the name belongs to, as the transcript labels it (`meeting_speaker.label`: "Mówca 3",
    /// "Ja" or a name). The pure layer never knows the database id: steps 1.4a and 1.4b map the label back to
    /// `meeting_speaker.id`, through the segment's own `speaker_id` rather than the label alone (two speakers may
    /// share a label after "Zostaw osobno"). `nil` for a source that carries no cluster (`calendar` until a later
    /// step matches it).
    var speaker: String?
    /// The kind of a name said in the conversation; `nil` for `self`, `user`, `platform` and `calendar`.
    var kind: NameEvidenceKind?
    /// The index of the segment the name was heard in, in the transcript the source was given; step 1.4a
    /// writes its `meeting_segment.id`.
    var segment: Int?
    var startMs: Int?
    var endMs: Int?
    /// How strong the evidence is, for `SpeakerNameResolver`: the model's confidence for a transcript name,
    /// the source's own measure for `platform` (a share of speaking time, phase F2).
    var strength: Double
    /// The model's own answer, `transcript` only.
    var confidence: NameEvidenceConfidence?
}

/// What the notes model said about one name before the guard checked it: the output line of
/// `SpeakerNamePrompt`, `[{speaker, name, kind, quote, confidence}]`. The quote is checked against the
/// transcript and never stored.
struct NameProposal: Equatable, Sendable {
    /// The cluster the name belongs to, as the transcript labels the excerpt's lines. For an introduction it is
    /// the speaker of the quoted line; for a vocative and for an announcement it is the person who speaks right
    /// after the quote (the one who answers, or the one given the floor), and the guard checks that they do.
    var speaker: String
    /// The name the model gives, in the nominative.
    var name: String
    var kind: NameEvidenceKind
    /// The words of the transcript the name stands in, as the model copied them from the excerpt.
    var quote: String
    var confidence: NameEvidenceConfidence
}

/// One segment of the transcript for the name pass: the cluster's label, its time and its text. `NameMentionExtractor`
/// reads them and `NameEvidenceGuard` checks quotes against them; neither needs the database.
struct NameSegment: Equatable, Sendable {
    var speaker: String
    var startMs: Int
    var endMs: Int
    var text: String

    /// `[mm:ss] Speaker: text`, the line format of the excerpts and of the notes' chunks.
    var line: String {
        "[\(NotesText.clock(milliseconds: startMs))] \(speaker): \(text)"
    }
}

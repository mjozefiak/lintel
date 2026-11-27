import Foundation

// Contract additions for the Notes workspace (spec `.ai/specs/2026-11-04-notes-workspace.md`, step 1.1, ADR 0008).
// All of them are additive: `LintelPlugin.noteSources`, `PluginContext.noteSources` / `noteSourcesChanged` /
// `openNote` and `PasteboardClient.write(_:options:)` have defaults, so a plugin written before them compiles
// unchanged. Step 4.6 adds `LintelPlugin.keptNoteCopyCount(ofOwner:)` / `deleteKeptNoteCopies(ofOwner:ownerErased:)` and
// `PluginContext.keptNoteCopies` / `deleteKeptNoteCopies` (same rule: defaults). Note sources carry plain `String` text only: no attributed, HTML or other markup is ever returned.
//
// The notes explorer (spec `.ai/specs/2026-11-24-notes-explorer-main-window.md`, phase 1.1) adds, also additively:
// the optional `NoteSourceTrash` refinement with `NoteSourceError` and `TrashBatch`, the `TrashSource` /
// `TrashPage` / `TrashedItem` contract for stores the Notes section cannot reach as note sources, `NoteSummary`'s
// `deletedAt`, `purgeAt`, `taskCount`, `wordCount` and `liveSince`, `NoteLayer.writer` with `NoteWriter`,
// `LiveRecorder` with `LiveRecordingStatus` and `LiveRecordingFailure`, and the `LintelPlugin.liveRecorder` /
// `PluginContext.liveRecorder` hooks (in their own files). No plugin has to conform to anything new.

/// Key of one note in the persisted format `<plugin id>:<id>` (`meetings:<uuid>`, `dictation:<store id>/<row id>`,
/// `notes:<uuid>`). Only the first `:` separates the plugin id from the rest. Never reused after Erase Data or a
/// key reset; a recreated store gets new keys.
public struct NoteKey: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    /// The only way to build a key (decoding goes through it too).
    public init(pluginID: PluginID, id: String) {
        self.rawValue = "\(pluginID.rawValue):\(id)"
    }

    /// The plugin that owns the note.
    public var pluginID: PluginID {
        guard let separator = rawValue.firstIndex(of: ":") else { return PluginID(rawValue: "") }
        return PluginID(rawValue: String(rawValue[..<separator]))
    }

    /// Everything after the first `:`.
    public var id: String {
        guard let separator = rawValue.firstIndex(of: ":") else { return "" }
        return String(rawValue[rawValue.index(after: separator)...])
    }

    public var description: String { rawValue }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let separator = raw.firstIndex(of: ":"), separator != raw.startIndex,
            raw.index(after: separator) != raw.endIndex
        else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "A note key is \"<plugin id>:<id>\".")
        }
        self.init(
            pluginID: PluginID(rawValue: String(raw[..<separator])),
            id: String(raw[raw.index(after: separator)...]))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// What kind of note it is. An open set: consumers handle unknown values, new values are additive.
public struct NoteKind: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let meeting = NoteKind(rawValue: "meeting")
    public static let dictation = NoteKind(rawValue: "dictation")
    public static let manual = NoteKind(rawValue: "manual")

    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Who wrote a revision or a layer. An open set: consumers handle unknown values, new values are additive.
public struct NoteAuthor: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// Speech to text.
    public static let stt = NoteAuthor(rawValue: "stt")
    /// A language model.
    public static let agent = NoteAuthor(rawValue: "agent")
    public static let human = NoteAuthor(rawValue: "human")

    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Who wrote the text of one layer, named for the reader ("Lintel wrote these notes … on this Mac.", "Claude wrote
/// these notes …"). A closed set: the source maps its own record to a case, and a record this build cannot map
/// (a provider added later, no notes at all) is `nil`, so an older build shows no footer instead of guessing.
/// Not `Codable`: nothing stores it, the source derives it on every read. Added with the notes explorer.
///
/// Meetings maps `meeting.notes_status` and `meeting.notes_provider` like this: notes exist (`ok`, `partial` or
/// `stale`) and `notes_provider IS NULL` is `.thisMac`; `notes_provider == "claude-code"` (`ProviderID.claudeCode`,
/// not `claude`) is `.claude`; any other value, or no notes, is `nil`. The mapping and its test belong to the
/// source, not to `LintelKit`.
public enum NoteWriter: String, Sendable, CaseIterable {
    /// The built-in language model, on this Mac.
    case thisMac
    /// An external AI provider's CLI (Claude Code).
    case claude
}

/// The state of a note as its source reports it. A closed set, frozen with step 1.1: it mirrors the sources'
/// status columns.
public enum NoteState: Sendable, Equatable {
    case ready
    case recording
    case processing
    case writing(done: Int, of: Int)
    case partial
    case stale
    case interrupted
    case failed
    case needsModel
}

/// One layer's matching text for a search.
public struct NoteLayerMatch: Sendable, Equatable {
    public var layerID: String
    /// Plain text; the shell highlights, sources never return markup.
    public var snippet: String

    public init(layerID: String, snippet: String) {
        self.layerID = layerID
        self.snippet = snippet
    }
}

/// A row of the explorer.
public struct NoteSummary: Sendable, Identifiable, Equatable {
    public var id: NoteKey
    public var kind: NoteKind
    public var title: String?
    public var startedAt: Date
    public var durationMs: Int?
    /// A secondary label, only when the source knows it.
    public var sourceApp: String?
    public var state: NoteState
    /// Every matched layer of a search.
    public var matches: [NoteLayerMatch]
    public var titleMatched: Bool
    /// When the note moved to Recently deleted; set only in the pages of `NoteSourceTrash.trashed(after:limit:)`
    /// (`nil` everywhere else, a live note included). Added with the notes explorer.
    public var deletedAt: Date?
    /// When the note is deleted for good: the earlier of `deletedAt` + 30 days and the row's retention limit.
    /// Set only together with `deletedAt`. Never `nil` in the pages of `NoteSourceTrash.trashed(after:limit:)`
    /// (every row there carries it); `Date?` only because the struct is shared with the live list, where it is
    /// `nil`. Added with the notes explorer.
    public var purgeAt: Date?
    /// How many tasks the notes carry ("3 tasks"); `nil` means the row shows no count. Added with the notes
    /// explorer.
    public var taskCount: Int?
    /// How many words the text has ("118 words"); `nil` means the row shows no count. Added with the notes
    /// explorer.
    public var wordCount: Int?
    /// When a note that is being recorded now started ("Now" row timer); set only for `NoteState.recording` and
    /// `NoteState.processing`. Added with the notes explorer.
    public var liveSince: Date?

    public init(
        id: NoteKey,
        kind: NoteKind,
        title: String? = nil,
        startedAt: Date,
        durationMs: Int? = nil,
        sourceApp: String? = nil,
        state: NoteState = .ready,
        matches: [NoteLayerMatch] = [],
        titleMatched: Bool = false,
        deletedAt: Date? = nil,
        purgeAt: Date? = nil,
        taskCount: Int? = nil,
        wordCount: Int? = nil,
        liveSince: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.startedAt = startedAt
        self.durationMs = durationMs
        self.sourceApp = sourceApp
        self.state = state
        self.matches = matches
        self.titleMatched = titleMatched
        self.deletedAt = deletedAt
        self.purgeAt = purgeAt
        self.taskCount = taskCount
        self.wordCount = wordCount
        self.liveSince = liveSince
    }
}

/// What lets the UI draw a quote chip for one block of a layer.
public struct NoteBlockProvenance: Sendable, Equatable {
    /// Index of the block as split by `LintelCore.MarkdownBlocks.split`.
    public var blockIndex: Int
    public var quoteTimesMs: [Int]
    /// Transcript layers only, `nil` otherwise.
    public var speakerID: String?
    public var startMs: Int?
    public var segmentRef: String?

    public init(
        blockIndex: Int,
        quoteTimesMs: [Int] = [],
        speakerID: String? = nil,
        startMs: Int? = nil,
        segmentRef: String? = nil
    ) {
        self.blockIndex = blockIndex
        self.quoteTimesMs = quoteTimesMs
        self.speakerID = speakerID
        self.startMs = startMs
        self.segmentRef = segmentRef
    }
}

/// How sure the owner is of a speaker's shown `name` (speaker names, spec `2026-11-25-meeting-speaker-names`). A
/// closed set: adding a case is a breaking change of this contract (`BACKWARD_COMPATIBILITY.md` §1).
public enum NoteSpeakerNameStatus: String, Sendable, Equatable, CaseIterable {
    /// The name is final: the user gave or confirmed it, it is the user's own, or it is the default label nobody
    /// named. The default for every speaker of a source that does not know names.
    case confirmed
    /// An automatic name the owner is sure of (the person introduced themselves, the meeting window named them).
    /// It is used in the transcript and the notes without a click; the user can still change it.
    case applied
    /// `name` is still the default label ("Speaker 2"); `suggestion` waits for the user's yes or no and is never
    /// used in the notes.
    case suggested
}

public struct NoteSpeaker: Sendable, Equatable {
    public var id: String
    public var name: String
    public var isSelf: Bool
    /// Added with speaker names; `.confirmed` for a source that does not know them.
    public var nameStatus: NoteSpeakerNameStatus
    /// The name waiting for the user's confirmation ("Marek?"); set only with `nameStatus == .suggested`.
    public var suggestion: String?

    public init(
        id: String, name: String, isSelf: Bool = false, nameStatus: NoteSpeakerNameStatus = .confirmed,
        suggestion: String? = nil
    ) {
        self.id = id
        self.name = name
        self.isSelf = isSelf
        self.nameStatus = nameStatus
        self.suggestion = suggestion
    }
}

/// One layer of a note (`notes`, `transcript`, `cleaned`, `original`).
public struct NoteLayer: Sendable, Equatable, Identifiable {
    public var id: String
    public var author: NoteAuthor
    public var markdown: String
    /// Empty for `stt` layers and for sources that cannot say.
    public var provenance: [NoteBlockProvenance]
    /// Changes only when THIS layer's markdown or provenance changes (for example a SHA-256 of both). Neither
    /// speaker names nor speaker ids are part of it.
    public var version: String
    /// Who wrote the layer's text, when the source can say who ("On this Mac" / "Claude"); `nil` shows no footer.
    /// The source maps its own record to a `NoteWriter` (Meetings: notes exist and `notes_provider IS NULL` is
    /// `.thisMac`, `"claude-code"` is `.claude`, anything else or no notes is `nil`; see `NoteWriter`), never the
    /// UI. Added with the notes explorer.
    public var writer: NoteWriter?

    public init(
        id: String,
        author: NoteAuthor,
        markdown: String,
        provenance: [NoteBlockProvenance] = [],
        version: String,
        writer: NoteWriter? = nil
    ) {
        self.id = id
        self.author = author
        self.markdown = markdown
        self.provenance = provenance
        self.version = version
        self.writer = writer
    }
}

/// A label and value for the Details pane (language, speech model, audio state).
public struct NoteDetail: Sendable, Equatable {
    public var label: LocalizedStringResource
    public var value: String

    public init(label: LocalizedStringResource, value: String) {
        self.label = label
        self.value = value
    }
}

public struct NoteContent: Sendable {
    public var summary: NoteSummary
    public var layers: [NoteLayer]
    public var speakers: [NoteSpeaker]
    public var details: [NoteDetail]

    public init(
        summary: NoteSummary,
        layers: [NoteLayer] = [],
        speakers: [NoteSpeaker] = [],
        details: [NoteDetail] = []
    ) {
        self.summary = summary
        self.layers = layers
        self.speakers = speakers
        self.details = details
    }
}

/// An opaque paging position; only the source that returned it reads it.
public struct NoteCursor: Sendable, Hashable {
    public let token: String
    public init(token: String) { self.token = token }
}

public struct NotePage: Sendable {
    public var items: [NoteSummary]
    public var next: NoteCursor?
    public var total: Int

    public init(items: [NoteSummary] = [], next: NoteCursor? = nil, total: Int = 0) {
        self.items = items
        self.next = next
        self.total = total
    }
}

/// An action of the owner on a note (finish the transcript, regenerate, open Models).
public struct NoteSourceAction: Identifiable, Sendable {
    public let id: String
    public let title: LocalizedStringResource
    public let symbolName: String
    public let isDestructive: Bool
    public let perform: @Sendable () async throws -> Void

    public init(
        id: String,
        title: LocalizedStringResource,
        symbolName: String,
        isDestructive: Bool = false,
        perform: @escaping @Sendable () async throws -> Void
    ) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.isDestructive = isDestructive
        self.perform = perform
    }
}

/// The recorded notes a plugin owns, read by the Notes section. A plugin keeps its data; Notes only reads it.
public protocol NoteSource: Sendable {
    var pluginID: PluginID { get }
    /// `list`, `exists` and `content` throw whenever the owner's store is not open (switched off, Keychain locked
    /// or denied, failed, not yet opened); only an open store may report absence. The error type is the source's
    /// own (a plugin cannot import Notes, so the contract names none): the consumer treats ANY thrown error as
    /// "source unavailable", never as "the note is gone", and never detaches or reports absence because of one.
    func list(matching: NormalizedQuery?, after: NoteCursor?, limit: Int) async throws -> NotePage
    /// Batch for the detach sweep: the subset of `keys` that still exist. Any thrown error means "unknown"
    /// (store not open), never "none exist".
    ///
    /// Since the notes explorer (documented meaning, not a new signature): **a note in Recently deleted still
    /// exists**; only a permanent delete, the 30-day purge or retention makes it gone. So the detach sweep never
    /// detaches the overlays of a trashed note, and a trashed note's overlays can still come back on Restore.
    /// `list(matching:after:limit:)` never returns a trashed row, and a search never matches one.
    func exists(_ keys: [NoteKey]) async throws -> Set<NoteKey>
    /// `nil` means the note is gone (the store is open and has no such note); any thrown error means "unknown"
    /// (source off, failed, locked).
    ///
    /// Since the notes explorer: **a note in Recently deleted still has its content.** `content(for:)` returns it,
    /// with `summary.deletedAt` and `summary.purgeAt` set, and never `nil`; `nil` only after a permanent delete,
    /// the purge or retention. Hiding a trashed note is the reader's job (Notes checks `deletedAt` and
    /// `trashedKeys`). A reconcile that read `nil` would detach the overlays of a trashed note, which the
    /// deletion lifecycle forbids.
    func content(for key: NoteKey) async throws -> NoteContent?
    /// Deletes the note permanently. It works on a note that is in Recently deleted too (Delete Now and Empty call
    /// it there).
    func delete(_ key: NoteKey) async throws
    /// The owner's actions on a note. For a key that is in Recently deleted: an empty list.
    func actions(for key: NoteKey) -> [NoteSourceAction]
    /// One stream per call (`.bufferingNewest(1)`), finished on `deactivate()`.
    func makeChanges() -> AsyncStream<Void>
}

/// Why an edit of `NoteSourceEditing` was not made. Added with speaker names; any other error stays the source's own.
public enum NoteEditingError: Error, Sendable, Equatable {
    /// The source does not offer this edit (the default of every edit added after the first three).
    case unsupported
}

/// Optional capability, found with `as?`: the edits that must stay in the owner.
public protocol NoteSourceEditing: NoteSource {
    func renameTitle(_ key: NoteKey, to: String) async throws
    func renameSpeaker(_ key: NoteKey, speakerID: String, to: String) async throws
    /// Marks the speaker as the user; the owner sets its notes `stale`.
    func markSelf(_ key: NoteKey, speakerID: String) async throws
    /// "Yes" on a suggestion: `name` (the suggestion the screen showed) becomes the speaker's name, the user's own,
    /// and the owner sets its notes `stale`. Throws when the speaker no longer suggests `name` (the screen was
    /// older than the note). Default: `NoteEditingError.unsupported`.
    func confirmSpeakerName(_ key: NoteKey, speakerID: String, name: String) async throws
    /// "No" on a suggestion: the owner remembers that this speaker is not `name` and never suggests it again; the
    /// shown name stays. Throws when the speaker no longer suggests `name`. Default:
    /// `NoteEditingError.unsupported`.
    func rejectSpeakerName(_ key: NoteKey, speakerID: String, name: String) async throws
    /// Two speakers are one person: everything `speakerID` said moves to `targetSpeakerID`, `speakerID` goes away
    /// and the owner sets the notes `stale`. Refused while the note is being recorded or processed. Default:
    /// `NoteEditingError.unsupported`.
    func mergeSpeakers(_ key: NoteKey, speakerID: String, into targetSpeakerID: String) async throws
}

extension NoteSourceEditing {
    public func confirmSpeakerName(_ key: NoteKey, speakerID: String, name: String) async throws {
        throw NoteEditingError.unsupported
    }

    public func rejectSpeakerName(_ key: NoteKey, speakerID: String, name: String) async throws {
        throw NoteEditingError.unsupported
    }

    public func mergeSpeakers(_ key: NoteKey, speakerID: String, into targetSpeakerID: String) async throws {
        throw NoteEditingError.unsupported
    }
}

// MARK: - Recently deleted (notes explorer, phase 1.1)

/// Why a note cannot be moved to Recently deleted or put back. Any other error stays the source's own type: the
/// consumer shows the generic failure strip for those and maps these two to their own sentences ("You can delete
/// this meeting after it's saved.", "This note was deleted permanently.").
public enum NoteSourceError: Error, Sendable, Equatable {
    /// The note is recording or being processed; nothing changed.
    case busy
    /// The owner's store is open and has no such note (it was purged or deleted permanently).
    case notFound
}

/// What one bulk move to Recently deleted did: every row it moved carries exactly `deletedAt`, and the next two
/// numbers let the caller say what stayed behind.
///
/// The stamp is the batch: `restoreBatch(deletedAt:)` puts back exactly the rows it moved, never a row deleted
/// earlier or later, and it survives a quit (Cancel of a bulk deletion uses it). A single `trash` never reuses a
/// batch stamp.
///
/// Precision: stamps are compared to within 1 µs. The store writes `at` and compares it through the same
/// conversion (the same round trip to its column type), so a stamp read back after the database is reopened
/// equals the one written. A single `trash` that would land on a batch stamp (within 1 µs) is stamped 1 µs later.
public struct TrashBatch: Sendable, Equatable {
    /// The `deleted_at` every moved row was stamped with.
    public var deletedAt: Date
    /// How many rows moved.
    public var moved: Int
    /// How many live rows stayed because they were busy (recording, being processed).
    public var stayed: Int

    public init(deletedAt: Date, moved: Int, stayed: Int) {
        self.deletedAt = deletedAt
        self.moved = moved
        self.stayed = stayed
    }
}

/// One row of a `TrashSource`'s Recently deleted page.
public struct TrashedItem: Sendable, Identifiable, Equatable {
    /// The source's own id for the row, the one `trash`, `restore` and `deleteNow` take.
    public var id: String
    /// What the thing is ("Clipboard item", "Note"), localized by the source.
    public var kindLabel: LocalizedStringResource
    /// The title shown to the user; `nil` when the source `hidesContent` (and when it has no title).
    public var title: String?
    public var deletedAt: Date
    /// When the row is deleted for good: the earlier of `deletedAt` + 30 days and the row's retention limit
    /// ("Deletes in 12 days").
    public var purgeAt: Date

    public init(
        id: String,
        kindLabel: LocalizedStringResource,
        title: String? = nil,
        deletedAt: Date,
        purgeAt: Date
    ) {
        self.id = id
        self.kindLabel = kindLabel
        self.title = title
        self.deletedAt = deletedAt
        self.purgeAt = purgeAt
    }
}

/// One page of a `TrashSource`'s Recently deleted rows, newest-deleted first.
public struct TrashPage: Sendable {
    public var items: [TrashedItem]
    /// Opaque to everyone but the source that returned it; `nil` on the last page.
    public var next: String?
    public var total: Int

    public init(items: [TrashedItem] = [], next: String? = nil, total: Int = 0) {
        self.items = items
        self.next = next
        self.total = total
    }
}

/// One store's Recently deleted, for a store the Notes section cannot reach as a note source: the clipboard, and
/// Notes' own manual notes. A plugin contributes one through `LintelPlugin.trashSources`; the shell hands the
/// active plugins' sources to the Recently deleted view, so nothing imports the owner.
///
/// The rules are the ones of `NoteSourceTrash`, with `String` ids instead of `NoteKey`s:
///
/// - `trash`, `restore` and `deleteNow` take at most 500 ids per call; a store that is given more processes them
///   in chunks of 500, never truncating silently and never trapping. An id the store does not have is skipped (it
///   is gone already, which is what the caller wanted). A busy row (recording, being processed) makes `trash`
///   throw `NoteSourceError.busy` for the whole call and change nothing; `trash` of a row already trashed is a
///   no-op.
/// - `restore` puts back every id that is trashed, is a no-op for a live one, and returns the ids the store no
///   longer has (purged or deleted permanently) so the UI can say how many were gone; it does not throw
///   `notFound` for a batch.
/// - `trashed(after:limit:)` pages newest-deleted first with `purgeAt` on every row.
/// - `trashAll(at:)` moves every live row that is not busy, all with the same `deleted_at`; the stamp is the
///   batch, so `restoreBatch(deletedAt:)` puts back exactly that batch and skips rows already purged or removed
///   by retention, answering how many came back. A single `trash` never reuses a batch stamp. Stamps are compared
///   to within 1 µs, through the same conversion on write and on compare; a single `trash` that would clash with
///   a batch stamp is stamped 1 µs later.
/// - `deleteNow` is the permanent delete (Delete Now, Empty Recently deleted); it works on a trashed row.
/// - `makeChanges()` fires after trash, restore, `trashAll`, `restoreBatch` and a purge (the retention job
///   included); one stream per call, finished when the plugin deactivates.
/// - With `hidesContent`, no method ever returns a title or any text of an item.
/// - The store logs codes, counts and hashed ids only, never titles or text.
public protocol TrashSource: Sendable {
    /// Stable id, for example `clipboard` or `notes`; it names the source's rows in the view.
    var id: String { get }
    /// The source's name shown above its rows ("Clipboard", "Notes").
    var title: LocalizedStringResource { get }
    /// When `true` the rows carry no content at all: `TrashedItem.title` is `nil` and the view draws its own
    /// label ("Clipboard item · 2 min ago").
    var hidesContent: Bool { get }
    func liveCount() async throws -> Int
    func trashedCount() async throws -> Int
    func trashed(after: String?, limit: Int) async throws -> TrashPage
    func trash(_ ids: [String]) async throws
    /// Returns the ids the store no longer has; see the rules above.
    @discardableResult
    func restore(_ ids: [String]) async throws -> Set<String>
    func deleteNow(_ ids: [String]) async throws
    func trashAll(at deletedAt: Date) async throws -> TrashBatch
    func restoreBatch(deletedAt: Date) async throws -> Int
    /// One stream per call (`.bufferingNewest(1)`), finished on `deactivate()`.
    func makeChanges() -> AsyncStream<Void>
}

extension TrashSource {
    /// A source that shows its titles (Notes' manual notes); only the clipboard hides content.
    public var hidesContent: Bool { false }
}

/// The Recently deleted a note source can offer, found with `as?`. A source that does not conform has no Recently
/// deleted: Notes keeps today's confirmation sheet and permanent `delete` for its notes, and nothing else changes.
///
/// The rules every conformer follows:
///
/// - `trash` on a note that is recording or being processed throws `NoteSourceError.busy` and changes nothing; on
///   an already trashed note it is a no-op; on a missing note it throws `NoteSourceError.notFound`.
/// - `restore(_:)` is the batch restore: it puts back every key that exists and returns the keys that no longer
///   exist (purged or deleted permanently); `NoteSourceError.notFound` is not thrown for a batch, a live note is a
///   no-op. The UI says "N notes were deleted permanently." for a non-empty result.
/// - `trashed(after:limit:)` pages newest-deleted first, and every returned `NoteSummary` carries `deletedAt` and
///   `purgeAt`. `NoteSource.list` and every search never return a trashed note.
/// - A note in Recently deleted still has content: `content(for:)` returns it (with `deletedAt` and `purgeAt`),
///   never `nil`; `nil` only after a permanent delete, the purge or retention. `actions(for:)` of a trashed key is
///   empty, and `delete(_:)` works on it (Delete Now and Empty call it; it keeps its meaning, permanent).
/// - `trashAll(at:)` moves every live note except busy ones, stamping all of them with exactly `at`; the stamp is
///   the batch, so `restoreBatch(deletedAt:)` puts back exactly that batch (never a note deleted earlier or later)
///   and it survives a quit. A single `trash` never reuses a batch stamp: stamps are compared to within 1 µs,
///   written and compared through the same conversion (a round trip that survives reopening the database), and a
///   single `trash` that would clash is stamped 1 µs later.
/// - After `trash`, `restore`, `trashAll`, `restoreBatch` and a purge (the retention job included) the source
///   announces the change through the same stream as after `delete`: `NoteSource.makeChanges()`. There is no new
///   method; Notes' sweep stands on that event.
/// - `restore(_:)` and `trashedKeys(_:)` take at most 500 keys per call; a source that is given more processes
///   them in chunks of 500, never truncating silently and never trapping.
/// - The trash of a note never touches another store, its audio or the notes overlays; Notes marks the overlays
///   through `trashedKeys(_:)` and only the owner's purge makes a note gone.
public protocol NoteSourceTrash: NoteSource {
    /// Moves one note to Recently deleted; `NoteSourceError.notFound` when there is no such note, `.busy` while
    /// it is recording or being processed. Returns the `deleted_at` the owner used, so Notes marks the overlays
    /// with the same time.
    @discardableResult
    func trash(_ key: NoteKey) async throws -> Date
    /// Moves every live note except the busy ones to Recently deleted, all stamped with `deletedAt`.
    func trashAll(at deletedAt: Date) async throws -> TrashBatch
    /// Puts the notes back (batch, at most 500 keys per call) and returns the keys that no longer exist; see the
    /// rules above.
    @discardableResult
    func restore(_ keys: [NoteKey]) async throws -> Set<NoteKey>
    /// Puts back every note whose `deleted_at` equals the batch stamp and that still exists, answering how many
    /// came back; a note already purged or removed by retention is skipped.
    func restoreBatch(deletedAt: Date) async throws -> Int
    /// The notes that are not in Recently deleted.
    func liveCount() async throws -> Int
    /// The notes in Recently deleted.
    func trashedCount() async throws -> Int
    /// One page of Recently deleted notes, newest-deleted first, every row with `deletedAt` and `purgeAt`.
    func trashed(after: NoteCursor?, limit: Int) async throws -> NotePage
    /// Which of these keys are in Recently deleted, each with the owner's `deleted_at` (batch, at most 500 keys per
    /// call, without loading the rows). The trash sweep uses it to mark the overlays of a note deleted elsewhere
    /// (the launcher's panel, a bulk delete) with the owner's time.
    func trashedKeys(_ keys: [NoteKey]) async throws -> [NoteKey: Date]
}

// MARK: - Live recording (notes explorer, phase 1.1)

/// Why a live recording could not start or was lost. Each case has one sentence and one fix button in the UI; any
/// other error is the plugin's own and gets the generic sentence. A closed set: adding a case is a change in tree
/// that needs the UI's sentence (a compile error, not a runtime one).
public enum LiveRecordingFailure: Error, Sendable, Equatable {
    /// The microphone permission is denied or was refused at the key press.
    case microphoneDenied
    /// A recording is already running.
    case alreadyRecording
    /// The owner's library is not open (Keychain locked or denied, the store failed): nothing was touched.
    case libraryUnavailable
    /// The speech recognition model is not on this Mac.
    case modelMissing
    /// The previous recording is still being processed; one can start after it is saved.
    case stillProcessing
    /// There is no audio input device.
    case noAudioInput
    /// There is too little free disk space to start.
    case lowDisk
    /// The speech model is not usable right now: it is being removed or used by another job.
    case modelBusy
    /// Nothing was heard, so the recording was discarded. Reported as `LiveRecordingStatus.failed(key:reason:)`
    /// with the discarded recording's key, so Notes can keep the user's own writing (`mine`) as a manual note.
    case discarded
    /// Any other failure; the UI shows its generic sentence.
    case other
}

/// What a live recording is doing now, as the core toolbar, the list and the preview draw it.
///
/// The owner maps its own recording notices to `hearing` and `warning` like this (Meetings, from the HUD's state):
///
/// | The recording notices | Status |
/// |---|---|
/// | System audio unavailable at the start (`unavailable(.system)`), microphone fine | `hearing: .microphoneOnly`, no warning |
/// | The microphone was never part of the recording: denied, system-audio-only, or not started after the start retries (`microphoneNotRecorded`) | `hearing: .callOnly`, no warning |
/// | System audio was lost during the recording (`lost(.system)`) | `warning: .callAudioMissing` |
/// | The system track heard nothing for about 20 s (`noSystemAudio`) | `warning: .silence` |
/// | The microphone track is digitally silent (`noMicrophoneAudio`) | `warning: .microphoneSilent` |
/// | The microphone was recorded and then went away mid-meeting (`deviceDisconnected`, `lost(.mic)`) | `warning: .microphoneLost`; `hearing` stays as it was |
/// | Low disk space, a write problem, the time-limit countdown | HUD only, never a status |
///
/// Each HUD notice is in exactly one row. `microphoneLost` is a warning and leaves `hearing` untouched: the
/// recording did hear the microphone until it went away, and the warning says it stopped.
///
/// The notes' own failure is not a status: after `processing` comes `idle`, and the state of the notes is read
/// from `NoteSummary.state` (`writing`, `partial`, `failed`) of the owner's note.
public enum LiveRecordingStatus: Sendable, Equatable {
    /// How well Lintel hears the call.
    public enum Hearing: Sendable, Equatable {
        /// The user and the other people in the call.
        case everyone
        /// Only the microphone (no system audio); the UI offers "Fix Call Audio".
        case microphoneOnly
        /// Only the call's audio: the microphone was never part of the recording (denied, system audio only, not
        /// started); the UI offers "Fix Microphone".
        case callOnly
    }

    /// A problem the recording notices: set by the same timers as the HUD notices and cleared when it goes away.
    public enum Warning: Sendable, Equatable {
        /// The system track heard nothing for about 20 s.
        case silence
        /// System audio could not be recorded (permission, no tap) or was lost during the recording.
        case callAudioMissing
        /// The microphone is digitally silent (about 10 s).
        case microphoneSilent
        /// The microphone was recorded and then went away during the meeting (the device was disconnected).
        case microphoneLost
    }

    case idle
    case starting
    case recording(key: NoteKey, since: Date, hearing: Hearing, warning: Warning?)
    /// The recording stopped; the meeting is being transcribed and its notes written. `progress` is `0…1` when
    /// the owner can say, `nil` when not. When it is done the status goes to `idle`.
    case processing(key: NoteKey, progress: Double?)
    /// The recording failed or was discarded; `key` is the meeting that was made, `nil` when none was.
    case failed(key: NoteKey?, reason: LiveRecordingFailure)
}

/// A plugin's live recording, shown and driven from the main window (the working ring, the "Now" row, the
/// recording panel). A plugin contributes one through `LintelPlugin.liveRecorder`; the shell hands the first
/// active plugin's recorder to the Notes section through `PluginContext.liveRecorder`.
///
/// The rules every implementation follows:
///
/// - `start()` throws a `LiveRecordingFailure` (`microphoneDenied`, `alreadyRecording`, `libraryUnavailable`,
///   `modelMissing`, `stillProcessing`, `noAudioInput`, `lowDisk` or `modelBusy`); any other error is the
///   plugin's own. Nothing is left half started.
/// - `stop(writeNotes: true)` is "Stop and Write Notes" and honours `plugins.meetings.notesEnabled` exactly as the
///   global shortcut does: with notes off, `writeNotes: true` does NOT write notes (the button is then "Stop
///   Recording"). `stop(writeNotes: false)` never writes notes.
/// - `status()` returns one stream per call. It replays the current value to its subscriber and emits on every
///   change of the recording state, including the warnings going on and off. Every stream emits `.idle` and
///   finishes on `deactivate()`, so a subscriber never holds a stream of a recorder that is gone.
/// - `retryNotes` runs the notes pipeline again for a meeting in `failed` or `partial`, and is refused with
///   `NoteSourceError.busy` while another job runs.
/// - It lives as long as the plugin's activation.
@MainActor
public protocol LiveRecorder: AnyObject, Sendable {
    /// The plugin that owns the recording (`meetings`).
    var pluginID: PluginID { get }
    func status() -> AsyncStream<LiveRecordingStatus>
    func start() async throws
    func stop(writeNotes: Bool) async
    func retryNotes(_ key: NoteKey) async throws
}

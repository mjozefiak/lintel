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
/// these notes …"). A closed set with a failable raw-value init: a value this build does not know (a provider added
/// later) reads as `nil`, so an older build shows no footer instead of guessing. Added with the notes explorer.
public enum NoteWriter: String, Sendable, Codable, CaseIterable {
    /// The built-in language model, on this Mac.
    case thisMac
    /// An external AI provider's CLI (the `claude` provider).
    case claude

    /// The writer a stored value names; `nil` for an unknown value and for `nil` or an empty string. A reader maps
    /// an unknown provider id here, never to a guess.
    public init?(reading raw: String?) {
        guard let raw, let writer = NoteWriter(rawValue: raw) else { return nil }
        self = writer
    }
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
    /// Set only together with `deletedAt`; `nil` when the source cannot say. Added with the notes explorer.
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

public struct NoteSpeaker: Sendable, Equatable {
    public var id: String
    public var name: String
    public var isSelf: Bool

    public init(id: String, name: String, isSelf: Bool = false) {
        self.id = id
        self.name = name
        self.isSelf = isSelf
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
    /// The source derives it from its own record (Meetings from `meeting.notes_provider`), never the UI. Added with
    /// the notes explorer.
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
    func content(for key: NoteKey) async throws -> NoteContent?
    func delete(_ key: NoteKey) async throws
    func actions(for key: NoteKey) -> [NoteSourceAction]
    /// One stream per call (`.bufferingNewest(1)`), finished on `deactivate()`.
    func makeChanges() -> AsyncStream<Void>
}

/// Optional capability, found with `as?`: the edits that must stay in the owner.
public protocol NoteSourceEditing: NoteSource {
    func renameTitle(_ key: NoteKey, to: String) async throws
    func renameSpeaker(_ key: NoteKey, speakerID: String, to: String) async throws
    /// Marks the speaker as the user; the owner sets its notes `stale`.
    func markSelf(_ key: NoteKey, speakerID: String) async throws
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
/// - `trash`, `restore` and `deleteNow` take at most 500 ids per call. A busy row (recording, being processed)
///   makes `trash` throw `NoteSourceError.busy` and changes nothing; it is read as no-op on a row that is already
///   trashed and `notFound` on an id the store does not have.
/// - `restore` is a no-op on a row that is not trashed, and `notFound` after the purge.
/// - `trashed(after:limit:)` pages newest-deleted first with `purgeAt` on every row.
/// - `trashAll(at:)` moves every live row that is not busy, all with the same `deleted_at`; the stamp is the
///   batch, so `restoreBatch(deletedAt:)` puts back exactly that batch and skips rows already purged or removed
///   by retention, answering how many came back. A single `trash` never reuses a batch stamp.
/// - `deleteNow` is the permanent delete (Delete Now, Empty Recently deleted).
/// - `makeChanges()` fires after trash, restore and a purge; one stream per call, finished when the plugin
///   deactivates.
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
    func restore(_ ids: [String]) async throws
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
/// - `restore` on a note that is not trashed is a no-op; after the purge it throws `NoteSourceError.notFound`
///   (the UI removes the row and says "This note was deleted permanently.").
/// - `trashed(after:limit:)` pages newest-deleted first, and every returned `NoteSummary` carries `deletedAt` and
///   `purgeAt`. `NoteSource.list` and every search never return a trashed note.
/// - `trashAll(at:)` moves every live note except busy ones, stamping all of them with exactly `at`; the stamp is
///   the batch, so `restoreBatch(deletedAt:)` puts back exactly that batch (never a note deleted earlier or later)
///   and it survives a quit. A single `trash` never reuses a batch stamp (the store adds 1 µs on a clash).
/// - `restore(_:)` is the batch restore (at most 500 keys per call); `trashedKeys(_:)` answers for at most 500
///   keys without loading the rows.
/// - `delete` keeps its meaning (permanent) and is what Delete Now and Empty call.
/// - The trash of a note never touches another store, its audio or the notes overlays; Notes marks the overlays
///   through `trashedKeys(_:)` and only the owner's purge makes a note gone.
public protocol NoteSourceTrash: NoteSource {
    /// Moves one note to Recently deleted; `NoteSourceError.notFound` when there is no such note, `.busy` while
    /// it is recording or being processed.
    func trash(_ key: NoteKey) async throws
    /// Moves every live note except the busy ones to Recently deleted, all stamped with `deletedAt`.
    func trashAll(at deletedAt: Date) async throws -> TrashBatch
    /// Puts the notes back (batch, at most 500 keys); no-op on a note that is not trashed, `notFound` after the
    /// purge.
    func restore(_ keys: [NoteKey]) async throws
    /// Puts back every note whose `deleted_at` equals the batch stamp and that still exists, answering how many
    /// came back; a note already purged or removed by retention is skipped.
    func restoreBatch(deletedAt: Date) async throws -> Int
    /// The notes that are not in Recently deleted.
    func liveCount() async throws -> Int
    /// The notes in Recently deleted.
    func trashedCount() async throws -> Int
    /// One page of Recently deleted notes, newest-deleted first, every row with `deletedAt` and `purgeAt`.
    func trashed(after: NoteCursor?, limit: Int) async throws -> NotePage
    /// Which of these keys are in Recently deleted (batch, at most 500 keys, without loading the rows). The
    /// trash sweep uses it to mark the overlays of a note deleted elsewhere (the launcher's panel, a bulk delete).
    func trashedKeys(_ keys: [NoteKey]) async throws -> Set<NoteKey>
}

// MARK: - Live recording (notes explorer, phase 1.1)

/// Why a live recording could not start, or why it failed. Each case has one sentence and one fix button in the
/// UI; any other error is the plugin's own and gets the generic sentence.
public enum LiveRecordingFailure: Error, Sendable, Equatable {
    /// The microphone permission is denied or was refused at the key press.
    case microphoneDenied
    /// A recording is already running.
    case alreadyRecording
    /// The owner's library is not open (Keychain locked or denied, the store failed): nothing was touched.
    case libraryUnavailable
    /// The speech recognition model is not on this Mac.
    case modelMissing
}

/// What a live recording is doing now, as the core toolbar, the list and the preview draw it.
public enum LiveRecordingStatus: Sendable, Equatable {
    /// How well Lintel hears the call.
    public enum Hearing: Sendable, Equatable {
        /// The user and the other people in the call.
        case everyone
        /// Only the microphone (no system audio); the UI offers "Fix Call Audio".
        case microphoneOnly
    }

    /// A problem the recording notices: set by the same timers as the HUD notices and cleared when it goes away.
    public enum Warning: Sendable, Equatable {
        /// The system track heard nothing for about 20 s.
        case silence
        /// System audio could not be recorded (permission, no tap).
        case callAudioMissing
        /// The microphone is digitally silent (about 10 s).
        case microphoneSilent
    }

    case idle
    case starting
    case recording(key: NoteKey, since: Date, hearing: Hearing, warning: Warning?)
    /// The recording stopped; the meeting is being transcribed and its notes written. `progress` is `0…1` when
    /// the owner can say, `nil` when not.
    case processing(key: NoteKey, progress: Double?)
    /// The recording or the notes failed; `key` is `nil` when no meeting was made.
    case failed(key: NoteKey?, reason: LiveRecordingFailure)
}

/// A plugin's live recording, shown and driven from the main window (the working ring, the "Now" row, the
/// recording panel). A plugin contributes one through `LintelPlugin.liveRecorder`; the shell hands the first
/// active plugin's recorder to the Notes section through `PluginContext.liveRecorder`.
///
/// The rules every implementation follows:
///
/// - `start()` throws `LiveRecordingFailure.microphoneDenied`, `.alreadyRecording`, `.libraryUnavailable` or
///   `.modelMissing`; nothing is left half started.
/// - `stop(writeNotes: true)` is "Stop and Write Notes" and honours `plugins.meetings.notesEnabled` exactly as the
///   global shortcut does (with notes off it is "Stop Recording"); `stop(writeNotes: false)` never writes notes.
/// - `status()` replays the current value to a new subscriber and emits on every change of the recording state,
///   including the warnings going on and off.
/// - `retryNotes` runs the notes pipeline again for a meeting in `failed` or `partial`, and is refused with
///   `NoteSourceError.busy` while another job runs.
/// - It lives as long as the plugin's activation; after `deactivate()` it reports `idle`.
@MainActor
public protocol LiveRecorder: AnyObject, Sendable {
    /// The plugin that owns the recording (`meetings`).
    var pluginID: PluginID { get }
    func status() -> AsyncStream<LiveRecordingStatus>
    func start() async throws
    func stop(writeNotes: Bool) async
    func retryNotes(_ key: NoteKey) async throws
}

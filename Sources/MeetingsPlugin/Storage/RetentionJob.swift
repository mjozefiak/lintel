import Foundation
import os

/// Applies the retention policy at activation and every hour: meetings older than `plugins.meetings
/// .retentionDays` (0 keeps everything) are deleted with their spool folders, expired spools of interrupted
/// meetings go (`orphanAudioDays`), and a `VACUUM` runs at most once a day. Meetings in Recently deleted are
/// deleted for good 30 days after they were deleted (spool and kept recording included; the first such purge runs
/// `firstTrashPurgeDelay` after the start), while the age rules above keep deleting by age at once, trashed rows
/// included. Transcripts never reach a log.
@MainActor
final class RetentionJob {
    static let interval: Duration = .seconds(60 * 60)
    static let vacuumInterval: TimeInterval = 24 * 60 * 60
    /// How long after the job starts the first trash purge runs. Not on the immediate pass: Notes' trash sweep runs
    /// at activation and has to mark the overlays of trashed meetings first, so a Mac that was off for 40 days
    /// purges soon after the next launch but not before that sweep.
    static let firstTrashPurgeDelay: Duration = .seconds(10 * 60)

    struct Policy: Equatable, Sendable {
        /// 0 means unlimited.
        var retentionDays: Int
        var orphanAudioDays: Int
        /// How long the audio of a `ready` meeting stays when `keepAudio` is on.
        var keptAudioDays: Int = MeetingsSettings.defaultKeptAudioDays

        func cutoff(now: Date) -> Date? {
            retentionDays > 0 ? now.addingTimeInterval(-Double(retentionDays) * 24 * 60 * 60) : nil
        }

        func keptCutoff(now: Date) -> Date {
            now.addingTimeInterval(-Double(max(1, keptAudioDays)) * 24 * 60 * 60)
        }

        func orphanCutoff(now: Date) -> Date {
            now.addingTimeInterval(-Double(max(1, orphanAudioDays)) * 24 * 60 * 60)
        }
    }

    private let clock: any Clock<Duration>
    private let now: () -> Date
    private let spool: any SpoolMaintenance
    private let logger: Logger
    private var task: Task<Void, Never>?
    private(set) var lastVacuum: Date?
    /// Meetings that must not be touched right now: live sessions and meetings being finished. Read on the
    /// main actor at the start of each pass; a finishing meeting is also `processing` in the library and its
    /// spool is freshly touched, which closes the gap between this snapshot and the deletes.
    var protectedMeetingIDs: @MainActor () -> Set<Int64> = { [] }

    init(
        clock: any Clock<Duration>, now: @escaping () -> Date = { Date() },
        spool: any SpoolMaintenance = NoSpoolMaintenance(), logger: Logger
    ) {
        self.clock = clock
        self.now = now
        self.spool = spool
        self.logger = logger
    }

    var isRunning: Bool { task != nil }

    /// Runs once now and then every hour, until `stop()`. `hourly` runs on each pass too, even while the
    /// library is unavailable (the plugin purges expired reset archives there).
    func start(
        store: @escaping @MainActor () -> MeetingsStore?, policy: @escaping @MainActor () -> Policy,
        hourly: @escaping @MainActor () -> Void = {}, changed: @escaping @MainActor () -> Void
    ) {
        stop()
        let clock = clock
        task = Task { [weak self] in
            var purgesTrash = false
            var delay = Self.firstTrashPurgeDelay
            while !Task.isCancelled {
                guard let self else { return }
                hourly()
                if let store = store(),
                    await self.run(store: store, policy: policy(), purgesTrash: purgesTrash) > 0
                {
                    changed()
                }
                do {
                    try await clock.sleep(for: delay)
                } catch {
                    return
                }
                // The pass after the first sleep is the first that purges Recently deleted; later ones are hourly.
                purgesTrash = true
                delay = Self.interval
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// One pass in the background. Returns how many meetings were deleted (by age and, when `purgesTrash`, from
    /// Recently deleted after their 30 days).
    @discardableResult
    func run(store: MeetingsStore, policy: Policy, purgesTrash: Bool = true) async -> Int {
        let now = now()
        let vacuums = lastVacuum.map { now.timeIntervalSince($0) >= Self.vacuumInterval } ?? true
        let spool = spool
        let logger = logger
        let protected = protectedMeetingIDs()
        let outcome = await Task.detached(priority: .utility) { () -> (deleted: Int, vacuumed: Bool) in
            do {
                var uuids: [String] = []
                if let cutoff = policy.cutoff(now: now) {
                    uuids = try store.applyRetention(cutoff: cutoff, excluding: protected)
                    spool.removeSpools(forMeetings: uuids)
                }
                // Recently deleted: 30 days after the delete the meeting goes for good with its audio (a restore
                // before that brings the audio back, so nothing of a trashed meeting was removed until now).
                var purged: [String] = []
                if purgesTrash {
                    purged = try store.purgeTrashed(
                        olderThan: now.addingTimeInterval(-TrashStamp.retention), excluding: protected)
                    spool.removeSpools(forMeetings: purged)
                }
                // Only interrupted meetings age out; the sweep never sees a recording or processing one, nor one
                // that is being finished.
                let candidates = Set(try store.incompleteSpoolUUIDs(excluding: protected))
                let orphans = spool.removeSpools(olderThan: policy.orphanCutoff(now: now), among: candidates)
                try store.markAudioDeleted(uuids: orphans)
                // Kept audio of a meeting that is still in the library ages out on its own clock; the
                // transcript stays.
                let keptCandidates = try store.expiredKeptSpoolUUIDs(
                    cutoff: policy.keptCutoff(now: now), excluding: protected)
                spool.removeSpools(forMeetings: keptCandidates)
                let keptGone = keptCandidates.filter { !spool.hasSpool(forMeeting: $0) }
                try store.markAudioDeleted(uuids: keptGone)
                if !uuids.isEmpty || !orphans.isEmpty || !keptGone.isEmpty || !purged.isEmpty {
                    logger.info(
                        "Retention deleted \(uuids.count, privacy: .public) meetings, purged \(purged.count, privacy: .public) from Recently deleted and removed \(orphans.count + keptGone.count, privacy: .public) old spools"
                    )
                }
                var vacuumed = false
                if vacuums, !uuids.isEmpty || !purged.isEmpty {
                    try store.vacuum()
                    vacuumed = true
                }
                return (uuids.count + purged.count, vacuumed)
            } catch MeetingsStoreError.closed {
                // The plugin deactivated while the pass ran: a quiet cancel.
                return (0, false)
            } catch {
                logger.error("Retention failed: \(String(describing: type(of: error)), privacy: .public)")
                return (0, false)
            }
        }.value
        if outcome.vacuumed {
            lastVacuum = now
        }
        return outcome.deleted
    }
}

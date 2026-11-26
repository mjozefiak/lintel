import Foundation
import LintelKit

/// The retention rules that run on store open and in each sweep (spec "Data Model", Retention): a `detached` row
/// without user writing and without an open comment (and not open in the registry) is deleted, and a `VACUUM`
/// follows at most once a day, only after something was deleted, as in Meetings and Dictation.
///
/// With `purgesTrash` (the sweeps after the first one, never the store open: notes explorer spec, Deletion
/// lifecycle) a manual note in Recently deleted for 30 days is purged too. Notes never purges another owner's
/// overlays on its own clock: they follow the owner (`exists == false`, the sweep).
extension NotesStore {
    static let vacuumInterval: TimeInterval = 24 * 60 * 60

    /// Deletes the leftover detached rows (and, with `purgesTrash`, the manual notes trashed 30 days ago or more)
    /// and vacuums when one day has passed since the last `VACUUM`. A failed `VACUUM` never fails the deletion.
    /// Returns how many detached rows and purged notes were deleted.
    @discardableResult
    func applyRetention(excluding openDocIDs: Set<Int64> = [], now: Date, purgesTrash: Bool = false) throws -> Int {
        let result = try applyRetentionReporting(excluding: openDocIDs, now: now, purgesTrash: purgesTrash)
        return result.detached + result.purged.count
    }

    /// `applyRetention`, saying apart the leftover detached rows and the purged manual notes (whose Recently
    /// deleted changed, so its change stream fires).
    func applyRetentionReporting(excluding openDocIDs: Set<Int64> = [], now: Date, purgesTrash: Bool = false) throws
        -> (detached: Int, purged: [NoteKey])
    {
        let detached = try deleteUnkeptDetached(excluding: openDocIDs)
        let purged = purgesTrash ? try purgeTrashedManualNotes(now: now, excluding: openDocIDs) : []
        if detached > 0 || !purged.isEmpty { vacuumIfDue(now: now) }
        return (detached, purged)
    }

    /// `VACUUM` unless one ran less than a day ago. The time is taken before the call, so two callers never both
    /// vacuum, and given back when the `VACUUM` fails.
    @discardableResult
    func vacuumIfDue(now: Date) -> Bool {
        let previous: Date?? = lastVacuum.withLock { last in
            if let last, now.timeIntervalSince(last) < Self.vacuumInterval { return nil }
            let before = last
            last = now
            return .some(before)
        }
        guard let previous else { return false }
        do {
            try vacuum()
            return true
        } catch {
            lastVacuum.withLock { $0 = previous }
            return false
        }
    }
}

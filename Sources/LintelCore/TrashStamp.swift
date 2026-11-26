import Foundation

/// How a `deleted_at` column of Recently deleted is written and compared (notes explorer spec, Deletion
/// lifecycle). Meetings, Dictation and Notes keep their trash in their own databases and share this one rule, so a
/// stamp one of them writes means the same to the others and to the sweep that copies it.
///
/// The column is a REAL in Unix seconds. A bulk move stamps every row with one value and `restoreBatch` finds
/// the batch by equality, so one conversion rules every write and every comparison: the time is rounded to a
/// whole microsecond, stored as `micros / 1e6` and compared through `CAST(ROUND(deleted_at * 1e6) AS INTEGER)`
/// (`microsSQL`). A stamp read back after the database is reopened therefore equals the one written: the Double
/// ulp at this magnitude, about 0.24 µs, is far below the half microsecond the rounding tolerates. A single trash
/// never reuses another row's batch stamp: on a clash the store moves its stamp on by 1 µs.
///
/// Pure value logic, no I/O. Each plugin adds its own `purgeAt` (the retention limit it knows about) in an
/// extension.
public enum TrashStamp {
    /// How long a row stays in Recently deleted before it is purged.
    public static let retention: TimeInterval = 30 * 24 * 60 * 60

    /// The SQL expression that reads a `deleted_at` column as whole microseconds.
    public static let microsSQL = "CAST(ROUND(deleted_at * 1000000) AS INTEGER)"

    /// The date rounded to a whole microsecond.
    public static func micros(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000_000).rounded())
    }

    /// The value the column holds for these microseconds.
    public static func column(micros: Int64) -> Double { Double(micros) / 1_000_000 }

    /// The microseconds a column value stands for.
    public static func micros(column: Double) -> Int64 { Int64((column * 1_000_000).rounded()) }

    public static func date(micros: Int64) -> Date { Date(timeIntervalSince1970: column(micros: micros)) }

    public static func date(column: Double) -> Date { date(micros: micros(column: column)) }

    /// When a row deleted at `deletedAt` is purged when only the 30 days count.
    public static func purgeAt(deletedAt: Date) -> Date { deletedAt.addingTimeInterval(retention) }

    /// When a row deleted at `deletedAt` is gone for good: the earlier of 30 days after the delete and the row's
    /// retention limit (`limitStart` + `retentionDays`; 0 means no limit, so only the 30 days count).
    public static func purgeAt(deletedAt: Date, limitStart: Date, retentionDays: Int) -> Date {
        let thirty = purgeAt(deletedAt: deletedAt)
        guard retentionDays > 0 else { return thirty }
        return min(thirty, limitStart.addingTimeInterval(Double(retentionDays) * 24 * 60 * 60))
    }
}

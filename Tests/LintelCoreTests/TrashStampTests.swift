import Foundation
import Testing

@testable import LintelCore

/// The one stamp rule of Recently deleted (Meetings, Dictation and Notes share it).
@Suite struct TrashStampTests {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    @Test func aDateIsRoundedToAWholeMicrosecond() {
        // Sub-microsecond noise rounds to the nearest microsecond, up and down (a Double at this magnitude has a
        // step of about 0.24 µs, so the noise stays clear of the half-microsecond boundary).
        #expect(TrashStamp.micros(Date(timeIntervalSince1970: 1_800_000_000.123_456_2)) == 1_800_000_000_123_456)
        #expect(TrashStamp.micros(Date(timeIntervalSince1970: 1_800_000_000.123_456_8)) == 1_800_000_000_123_457)
        #expect(TrashStamp.micros(base) == 1_800_000_000_000_000)
    }

    @Test func theColumnValueAndTheDateAgreeBothWays() {
        let micros: Int64 = 1_800_000_100_987_654
        #expect(TrashStamp.column(micros: micros) == 1_800_000_100.987_654)
        #expect(TrashStamp.micros(column: TrashStamp.column(micros: micros)) == micros)
        #expect(TrashStamp.micros(TrashStamp.date(micros: micros)) == micros)
        #expect(TrashStamp.micros(TrashStamp.date(column: 1_800_000_100.987_654)) == micros)
    }

    @Test func aStampWrittenAndReadBackIsTheSameMicrosecond() {
        // What a store does: write `column(micros:)`, read it back, compare through `micros(column:)`.
        for noise in [0.123_456_789, 0.987_654_321, 0.000_000_4, 0.999_999_6] {
            let date = Date(timeIntervalSince1970: 1_800_000_000 + noise)
            let written = TrashStamp.micros(date)
            let readBack = TrashStamp.date(column: TrashStamp.column(micros: written))
            #expect(TrashStamp.micros(readBack) == written)
        }
    }

    @Test func aClashIsMovedOnByOneMicrosecond() {
        // The stores move a single trash that would reuse a batch stamp on by 1 µs: the next stamp is a different
        // value, and it is exactly one microsecond later.
        let batch = TrashStamp.micros(base)
        let moved = TrashStamp.date(micros: batch + 1)
        #expect(TrashStamp.micros(moved) == batch + 1)
        #expect(TrashStamp.micros(moved) != batch)
        #expect(moved.timeIntervalSince(TrashStamp.date(micros: batch)) > 0)
    }

    @Test func theSQLExpressionReadsTheColumnAsWholeMicroseconds() {
        #expect(TrashStamp.microsSQL == "CAST(ROUND(deleted_at * 1000000) AS INTEGER)")
    }

    @Test func aNoteIsPurgedThirtyDaysAfterItsDeletion() {
        #expect(TrashStamp.retention == 30 * day)
        #expect(TrashStamp.purgeAt(deletedAt: base) == base.addingTimeInterval(30 * day))
    }

    @Test func theRetentionLimitWinsOnlyWhenItComesFirstAndZeroMeansNoLimit() {
        let deleted = base.addingTimeInterval(10 * day)
        // No limit: only the 30 days count.
        #expect(
            TrashStamp.purgeAt(deletedAt: deleted, limitStart: base, retentionDays: 0)
                == deleted.addingTimeInterval(30 * day))
        // A limit that ends before the 30 days: it wins.
        #expect(
            TrashStamp.purgeAt(deletedAt: deleted, limitStart: base, retentionDays: 20)
                == base.addingTimeInterval(20 * day))
        // A limit that ends after the 30 days: the 30 days win.
        #expect(
            TrashStamp.purgeAt(deletedAt: deleted, limitStart: base, retentionDays: 90)
                == deleted.addingTimeInterval(30 * day))
    }
}

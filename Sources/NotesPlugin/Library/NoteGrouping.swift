import Foundation
import LintelKit

/// How the explorer groups rows (`plugins.notes.grouping`).
enum NoteGrouping: String, Sendable, CaseIterable {
    case time
    case source
    /// The notes explorer's list (spec `2026-11-24-notes-explorer-main-window`): Today, Yesterday, the weekday for the
    /// rest of the week, then one group per date.
    case day
}

/// The identity of a group. Titles are the UI's (step 3.2), so no string lives here.
enum NoteGroupKey: Hashable, Sendable {
    case today
    case yesterday
    case previousSevenDays
    case previousThirtyDays
    case earlier
    /// By plugin: Meetings, Dictation, Notes, then any other.
    case source(PluginID)
    /// A calendar day that is neither today nor yesterday (the start of that day in the injected calendar).
    case day(Date)
}

struct NoteGroup: Sendable, Equatable, Identifiable {
    var key: NoteGroupKey
    var rows: [NoteRow]
    var id: NoteGroupKey { key }
}

/// Pure: puts rows into groups, each group newest first, empty groups left out.
enum NoteGroupingRules {
    static let sourceOrder: [PluginID] = ["meetings", "dictation", "notes"]

    static func group(
        _ rows: [NoteRow], by grouping: NoteGrouping, now: Date, calendar: Calendar = .current
    ) -> [NoteGroup] {
        let sorted = rows.sorted { NoteSortPosition($0).isBefore(NoteSortPosition($1)) }
        switch grouping {
        case .time:
            let order: [NoteGroupKey] = [.today, .yesterday, .previousSevenDays, .previousThirtyDays, .earlier]
            var buckets: [NoteGroupKey: [NoteRow]] = [:]
            for row in sorted {
                buckets[timeKey(row.startedAt, now: now, calendar: calendar), default: []].append(row)
            }
            return order.compactMap { key in buckets[key].map { NoteGroup(key: key, rows: $0) } }
        case .day:
            var order: [NoteGroupKey] = []
            var buckets: [NoteGroupKey: [NoteRow]] = [:]
            for row in sorted {
                let key = dayKey(row.startedAt, now: now, calendar: calendar)
                if buckets[key] == nil { order.append(key) }
                buckets[key, default: []].append(row)
            }
            return order.compactMap { key in buckets[key].map { NoteGroup(key: key, rows: $0) } }
        case .source:
            var buckets: [PluginID: [NoteRow]] = [:]
            for row in sorted { buckets[row.pluginID, default: []].append(row) }
            let known = sourceOrder.filter { buckets[$0] != nil }
            let others = buckets.keys.filter { !sourceOrder.contains($0) }.sorted { $0.rawValue < $1.rawValue }
            return (known + others).compactMap { id in
                buckets[id].map { NoteGroup(key: .source(id), rows: $0) }
            }
        }
    }

    /// One group per calendar day: today and yesterday by name, any other day by its start. A date in the future
    /// (a clock change) counts as today.
    static func dayKey(_ date: Date, now: Date, calendar: Calendar) -> NoteGroupKey {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        switch days {
        case ..<1: return .today
        case 1: return .yesterday
        default: return .day(day)
        }
    }

    /// Calendar days, not 24-hour spans: a note from late yesterday is "yesterday" at 00:05. A date in the
    /// future (a clock change) counts as today.
    static func timeKey(_ date: Date, now: Date, calendar: Calendar) -> NoteGroupKey {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        switch days {
        case ..<1: return .today
        case 1: return .yesterday
        case 2...7: return .previousSevenDays
        case 8...30: return .previousThirtyDays
        default: return .earlier
        }
    }
}

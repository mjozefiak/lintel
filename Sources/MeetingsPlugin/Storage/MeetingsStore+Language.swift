import Foundation
import GRDB

/// A stored segment with its text, what the language repair looks at. The text is never logged.
struct StoredSegment: Equatable, Sendable {
    let id: Int64
    let channel: AudioChannel
    let startMs: Int
    let endMs: Int
    let text: String

    var duration: TimeInterval { Double(max(0, endMs - startMs)) / 1_000 }
}

/// Reads for the language repair (spec `2026-11-23-automatic-language-detection`, step 2.4). Replacements are
/// written with `setSegmentText`, whose trigger keeps the transcript index current.
extension MeetingsStore {
    /// The meeting's segments with their text, in time order.
    func languageSegments(meetingID: Int64) throws -> [StoredSegment] {
        try read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, channel, start_ms, end_ms, text FROM meeting_segment
                    WHERE meeting_id = ? ORDER BY start_ms, id
                    """, arguments: [meetingID]
            ).compactMap { row -> StoredSegment? in
                let name: String = row["channel"]
                guard let channel = AudioChannel(rawValue: name) else { return nil }
                return StoredSegment(
                    id: row["id"], channel: channel, startMs: row["start_ms"], endMs: row["end_ms"],
                    text: row["text"])
            }
        }
    }
}

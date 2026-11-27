import AppKit
import LintelKit
import LintelUI

/// A name the owner suggests for a speaker ("Marek?"), waiting for Yes or No (speaker names, step 1.6b).
struct SpeakerNameSuggestion: Equatable, Sendable {
    var speakerID: String
    /// The suggested name as the source gave it; Yes and No send it back, so a stale screen is refused.
    var name: String
}

/// The width of the transcript's speaker column for one set of names and one text size.
struct SpeakerColumnCache {
    var names: [String]
    var scale: CGFloat
    var width: CGFloat
}

extension NoteDocumentModel {
    /// The first block of every speaker, in the order of `blocks`.
    static func firstBlocks(of blocks: [NoteBlock]) -> [String: Int] {
        var result: [String: Int] = [:]
        for block in blocks {
            guard let speaker = block.speakerID, result[speaker] == nil else { continue }
            result[speaker] = block.index
        }
        return result
    }

    /// The suggestion shown under a transcript block: only under the speaker's first block, only for a speaker
    /// whose name is `suggested` with a suggestion, only on a live note whose source can answer it, and only when
    /// the workspace wired the answer. A detached note ("Recording removed") keeps the seed's speakers, which carry
    /// no suggestion, so it never shows one.
    func speakerSuggestion(at block: NoteBlock) -> SpeakerNameSuggestion? {
        guard layerID == Self.transcriptLayerID, canEditSpeakers, answerSpeakerSuggestion != nil,
            case .live = id, let speakerID = block.speakerID, firstBlockOfSpeaker[speakerID] == block.index,
            let speaker = speakers.first(where: { $0.id == speakerID }), speaker.nameStatus == .suggested,
            let name = speaker.suggestion, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return SpeakerNameSuggestion(speakerID: speakerID, name: name)
    }

    /// Yes or No on a suggestion; the handler sends nothing while an answer for this note is still on its way.
    func answer(_ suggestion: SpeakerNameSuggestion, confirm: Bool) {
        answerSpeakerSuggestion?(suggestion.speakerID, suggestion.name, confirm)
    }

    // MARK: Speaker column (#362)

    /// The smallest column: the prototype's width, which fits a short first name.
    static func minimumSpeakerColumn(scale: CGFloat) -> CGFloat { 5.5 * 12.5 * scale }
    /// The widest column: a longer name wraps inside it instead of pushing the words to the right.
    static func maximumSpeakerColumn(scale: CGFloat) -> CGFloat { 13 * 12.5 * scale }

    /// A column as wide as the longest name (measured in the bold callout font of the text size, plus a little
    /// room for the difference between AppKit's measure and SwiftUI's drawing), never narrower than the minimum
    /// and never wider than the maximum.
    static func speakerColumnWidth(names: [String], font: NSFont, scale: CGFloat) -> CGFloat {
        let widest = names.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let slack: CGFloat = 4 * scale
        return min(
            maximumSpeakerColumn(scale: scale), max(minimumSpeakerColumn(scale: scale), (widest + slack).rounded(.up)))
    }

    /// The column width for the shown speakers at this text size, measured once per set of names and size.
    func speakerColumnWidth(textSize: TextSize) -> CGFloat {
        let names = speakers.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if let cache = speakerColumnCache, cache.names == names, cache.scale == textSize.scale { return cache.width }
        let base = textSize.nsFont(.callout)
        let font = NSFont.systemFont(ofSize: base.pointSize, weight: .bold)
        let width = Self.speakerColumnWidth(names: names, font: font, scale: textSize.scale)
        speakerColumnCache = SpeakerColumnCache(names: names, scale: textSize.scale, width: width)
        return width
    }
}

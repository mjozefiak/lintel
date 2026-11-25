import Foundation

/// The audio a speech range is sent with. The voice activity detector reports ranges at the resolution of its
/// 256 ms chunks, opening one at the first chunk that reaches the entry threshold and closing it at the first
/// quiet chunk, so the edge of a word can lie just outside it. The engine gets a little more audio on each side
/// (issue #135); the range of the transcript segment is the widened one.
enum SegmentWindow {
    /// What the live session and the resumer add before and after a detected range (issue #135).
    static let preRoll: Duration = .milliseconds(300)
    static let postRoll: Duration = .milliseconds(200)

    /// `detected` widened by `preRoll` samples before and `postRoll` after.
    /// - Parameters:
    ///   - notBefore: the end of the audio already sent; the widening never reaches back into it, so a word is
    ///     not transcribed twice (the range itself is never narrowed to keep that promise).
    ///   - received: samples that exist; the widening never runs past them.
    ///   - longest: the engine's window; the widened range is never longer (past it FluidAudio splits the audio
    ///     into two windows with a seam). The margins give way first, the one before the speech before the one
    ///     after it; the detected range itself is never cut.
    static func widened(
        _ detected: Range<Int>, notBefore: Int, received: Int, preRoll: Int, postRoll: Int,
        longest: Int = MeetingSession.longestSegment
    ) -> Range<Int> {
        guard !detected.isEmpty else { return detected }
        var lower = min(detected.lowerBound, max(notBefore, detected.lowerBound - max(0, preRoll)))
        var upper = max(detected.upperBound, min(received, detected.upperBound + max(0, postRoll)))
        var excess = max(0, (upper - lower) - max(longest, detected.count))
        let trimmedBefore = min(excess, detected.lowerBound - lower)
        lower += trimmedBefore
        excess -= trimmedBefore
        upper -= min(excess, upper - detected.upperBound)
        return max(0, lower)..<upper
    }

    /// Where a range that has outgrown the engine's window is cut. The piece is cut so that, with its pre-roll,
    /// it is exactly `longest` long: the first piece of a long utterance keeps its pre-roll too, and the
    /// continuation starts at the cut. Never earlier than `start` (so the piece is never empty) and never later
    /// than `start + longest`.
    static func cutEnd(
        start: Int, notBefore: Int, preRoll: Int, longest: Int = MeetingSession.longestSegment
    ) -> Int {
        let lower = min(start, max(notBefore, start - max(0, preRoll)))
        return max(start + 1, lower + longest)
    }
}

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
    static func widened(_ detected: Range<Int>, notBefore: Int, received: Int, preRoll: Int, postRoll: Int)
        -> Range<Int>
    {
        guard !detected.isEmpty else { return detected }
        let lower = min(detected.lowerBound, max(notBefore, detected.lowerBound - max(0, preRoll)))
        let upper = max(detected.upperBound, min(received, detected.upperBound + max(0, postRoll)))
        return max(0, lower)..<upper
    }
}

import LintelSpeech

/// The voice activity detector settings of the meeting recorder, in one place for the live session and the
/// resumer (dictation keeps FluidAudio's defaults).
enum MeetingVAD {
    /// Silero's own recommended hysteresis (speech opens at 0.5 and ends below 0.35) instead of FluidAudio's 0.85
    /// and 0.70. A remote speaker who is quiet or short produced no chunk at 0.85 and so no segment at all
    /// (issue #135); at 0.5 the words that were never sent drop to a third on Polish test speech and to half on
    /// quiet English (`scripts/meeting-eval/score_loss.py`, numbers in the pull request).
    static let tuning = VADTuning(entryThreshold: 0.5, exitOffset: 0.15, minSilence: 0.75, padding: 0.1)
}

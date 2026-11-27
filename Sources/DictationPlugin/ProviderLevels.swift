import Foundation

/// The cleanup levels an external AI provider serves for dictation (spec `2026-11-25-dictation-cleanup-levels`, "Source ×
/// level" and A12). A compile-time constant, like `DictationSettings.fullIsOffered`.
///
/// **Owner decision 2026-11-26:** `[.standard, .full]`. The owner wants the choice between this Mac and the provider
/// at both levels. Phase 4 measured Claude Code (Sonnet) from the key release: Standard's p90 is 3.30 s over all 160
/// dictations and its worst case on the corpus is 5.76 s, so both levels wait 6 s (owner decision 2026-11-27; Standard
/// was 4 s, which cut that tail). Full on the provider misses three corpus targets against Standard on the provider
/// (terms hit, `code` WER, one short item with a line break); whether it stays offered waits for the Full v2 round.
///
/// When a level is not in the set, a provider source runs that level locally (`DictationSettings.effectiveSource`), and
/// the pane says so in words (`ProviderFallbackLine`). With both levels offered that line never shows; the mechanism is
/// kept and tested because the constant can change.
enum ProviderLevels {
    static let offered: Set<DictationSettings.CleanupLevel> = [.standard, .full]

    /// How long after the key release the session waits for the provider's chunks still out (spec A10, A11, owner decisions
    /// 2026-11-26 and 2026-11-27: 6 s at both levels, Standard's 4 s raised so its measured worst case comes back tidied).
    /// `nil` for the levels that do not run on a provider.
    static func releaseDeadline(for level: DictationSettings.CleanupLevel) -> Duration? {
        switch level {
        case .light: nil
        case .standard: .seconds(6)
        case .full: .seconds(6)
        }
    }
}

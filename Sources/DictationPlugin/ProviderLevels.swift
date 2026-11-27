import Foundation

/// The cleanup levels an external AI provider serves for dictation (spec `2026-11-25-dictation-cleanup-levels`, "Source ×
/// level" and A12). A compile-time constant, like `DictationSettings.fullIsOffered`.
///
/// **Owner decision 2026-11-26:** `[.standard, .full]`. The owner wants the choice between this Mac and the provider
/// at both levels. Phase 4 measured Claude Code (Sonnet): Standard fails the first proposal's 2 s but its p90 from the
/// key release is 3.30 s over all 160 dictations, so the limit is 4 s (`ProviderLevels.releaseDeadline`); Full is under
/// 6 s. Full on the provider misses three corpus targets against Standard on the provider (terms hit, `code` WER, one
/// short item with a line break); whether it stays offered waits for the Full v2 round.
///
/// When a level is not in the set, a provider source runs that level locally (`DictationSettings.effectiveSource`), and
/// the pane says so in words (`ProviderFallbackLine`). With both levels offered that line never shows; the mechanism is
/// kept and tested because the constant can change.
enum ProviderLevels {
    static let offered: Set<DictationSettings.CleanupLevel> = [.standard, .full]

    /// How long after the key release the session waits for the provider's chunks still out (spec A10, A11, owner decision
    /// 2026-11-26). `nil` for the levels that do not run on a provider.
    static func releaseDeadline(for level: DictationSettings.CleanupLevel) -> Duration? {
        switch level {
        case .light: nil
        case .standard: .seconds(4)
        case .full: .seconds(6)
        }
    }
}

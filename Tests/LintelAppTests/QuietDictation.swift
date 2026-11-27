import Foundation
import LintelProviders
import Testing

@testable import DictationPlugin

/// The shell builds `DictationPlugin` from its type too, so its cleanup provider (spec
/// `2026-11-25-dictation-cleanup-levels`, Phase 5) cannot be handed a fake by each test: every environment that builds
/// plugins installs the quiet one, which looks for and starts no real CLI. `QuietMeetings.install()` calls this.
enum QuietDictation {
    static func install() {
        DictationProviders.standard = .quiet
        #expect(!DictationProviders.liveWasUsed, "a test built the live provider system of dictation")
    }
}

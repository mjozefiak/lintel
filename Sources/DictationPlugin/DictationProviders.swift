import Foundation
import LintelProviders
import Synchronization

/// What reaches an external provider's CLI from dictation: the one place the live runner is made (spec
/// `2026-11-25-dictation-cleanup-levels`, Phase 5; Meetings' `MeetingsSystem.makeProviderRunner` is the same idea).
/// `live` is the app's; tests install `quiet`, which starts nothing, in every environment that builds the plugin.
///
/// The runner is made on first use (a formatter that runs content, or a status check while the pane shows the source
/// row), never when the plugin is built: a user who never chooses a provider starts no process and builds no system.
struct DictationProviders: Sendable {
    var makeRunner: @Sendable (_ cachesDirectory: URL) -> ProviderRunner

    static let live = DictationProviders { cachesDirectory in
        liveUse.withLock { $0 = true }
        return ProviderRunner(
            system: ProviderSystem.live(homeDirectory: FileManager.default.homeDirectoryForCurrentUser),
            cachesDirectory: cachesDirectory)
    }

    /// A fake binary and a fake process: nothing real starts.
    static let quiet = DictationProviders { cachesDirectory in
        ProviderRunner(system: .quiet, cachesDirectory: cachesDirectory)
    }

    private static let standardValue = Mutex(DictationProviders.live)
    private static let liveUse = Mutex(false)

    /// What `DictationPlugin.init` uses: `live` in the app.
    static var standard: DictationProviders {
        get { standardValue.withLock { $0 } }
        set { standardValue.withLock { $0 = newValue } }
    }

    /// Whether the live system was made in this process (a test of `quiet` checks it did not).
    static var liveWasUsed: Bool { liveUse.withLock { $0 } }
}

/// The runner, made once and only when something needs it.
final class ProviderRunnerHolder: Sendable {
    private let make: @Sendable () -> ProviderRunner
    private let made = Mutex<ProviderRunner?>(nil)

    init(providers: DictationProviders, cachesDirectory: URL) {
        make = { providers.makeRunner(cachesDirectory) }
    }

    var runner: ProviderRunner {
        made.withLock { value in
            if let value { return value }
            let runner = make()
            // A crash can leave `provider-*` working folders behind; the first use of the runner removes them.
            runner.sweepStaleWorkspaces()
            value = runner
            return runner
        }
    }

    /// Whether the runner was made (the status row asked, or a dictation ran on the provider).
    var wasMade: Bool { made.withLock { $0 != nil } }
}

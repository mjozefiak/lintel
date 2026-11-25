import Foundation
import Testing

@testable import MeetingsPlugin

/// Which app a process that uses an input belongs to, and the notes the policy leaves for the log.
@Suite struct MeetingDetectionMatchingTests {
    private let chrome = SuggestionConfig(
        enabled: true, extraBundleIDs: ["com.google.Chrome", "org.mozilla.firefox"], ownBundleID: "com.lintelapp")

    private func event(
        _ process: UInt32, _ bundleID: String?, responsible: String? = nil, running: Bool = true
    ) -> ProcessAudioEvent {
        ProcessAudioEvent(
            processObjectID: process, bundleID: bundleID, isRunningInput: running, responsibleBundleID: responsible)
    }

    private func suggestions(_ policy: inout SuggestionPolicy, at seconds: Double, config: SuggestionConfig? = nil)
        -> [SuggestionPolicy.Effect]
    {
        policy.evaluate(now: .seconds(seconds), config: config ?? chrome, isBusy: false)
    }

    // MARK: Matching

    @Test func chromesHelperProcessesBelongToChrome() {
        // What Core Audio reports on this Mac for Chrome (measured with a probe on 2026-11-25).
        for id in ["com.google.Chrome", "com.google.Chrome.helper", "com.google.Chrome.helper.Renderer"] {
            var policy = SuggestionPolicy()
            policy.handle(event(1, id), now: .zero, config: chrome)
            #expect(suggestions(&policy, at: 10) == [.suggest(bundleID: "com.google.Chrome")], "\(id)")
        }
    }

    @Test func aHelperWhoseOwnIDHasAnotherPrefixBelongsToTheAppItLivesIn() {
        var policy = SuggestionPolicy()
        policy.handle(
            event(1, "org.mozilla.plugincontainer", responsible: "org.mozilla.firefox"), now: .zero, config: chrome)
        #expect(suggestions(&policy, at: 10) == [.suggest(bundleID: "org.mozilla.firefox")])
    }

    @Test func aProcessWithoutABundleIDIsMatchedByTheAppItLivesIn() {
        var policy = SuggestionPolicy()
        policy.handle(event(1, nil, responsible: "com.google.Chrome"), now: .zero, config: chrome)
        #expect(suggestions(&policy, at: 10) == [.suggest(bundleID: "com.google.Chrome")])
    }

    @Test func aProcessThatBelongsToNoListedAppIsIgnored() {
        var policy = SuggestionPolicy()
        policy.handle(event(1, "com.example.recorder", responsible: "com.example.recorder"), now: .zero, config: chrome)
        policy.handle(event(2, nil), now: .zero, config: chrome)
        #expect(suggestions(&policy, at: 60).isEmpty)
    }

    @Test func theResponsibleAppDoesNotOverrideAListedBundleID() {
        // Slack's helper lives in Slack.app: the process's own ID already matches.
        var policy = SuggestionPolicy()
        policy.handle(
            event(1, "com.tinyspeck.slackmacgap.helper", responsible: "com.tinyspeck.slackmacgap"), now: .zero,
            config: chrome)
        #expect(suggestions(&policy, at: 10) == [.suggest(bundleID: "com.tinyspeck.slackmacgap")])
    }

    @Test func theStopOfAHelperIsAttributedToItsApp() {
        var policy = SuggestionPolicy()
        policy.handle(event(1, nil, responsible: "com.google.Chrome"), now: .zero, config: chrome)
        policy.handle(event(1, nil, running: false), now: .seconds(5), config: chrome)
        // Used for 5 s only: nothing at 10 s.
        #expect(suggestions(&policy, at: 10).isEmpty)
    }

    // MARK: Notes for the log

    @Test func everyStartOfInputUseLeavesANoteWithTheListedApp() {
        var policy = SuggestionPolicy()
        policy.handle(event(1, "com.google.Chrome.helper"), now: .zero, config: chrome)
        policy.handle(event(2, "com.example.recorder", responsible: "com.example.recorder"), now: .zero, config: chrome)
        #expect(
            policy.drainNotes() == [
                .inputStarted(reported: "com.google.Chrome.helper", responsible: nil, listed: "com.google.Chrome"),
                .inputStarted(
                    reported: "com.example.recorder", responsible: "com.example.recorder", listed: nil),
            ])
        #expect(policy.drainNotes().isEmpty)
    }

    @Test func aSuggestionAndTheEndOfUseAreNoted() {
        var policy = SuggestionPolicy()
        policy.handle(event(1, "com.google.Chrome.helper"), now: .zero, config: chrome)
        _ = policy.drainNotes()
        _ = suggestions(&policy, at: 10)
        #expect(policy.drainNotes() == [.suggested(app: "com.google.Chrome")])
        policy.handle(event(1, nil, running: false), now: .seconds(60), config: chrome)
        #expect(policy.drainNotes() == [.inputEnded(app: "com.google.Chrome")])
    }

    @Test(arguments: [
        (true, false, false, SuggestionPolicy.SkipReason.busy), (true, true, false, .muted),
        (false, false, false, .disabled),
    ])
    func aSkippedSuggestionSaysWhy(enabled: Bool, muted: Bool, busy: Bool, reason: SuggestionPolicy.SkipReason) {
        var config = chrome
        config.enabled = enabled
        config.mutedBundleIDs = muted ? ["com.google.Chrome"] : []
        // `busy` is the third tuple field only to keep the table readable: busy is the first row's reason.
        let isBusy = reason == .busy
        _ = busy
        var policy = SuggestionPolicy()
        policy.handle(event(1, "com.google.Chrome.helper"), now: .zero, config: config)
        _ = policy.drainNotes()
        #expect(policy.evaluate(now: .seconds(10), config: config, isBusy: isBusy).isEmpty)
        #expect(policy.drainNotes() == [.skipped(app: "com.google.Chrome", reason: reason)])
    }

    @Test func anAppThatWaitsForTheSuggestionOnScreenIsNotedOncePerUse() {
        var policy = SuggestionPolicy()
        policy.handle(event(1, "com.google.Chrome.helper"), now: .zero, config: chrome)
        _ = policy.drainNotes()
        #expect(policy.evaluate(now: .seconds(10), config: chrome, isBusy: false, canSuggest: false).isEmpty)
        #expect(policy.evaluate(now: .seconds(12), config: chrome, isBusy: false, canSuggest: false).isEmpty)
        #expect(policy.drainNotes() == [.waiting(app: "com.google.Chrome")])
        #expect(policy.evaluate(now: .seconds(13), config: chrome, isBusy: false).count == 1)
    }

    // MARK: Responsible app

    @Test func theOutermostAppInAnExecutablePathIsTheResponsibleApp() {
        let path =
            "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/158/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"
        #expect(ResponsibleApp.bundlePath(inExecutablePath: path) == "/Applications/Google Chrome.app")
        #expect(
            ResponsibleApp.bundlePath(inExecutablePath: "/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal")
                == "/Applications/Utilities/Terminal.app")
    }

    @Test func aProcessOutsideAnyAppHasNoResponsibleApp() {
        let service =
            "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.GPU.xpc/Contents/MacOS/com.apple.WebKit.GPU"
        #expect(ResponsibleApp.bundlePath(inExecutablePath: service) == nil)
        #expect(ResponsibleApp.bundlePath(inExecutablePath: "") == nil)
        #expect(ResponsibleApp.bundlePath(inExecutablePath: "/usr/bin/true") == nil)
    }
}

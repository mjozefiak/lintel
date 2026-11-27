import Foundation
import LintelKit
import LintelProviders
import LintelTestSupport
import Testing

@testable import DictationPlugin

/// Spec `2026-11-25-dictation-cleanup-levels`, Phase 5, owner decision 2026-11-27: Claude is in the "Tidy up with" menu
/// from its descriptor alone, with nothing started, and the CLI's two probes (`--version`, `auth status`) run only once
/// the user chose it. The counter stands for the probes; no process is made here.
@MainActor
@Suite(.serialized) struct ProviderProbeTests {
    private struct Rig {
        let model: FormattingSettingsModel
        let settings: DictationSettings
        let probes: CountLatch
    }

    /// The settings of a user who chose Claude at Standard: the menu's choice writes all three keys.
    private static let chosen: [String: SettingValue] = [
        "plugins.dictation.mode": .string("cleanup"),
        "plugins.dictation.llmSource": .string("provider"),
        "plugins.dictation.provider": .string("claude-code"),
    ]

    /// The second answer differs from the first, so a test can see the forced probe land; a state that is not ready is
    /// looked at again on every refresh (the interval covers only a working provider).
    private func rig(
        _ values: [String: SettingValue] = [:], first: ProviderStatus = .ready, later: ProviderStatus = .notSignedIn
    ) -> Rig {
        let settings = DictationSettings(
            PluginSettings(pluginID: "dictation", store: MemorySettingsStore(values)), offersFull: true)
        let probes = CountLatch()
        let model = FormattingSettingsModel(
            settings: settings, transport: ScriptedTransport(.content("x")),
            providerStatus: { _ in
                let call = probes.increment()
                return ProviderStatusReport(status: call == 1 ? first : later, version: nil)
            })
        return Rig(model: model, settings: settings, probes: probes)
    }

    @Test func theProviderIsInTheMenuWithoutStartingAnyProbe() async {
        let rig = rig()
        rig.model.choice = .standard
        await rig.model.refresh()
        #expect(rig.model.providerIsListed)
        #expect(rig.probes.count == 0)
        #expect(rig.model.providerReadiness == nil)
    }

    @Test func aChosenProviderIsProbedOnceAndAgainOnCheckAgain() async {
        let rig = rig(Self.chosen)
        await rig.model.refresh()
        #expect(rig.probes.count == 1)
        #expect(rig.model.providerReadiness == .ready)
        // A working provider is looked at again only after the interval.
        await rig.model.refresh()
        #expect(rig.probes.count == 1)
        rig.model.checkProviderAgain()
        await rig.probes.wait(atLeast: 2, "the forced check")
        await waitForObserved("the forced check's answer") { rig.model.providerReadiness == .notSignedIn }
        #expect(rig.probes.count == 2)
    }

    @Test func choosingTheProviderInTheMenuStartsTheProbeAtOnce() async {
        let rig = rig()
        rig.model.choice = .standard
        rig.model.source = .provider
        await rig.model.refresh()
        #expect(rig.model.isProvider)
        #expect(rig.settings.providerSelection != nil)
        #expect(rig.probes.count == 1)
    }

    @Test func choosingAnotherSourceStopsTheProbing() async {
        // A provider that does not work is checked on every refresh, so a second probe would show at once.
        let rig = rig(Self.chosen, first: .notSignedIn, later: .notSignedIn)
        await rig.model.refresh()
        #expect(rig.probes.count == 1)
        rig.model.source = .server
        await rig.model.refresh()
        await rig.model.refresh()
        #expect(!rig.model.isProvider)
        #expect(rig.probes.count == 1)
    }

    @Test func aStoredProviderSourceWithoutAChoiceProbesNothing() async {
        // An older build or a hand-edited default: the source says provider, no provider is chosen, so a level runs on
        // the local fallback and nothing starts.
        let rig = rig([
            "plugins.dictation.mode": .string("cleanup"),
            "plugins.dictation.llmSource": .string("provider"),
        ])
        await rig.model.refresh()
        #expect(!rig.model.isProvider)
        #expect(rig.probes.count == 0)
    }

    @Test func aLevelThatRunsNoModelProbesNothing() async {
        // Off is `mode = raw`; the stored provider keys stay.
        let rig = rig(Self.chosen)
        rig.model.choice = .off
        await rig.model.refresh()
        #expect(rig.probes.count == 0)
    }
}

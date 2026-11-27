import Foundation
import LintelKit
import Testing

@testable import LintelApp

/// Settings → Features: the banner follows the sidebar's dots (#287), Result order lists only the features that are
/// on (#288) and the switches keep their accessibility press action (#289).
@MainActor
@Suite(.serialized) struct FeaturesPaneFixesTests {
    let env: TestEnvironment

    init() throws {
        env = try TestEnvironment()
    }

    // #287

    @Test func theBannerNamesTheEnabledFeaturesThatHaveADot() {
        let ready = ShellPaneBanners.Feature(name: "Apps", isEnabled: true, isFailed: false)
        let waiting = ShellPaneBanners.Feature(
            name: "Dictation", isEnabled: true, isFailed: false, attention: .attention)
        let waitingToo = ShellPaneBanners.Feature(
            name: "Meetings", isEnabled: true, isFailed: false, attention: .attention)
        let banner = ShellPaneBanners.features([ready, waiting, waitingToo])
        #expect(banner.level == .attention)
        #expect(banner.title == StatusDerivation.levelName(.attention))
        #expect(banner.detail?.contains("Dictation") == true)
        #expect(banner.detail?.contains("Meetings") == true)
        #expect(banner.detail?.contains("Apps") == false)
        // A feature that is off never counts, whatever its pane would say.
        let off = ShellPaneBanners.Feature(name: "Files", isEnabled: false, isFailed: false, attention: .attention)
        #expect(ShellPaneBanners.features([ready, off]).title == "All set")
        // An error in a pane is an error here; a feature that could not start keeps its own banner.
        let broken = ShellPaneBanners.Feature(name: "Dictation", isEnabled: true, isFailed: false, attention: .error)
        #expect(ShellPaneBanners.features([ready, broken]).level == .error)
        let failed = ShellPaneBanners.Feature(name: "Files", isEnabled: true, isFailed: true, attention: .error)
        #expect(ShellPaneBanners.features([waiting, failed]).title == "A feature couldn't start")
    }

    @Test func theBannerAndTheSidebarDotAgree() async {
        defer { env.tearDown() }
        let host = env.makeHost([PlainFeaturePlugin.self, ListeningPlugin.self])
        await host.start()
        let reader = FakePermissionsReader()
        reader.answers[.microphone] = .granted
        #expect(ShellPaneBanners.features(host: host, reader: reader).title == "All set")
        // Listening needs the microphone and it is denied: the sidebar gets a dot for it, and so does the banner.
        reader.answers[.microphone] = .denied
        let id = ListeningPlugin.manifest.id.rawValue
        #expect(StatusDerivation.attention(SettingsHostModel.banner(for: id, host: host, reader: reader)) != nil)
        let banner = ShellPaneBanners.features(host: host, reader: reader)
        #expect(banner.level == .attention)
        #expect(banner.detail?.contains("Listening") == true)
        // Switched off, it has no dot and the banner no longer names it.
        await host.setEnabled(false, for: ListeningPlugin.manifest.id)
        #expect(StatusDerivation.attention(SettingsHostModel.banner(for: id, host: host, reader: reader)) == nil)
        let off = ShellPaneBanners.features(host: host, reader: reader)
        #expect(off.level == .ok)
        #expect(off.detail == "Some features are off.")
    }

    // #288

    @Test func resultOrderListsOnlyTheFeaturesThatAreOn() async {
        defer { env.tearDown() }
        let host = env.makeHost([PlainFeaturePlugin.self, OtherFeaturePlugin.self, ThirdFeaturePlugin.self])
        await host.start()
        let order = SectionOrderControls(host: host, settings: AppSettings(store: env.settings))
        // Other is off by default.
        #expect(order.ordered.map(\.manifest.id.rawValue) == ["plain", "third"])
        await host.setEnabled(true, for: OtherFeaturePlugin.manifest.id)
        #expect(order.ordered.map(\.manifest.id.rawValue) == ["plain", "other", "third"])
        await host.setEnabled(false, for: PlainFeaturePlugin.manifest.id)
        await host.setEnabled(false, for: OtherFeaturePlugin.manifest.id)
        await host.setEnabled(false, for: ThirdFeaturePlugin.manifest.id)
        #expect(order.ordered.isEmpty)
    }

    @Test func movingAFeatureKeepsTheSavedPlaceOfOneThatIsOff() async {
        defer { env.tearDown() }
        let host = env.makeHost([PlainFeaturePlugin.self, OtherFeaturePlugin.self, ThirdFeaturePlugin.self])
        await host.start()
        let settings = AppSettings(store: env.settings)
        let order = SectionOrderControls(host: host, settings: settings)
        order.move(ThirdFeaturePlugin.manifest.id, by: -1)
        #expect(order.ordered.map(\.manifest.id.rawValue) == ["third", "plain"])
        // Other was off while the others moved; once it is on again it is still between them.
        #expect(settings.sectionOrder == ["third", "other", "plain"])
        await host.setEnabled(true, for: OtherFeaturePlugin.manifest.id)
        #expect(order.ordered.map(\.manifest.id.rawValue) == ["third", "other", "plain"])
        order.move(PlainFeaturePlugin.manifest.id, to: 0)
        #expect(order.ordered.map(\.manifest.id.rawValue) == ["plain", "third", "other"])
    }

    // #289

    /// A switch whose label is hidden is exposed as an `AXToggle` with no press action; the feature rows therefore
    /// make the text the switch's own label, like Settings → General (see `FeatureSwitchRow`).
    @Test func theFeatureSwitchesAreLabelledSwitchesNotHiddenLabelToggles() throws {
        var url = URL(filePath: #filePath)
        while url.path != "/", !FileManager.default.fileExists(atPath: url.appending(path: "Package.swift").path) {
            url = url.deletingLastPathComponent()
        }
        let source = try String(
            contentsOf: url.appending(path: "Sources/LintelApp/Settings/FeaturesPane.swift"), encoding: .utf8)
        #expect(!source.contains(".labelsHidden()"))
        let row = try #require(source.components(separatedBy: "struct FeatureSwitchRow").last)
        #expect(row.contains("Toggle(isOn:"))
        #expect(row.contains(".toggleStyle(.switch)"))
    }
}

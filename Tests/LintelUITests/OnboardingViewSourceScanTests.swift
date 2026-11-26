import Foundation
import Testing

/// The onboarding pages are pure views (spec `2026-11-24-first-run-onboarding`, step 3.2): no I/O, no knowledge of
/// the shell's flow, no permission calls, no raw colours, and no disabled button (C10: Continue is never grey).
@Suite struct OnboardingViewSourceScanTests {
    /// What a pure view must not name: files, network, processes, defaults, the Keychain, permissions, windows of
    /// other apps, and the shell's own types (the adapter is written at wiring time, in `LintelApp`).
    static let forbidden =
        #"FileManager|URLSession|\bProcess\b|UserDefaults|SettingsStore|Keychain|SecItem|AVCaptureDevice|AVAudio|AXIsProcessTrusted|CGPreflight|CGWindowList|NSWorkspace|PermissionGrantService|OnboardingFlow|OnboardingDisplayPolicy|PluginHost|PluginContext|import LintelApp|import LintelKit|Task\s*[{.(]|DispatchQueue|Timer\b"#

    /// A raw colour or a system grey instead of `LintelBrand`.
    static let rawColour =
        #"Color\((red|white|hue|\.sRGB|nsColor|uiColor)|Color\.(red|blue|green|orange|purple|gray|black|white)\b|\.foregroundStyle\(\.(red|blue|green|orange|purple|gray|black|white)\)|NSColor\.|\.accentColor|\.tint\("#

    /// A button that can be turned off.
    static let disabledButton = #"\.disabled\("#

    static func code(_ file: (name: String, code: String)) -> [(Int, String)] {
        file.code.components(separatedBy: .newlines).enumerated().compactMap { index, line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Comments may name what the code never does.
            if trimmed.hasPrefix("//") { return nil }
            return (index + 1, line)
        }
    }

    static func offences(_ pattern: String, in files: [(name: String, code: String)]) -> [String] {
        files.flatMap { file in
            code(file).compactMap { number, line in
                line.range(of: pattern, options: .regularExpression) != nil ? "\(file.name):\(number): \(line)" : nil
            }
        }
    }

    @Test func theScannedFolderHoldsTheViewsOfAllFourPieces() throws {
        let names = try OnboardingCopyTests.sources().map(\.name)
        for name in [
            "OnboardingGoalPage.swift", "OnboardingPrivacyPage.swift", "OnboardingAccessPage.swift",
            "OnboardingStepRail.swift", "OnboardingWindowFrame.swift", "OnboardingTypes.swift",
        ] {
            #expect(names.contains(name), "\(name) is not scanned")
        }
    }

    @Test func noViewReachesForIOThePermissionsOrTheShell() throws {
        let files = try OnboardingCopyTests.sources()
        #expect(Self.offences(Self.forbidden, in: files).isEmpty, "\(Self.offences(Self.forbidden, in: files))")
    }

    @Test func noViewUsesARawColourOrASystemAccent() throws {
        let files = try OnboardingCopyTests.sources()
        #expect(Self.offences(Self.rawColour, in: files).isEmpty, "\(Self.offences(Self.rawColour, in: files))")
    }

    @Test func noButtonIsEverDisabled() throws {
        let files = try OnboardingCopyTests.sources()
        #expect(Self.offences(Self.disabledButton, in: files).isEmpty)
    }

    @Test func theScansCatchWhatTheyShouldAndOnlyThat() {
        func hits(_ pattern: String, _ line: String) -> Bool {
            line.range(of: pattern, options: .regularExpression) != nil
        }
        #expect(hits(Self.forbidden, "let data = FileManager.default.contents(atPath: p)"))
        #expect(hits(Self.forbidden, "AVCaptureDevice.requestAccess(for: .audio)"))
        #expect(hits(Self.forbidden, "let flow: OnboardingFlow"))
        #expect(hits(Self.forbidden, "Task { await work() }"))
        #expect(!hits(Self.forbidden, "Text(state.stepLabel)"))
        #expect(hits(Self.rawColour, ".foregroundStyle(.orange)"))
        #expect(hits(Self.rawColour, "Color(red: 1, green: 0, blue: 0)"))
        #expect(!hits(Self.rawColour, ".foregroundStyle(LintelBrand.accent)"))
        #expect(hits(Self.disabledButton, "Button(action: go) { Text(x) }.disabled(!ready)"))
        #expect(!hits(Self.disabledButton, "Button(action: go) { Text(x) }"))
    }

    @Test func thePrimaryButtonIsTheOnlyFilledOneAndIsTheDefaultAction() throws {
        // C3: one filled button per screen. The page frame owns it; no page adds another.
        let files = try OnboardingCopyTests.sources()
        let primaryUses = files.flatMap { file in
            Self.code(file).filter { $0.1.contains("LintelPrimaryButtonStyle") }.map { _ in file.name }
        }
        #expect(primaryUses == ["OnboardingWindowFrame.swift"], "\(primaryUses)")
        let frame = try #require(files.first { $0.name == "OnboardingWindowFrame.swift" })
        #expect(frame.code.contains(".keyboardShortcut(.defaultAction)"))
    }
}

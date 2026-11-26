import AppKit
import LintelKit
import SwiftUI
import Testing

@testable import LintelUI

/// Off by default: with `LINTEL_UI_SNAPSHOT_DIR=<folder>` writes light and dark PNGs of the Languages row and sheet
/// (spec `2026-11-23-automatic-language-detection`, step 2.2) for the owner's review, rendered offscreen by AppKit
/// (`cacheDisplay`). The strings are the English base: the test bundle has no String Catalog.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["LINTEL_UI_SNAPSHOT_DIR"] != nil))
struct SpeechLanguagesSnapshotTests {
    private var folder: URL {
        URL(filePath: ProcessInfo.processInfo.environment["LINTEL_UI_SNAPSHOT_DIR"] ?? "", directoryHint: .isDirectory)
    }

    /// The catalog as a plugin would build it, with English names.
    private static let options: [SpeechLanguageOption] = {
        let whisperOnly: Set<String> = ["ja", "tr", "ko", "zh", "ar", "hi", "he", "vi"]
        let codes = [
            "pl", "en", "uk", "de", "fr", "es", "it", "cs", "sk", "sv", "ru", "el", "ja", "tr", "ko", "zh", "ar", "hi",
            "he", "vi", "nl", "pt", "da", "fi", "hu", "ro",
        ]
        return codes.map {
            SpeechLanguageOption(
                code: $0, needsWhisper: whisperOnly.contains($0),
                name: SpeechLanguageOption.displayName(for: $0, interfaceLanguage: "en"))
        }
    }()

    private func sheet(_ selection: SpeechLanguageSelection, whisperInstalled: Bool = false) -> some View {
        SpeechLanguagesSheet(
            model: SpeechLanguagesSheetModel(
                selection: selection, options: Self.options, whisperInstalled: whisperInstalled),
            onDone: { _ in }, onCancel: {}, onGetWhisper: { _ in })
    }

    private func row(_ selection: SpeechLanguageSelection) -> some View {
        Form {
            Section {
                SpeechLanguagesRow(selection: selection, options: Self.options) {}
            }
        }
        .formStyle(.grouped)
        .modifier(LintelFormSurfaces())
        .frame(width: SettingsLayout.mainColumnWidth, height: 130)
    }

    @Test func writeTheScreens() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let derived = SpeechLanguageSelection(mode: .automatic, languages: ["pl", "en"], isDerived: true)
        let withJapanese = SpeechLanguageSelection(mode: .automatic, languages: ["pl", "en", "ja"], isDerived: false)
        let single = SpeechLanguageSelection(mode: .single("pl"), languages: ["pl", "en", "uk"], isDerived: false)
        let full = SpeechLanguageSelection(
            mode: .automatic, languages: ["pl", "en", "uk", "de", "fr", "es", "it", "cs", "sk", "sv"],
            isDerived: false)
        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            try write(row(derived), dark: dark, name: "row-automatic-\(suffix)")
            try write(row(single), dark: dark, name: "row-always-\(suffix)")
            try write(sheet(derived), dark: dark, name: "sheet-derived-\(suffix)")
            try write(sheet(withJapanese), dark: dark, name: "sheet-whisper-missing-\(suffix)")
            try write(
                sheet(withJapanese, whisperInstalled: true), dark: dark, name: "sheet-whisper-installed-\(suffix)")
            try write(sheet(single), dark: dark, name: "sheet-always-one-\(suffix)")
            try write(sheet(full), dark: dark, name: "sheet-ten-languages-\(suffix)")
        }
    }

    private func write(_ view: some View, dark: Bool, name: String) throws {
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        let content =
            view
            .background(LintelBrand.windowBackground)
            .environment(\.colorScheme, dark ? .dark : .light)
        let hosting = NSHostingView(rootView: content)
        hosting.appearance = appearance
        let size = hosting.fittingSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        appearance.performAsCurrentDrawingAppearance {
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        }
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: folder.appending(path: "\(name).png"))
        window.close()
    }
}

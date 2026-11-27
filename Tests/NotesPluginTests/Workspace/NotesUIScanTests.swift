import Foundation
import Testing

/// The Notes views draw every colour through `LintelBrand` (colours only through the brand tokens, no raw
/// colours): no named system colour, no `Color(red:…)`, no `NSColor`.
@Suite struct NotesUIScanTests {
    private static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private static let pattern =
        #"\.(red|green|blue|orange|yellow|pink|purple|indigo|teal|mint|cyan|brown|gray|black|white|primary)\b(?!\()|Color\((red|white|hue|\.sRGB|nsColor)|NSColor\.|\bNSColor\("#

    @Test func theViewsUseNoRawColour() throws {
        let folder = Self.root.appending(path: "Sources/NotesPlugin/UI")
        let enumerator = try #require(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil))
        var count = 0
        var offences: [String] = []
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            count += 1
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                let code = line.components(separatedBy: "//").first ?? ""
                if code.range(of: Self.pattern, options: .regularExpression) != nil {
                    offences.append("\(file.lastPathComponent):\(index + 1)")
                }
            }
        }
        #expect(count >= 6)
        #expect(offences.isEmpty, "colours come from LintelBrand: \(offences)")
    }

    /// Verdigris (the accent, its text colour and the selection tints) marks only the primary action, the selection
    /// and live states (spec C19). In the explorer of phase 3a no view has a primary action and the live rings take
    /// their colour inside `LintelRing`, so every use there must be a selection: a line that chooses by `isSelected`
    /// or `selected`. The one named exception is the search highlight, which reuses the selection look for the
    /// matched words (an owner question on #348).
    private static let verdigris = #"LintelBrand\.(accent|accentText|onAccent|selectionTint|windowSelectionTint)\b"#
    private static let verdigrisExceptions: [(file: String, line: String)] = [
        ("NoteRowView.swift", "text[lower..<upper].backgroundColor = LintelBrand.windowSelectionTint"),
        ("NoteRowView.swift", "text[lower..<upper].foregroundColor = LintelBrand.accentText"),
    ]

    @Test func verdigrisMarksOnlyTheSelectionInTheExplorer() throws {
        let files = [
            "Sources/NotesPlugin/UI/Explorer", "Sources/LintelUI/Components/SidebarRow.swift",
            "Sources/LintelUI/Components/EmptyStateView.swift", "Sources/LintelApp/Window/MainSidebar.swift",
        ].flatMap { path -> [URL] in
            let url = Self.root.appending(path: path)
            guard url.pathExtension != "swift" else { return [url] }
            let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
            return names.filter { $0.hasSuffix(".swift") }.map { url.appending(path: $0) }
        }
        #expect(files.count >= 8)
        var uses = 0
        var offences: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                let code = line.components(separatedBy: "//").first ?? ""
                guard code.range(of: Self.verdigris, options: .regularExpression) != nil else { continue }
                uses += 1
                let trimmed = code.trimmingCharacters(in: .whitespaces)
                let isSelection = code.contains("isSelected ?") || code.contains("selected ?")
                let isException = Self.verdigrisExceptions.contains {
                    $0.file == file.lastPathComponent && trimmed.hasPrefix($0.line)
                }
                if !isSelection && !isException { offences.append("\(file.lastPathComponent):\(index + 1)") }
            }
        }
        #expect(uses >= 5)
        #expect(offences.isEmpty, "Verdigris outside the selection: \(offences)")
    }

    /// Phase 3b retired the tabs: one note at a time in the full window, the list behind "‹ All notes". Neither the
    /// tab bar, the path bar nor the tab set may come back in the plugin's sources.
    @Test func theTabsAndThePathBarAreRetired() throws {
        let folder = Self.root.appending(path: "Sources/NotesPlugin")
        let enumerator = try #require(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil))
        var offences: [String] = []
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for name in ["NoteTabBar", "NoteTabSet", "NotePathBar", "closeCurrentTab", "NoteTabReorder"]
            where text.contains(name) {
                offences.append("\(file.lastPathComponent): \(name)")
            }
        }
        #expect(offences.isEmpty, "the tabs are retired: \(offences)")
        let fullWindow = folder.appending(path: "UI/FullWindow/NoteFullWindowBar.swift")
        #expect(FileManager.default.fileExists(atPath: fullWindow.path(percentEncoded: false)))
    }

    @Test func thePatternCatchesRawColours() {
        for bad in [".foregroundStyle(.red)", "Color.black", "Color(red: 1, green: 0, blue: 0)", "NSColor.white"] {
            #expect(bad.range(of: Self.pattern, options: .regularExpression) != nil, "\(bad)")
        }
        for good in [".foregroundStyle(LintelBrand.ink)", "Color.clear", ".font(textSize.font(.callout))"] {
            #expect(good.range(of: Self.pattern, options: .regularExpression) == nil, "\(good)")
        }
    }
}

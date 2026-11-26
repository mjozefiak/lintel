import LintelKit
import SwiftUI

/// The Languages row of the Dictation and Meetings panes (spec `2026-11-23-automatic-language-detection`, "UI/UX"):
/// the shared selection in one line, "Automatic · Polish, English" or "Always Polish", an Edit… button that opens
/// `SpeechLanguagesSheet`, and the caption that the setting is shared. The panes place it through `SpeechLanguagesSetting`.
public struct SpeechLanguagesRow: View {
    private let selection: SpeechLanguageSelection
    private let names: [String: String]
    private let edit: () -> Void
    @Environment(\.lintelTextSize) private var textSize

    /// - Parameters:
    ///   - selection: the setting now (`PluginContext.speechLanguages.current()`).
    ///   - options: the catalog with names, for the summary.
    ///   - edit: opens the sheet.
    public init(selection: SpeechLanguageSelection, options: [SpeechLanguageOption], edit: @escaping () -> Void) {
        self.selection = selection
        self.names = Dictionary(options.map { ($0.code, $0.name) }, uniquingKeysWith: { first, _ in first })
        self.edit = edit
    }

    /// "Automatic · Polish, English".
    public var summary: String { selection.summary { names[$0] ?? $0 } }

    public var body: some View {
        LabeledContent {
            Button(action: edit) {
                Text(Self.editTitle)
            }
            .buttonStyle(LintelSecondaryButtonStyle())
            .accessibilityLabel(Text(Self.editAccessibilityLabel))
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title)
                    .font(textSize.font(.body))
                Text(summary)
                    .font(textSize.font(.callout))
                    .foregroundStyle(LintelBrand.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Self.caption)
                    .font(textSize.font(.callout))
                    .foregroundStyle(LintelBrand.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    public static let title = LocalizedStringResource(
        "Languages", comment: "Settings row and sheet title: the languages the user speaks, shared by voice features")
    public static let editTitle = LocalizedStringResource(
        "speechLanguages.edit", defaultValue: "Edit…", comment: "Settings Languages row: opens the languages sheet")
    static let editAccessibilityLabel = LocalizedStringResource(
        "Edit Languages", comment: "Settings Languages row: spoken name of the button that opens the languages sheet")
    public static let caption = LocalizedStringResource(
        "Shared by Dictation and Meetings.",
        comment: "Settings Languages row: the same list is used by both voice features")
}

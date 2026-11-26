import AppKit
import SwiftUI

/// The measurements of the floating permission helper (spec 2026-11-24, section 3, "Floating helper panel").
public nonisolated enum PermissionHelperLayout {
    /// The width of the card; its height follows the content and the text size.
    public static let width: CGFloat = 300
    /// The Lintel icon tile that is dragged into System Settings' list.
    public static let tileSize: CGFloat = 52
    public static let cornerRadius: CGFloat = 12
    public static let padding: CGFloat = 14
}

/// What the helper says right now.
public nonisolated enum PermissionHelperContent: Equatable, Sendable {
    /// The Lintel icon to drag into the list, then the switch (Full Disk Access, where Lintel is not added for you).
    case dragTile
    /// Lintel is already in the list: only the switch (Accessibility, Microphone, System Audio Recording).
    case turnOnSwitch
    /// The grant was detected; shown for a second before the panel closes.
    case allowed
}

/// The floating helper that sits next to the System Settings list: the Lintel icon as a real drag source, one
/// sentence, "Show Lintel in Finder" (the keyboard and VoiceOver path for the list's "+" button) and "Done".
/// Nothing else (owner decision 2026-11-25: floating panels are as small as they can be).
///
/// Pure view: no I/O. The icon and the bundle URL come in, so the gallery draws it over a fixed icon and a made-up
/// path, and the panel passes the real ones. Colours only from `LintelBrand`, sizes from `lintelTextSize`.
public struct PermissionHelperView<Icon: View>: View {
    private let content: PermissionHelperContent
    private let bundleURL: URL
    private let icon: Icon
    private let showInFinder: () -> Void
    private let done: () -> Void
    @Environment(\.lintelTextSize) private var textSize

    public init(
        content: PermissionHelperContent,
        bundleURL: URL,
        showInFinder: @escaping () -> Void,
        done: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) {
        self.content = content
        self.bundleURL = bundleURL
        self.showInFinder = showInFinder
        self.done = done
        self.icon = icon()
    }

    /// The sentence of the states that ask for something.
    public nonisolated static func sentence(for content: PermissionHelperContent) -> String? {
        switch content {
        case .dragTile:
            String(
                localized: "Drag Lintel into the list, then turn on its switch.",
                comment: "Floating helper next to the System Settings list: drag the app's icon into the list")
        case .turnOnSwitch:
            String(
                localized: "Turn on the switch next to Lintel.",
                comment: "Floating helper next to the System Settings list: Lintel is listed, its switch is off")
        case .allowed: nil
        }
    }

    public var body: some View {
        Group {
            switch content {
            case .allowed: allowedBody
            case .dragTile: dragBody
            case .turnOnSwitch: switchBody
            }
        }
        .font(textSize.font(.body))
        .padding(PermissionHelperLayout.padding)
        .frame(width: PermissionHelperLayout.width, alignment: .leading)
        .background(LintelBrand.card, in: RoundedRectangle(cornerRadius: PermissionHelperLayout.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: PermissionHelperLayout.cornerRadius)
                .strokeBorder(LintelBrand.hairline, lineWidth: 1)
        )
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }

    private var allowedBody: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(LintelBrand.statusOk)
                .accessibilityHidden(true)
            Text(String(localized: "Allowed", comment: "Permission state"))
                .fontWeight(.semibold)
                .foregroundStyle(LintelBrand.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var dragBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                tile
                sentenceText
            }
            HStack(spacing: 8) {
                Button(action: showInFinder) { Text(Self.showInFinderTitle) }
                    .buttonStyle(LintelSecondaryButtonStyle())
                Spacer(minLength: 0)
                doneButton
            }
        }
    }

    private var switchBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            sentenceText
            HStack {
                Spacer(minLength: 0)
                doneButton
            }
        }
    }

    private var sentenceText: some View {
        Text(Self.sentence(for: content) ?? "")
            .foregroundStyle(LintelBrand.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The icon is the drag source: a file URL, which System Settings' list accepts like a drop from Finder. A
    /// drag is not reachable with the keyboard or VoiceOver; "Show Lintel in Finder" is that path.
    private var tile: some View {
        icon
            .frame(width: PermissionHelperLayout.tileSize, height: PermissionHelperLayout.tileSize)
            .onDrag { NSItemProvider(object: bundleURL as NSURL) }
            .accessibilityHidden(true)
    }

    private var doneButton: some View {
        Button(action: done) { Text(Self.doneTitle) }
            .buttonStyle(LintelPrimaryButtonStyle())
    }

    public nonisolated static var showInFinderTitle: String {
        String(
            localized: "Show Lintel in Finder",
            comment: "Floating helper button that reveals the app in Finder, for the list's + button")
    }

    public nonisolated static var doneTitle: String {
        String(localized: "Done", comment: "Onboarding button on the last step")
    }
}

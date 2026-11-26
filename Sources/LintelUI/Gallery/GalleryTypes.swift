#if DEBUG
import AppKit
import SwiftUI

/// DEBUG only (spec `2026-11-23-swiftui-design-gallery`): one cell of the gallery matrix, the look a state is drawn
/// in. Its `name` (`<light|dark>-<s|m|l|xl>-<en|pl>`) is part of a golden file's name. Not a contract.
public struct GalleryVariant: Hashable, Sendable {
    public enum Appearance: String, CaseIterable, Sendable {
        case light
        case dark

        var name: NSAppearance.Name {
            switch self {
            case .light: .aqua
            case .dark: .darkAqua
            }
        }
    }

    public var appearance: Appearance
    public var textSize: TextSize
    /// `en` or `pl`. Texts come from the language of the process (`GalleryRenderer.processLanguage`), so a variant
    /// in another language cannot be drawn by this process.
    public var language: String

    public init(appearance: Appearance, textSize: TextSize, language: String) {
        self.appearance = appearance
        self.textSize = textSize
        self.language = language
    }

    /// `dark-m-en`.
    public var name: String { "\(appearance.rawValue)-\(textSize.rawValue)-\(language)" }

    /// What CI compares: light·M·en, dark·M·en and light·XL·pl (Q4).
    public static let ciSubset: [GalleryVariant] = [
        GalleryVariant(appearance: .light, textSize: .medium, language: "en"),
        GalleryVariant(appearance: .dark, textSize: .medium, language: "en"),
        GalleryVariant(appearance: .light, textSize: .extraLarge, language: "pl"),
    ]

    /// What the owner approves: 2 appearances × {S, M, XL} × 2 languages. `L` stays out (its scale lies between M
    /// and XL, and XL is the upper bound for wrapping); a state may add it to the owner's sheet with
    /// `GalleryState.includesLargeInSheet` (`sheetMatrix`), which leaves what CI compares unchanged.
    public static let fullMatrix: [GalleryVariant] = {
        var variants: [GalleryVariant] = []
        for language in ["en", "pl"] {
            for size in [TextSize.small, .medium, .extraLarge] {
                for appearance in Appearance.allCases {
                    variants.append(GalleryVariant(appearance: appearance, textSize: size, language: language))
                }
            }
        }
        return variants
    }()

    /// The owner's sheet of one state: `fullMatrix`, plus L in both appearances and languages when `includesLarge`
    /// (a component whose sizes are set per text size, like the HUD pill's 28 / 32 / 35 / 38 pt).
    public static func sheetMatrix(includesLarge: Bool) -> [GalleryVariant] {
        guard includesLarge else { return fullMatrix }
        var variants: [GalleryVariant] = []
        for language in ["en", "pl"] {
            for size in [TextSize.small, .medium, .large, .extraLarge] {
                for appearance in Appearance.allCases {
                    variants.append(GalleryVariant(appearance: appearance, textSize: size, language: language))
                }
            }
        }
        return variants
    }

    /// The variants of `all` that are drawn in `language`.
    public static func only(_ language: String, in all: [GalleryVariant]) -> [GalleryVariant] {
        all.filter { $0.language == language }
    }

    /// Parses `light-m-en`; `nil` for anything else.
    public init?(name: String) {
        let parts = name.split(separator: "-").map(String.init)
        guard parts.count == 3, let appearance = Appearance(rawValue: parts[0]),
            let size = TextSize(rawValue: parts[1]), ["en", "pl"].contains(parts[2])
        else { return nil }
        self.init(appearance: appearance, textSize: size, language: parts[2])
    }
}

/// The shape of a HUD's own backdrop (`SnapshotBackdropHostingView`).
public enum GalleryHUDShape: Sendable, Equatable {
    case capsule
    case rounded(radius: CGFloat)
}

/// How a state is put on the page. Sheets, popovers and HUDs are drawn as content on an opaque backdrop: the system's
/// chrome and the glass material are not drawn by `cacheDisplay` (`docs/qa.md`).
public enum GalleryPresentation: Sendable, Equatable {
    /// A pane in a container of `width`; `nil` height is the height the content asks for.
    case window(width: CGFloat, height: CGFloat? = nil)
    case sheet(width: CGFloat)
    /// The content of a popover with an outline and an arrow drawn by the renderer (an approximation). `width` is
    /// the least width: a popover that sizes itself with the text size (a menu) may be wider.
    case popover(width: CGFloat)
    case hud(shape: GalleryHUDShape)

    /// What the caption of a state says about what the picture leaves out.
    public var caveat: String? {
        switch self {
        case .window: nil
        case .sheet, .popover: "content only; system chrome approximated"
        case .hud: "glass not drawn; check live in --qa-gallery"
        }
    }
}

public struct GalleryState: Identifiable, Sendable {
    /// kebab-case and stable: it is part of the golden file's name.
    public let id: String
    /// What the owner approves, in English.
    public let summary: String
    public let presentation: GalleryPresentation
    public let variants: [GalleryVariant]
    /// The owner's sheet (export, the window's "Full matrix") also draws the L size; CI compares `variants` only.
    public let includesLargeInSheet: Bool
    public let make: @MainActor @Sendable () -> AnyView

    public init(
        id: String, summary: String, presentation: GalleryPresentation,
        variants: [GalleryVariant] = GalleryVariant.ciSubset, includesLargeInSheet: Bool = false,
        make: @escaping @MainActor @Sendable () -> AnyView
    ) {
        self.id = id
        self.summary = summary
        self.presentation = presentation
        self.variants = variants
        self.includesLargeInSheet = includesLargeInSheet
        self.make = make
    }

    /// What the owner's sheet draws for this state.
    public var sheetVariants: [GalleryVariant] {
        GalleryVariant.sheetMatrix(includesLarge: includesLargeInSheet)
    }
}

public struct GalleryScene: Identifiable, Sendable {
    /// `meetings.notes-provider`.
    public let id: String
    public let title: String
    public let states: [GalleryState]

    public init(id: String, title: String, states: [GalleryState]) {
        self.id = id
        self.title = title
        self.states = states
    }

    /// `^[a-z0-9.-]+$`: scene ids and state ids are file names.
    public static func isValidIdentifier(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.allSatisfy {
                ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2E || $0 == 0x2D
            }
    }

    /// The problems with a set of scenes: bad or duplicate ids, empty summaries.
    public static func validationProblems(_ scenes: [GalleryScene]) -> [String] {
        var problems: [String] = []
        var seenScenes = Set<String>()
        for scene in scenes {
            if !isValidIdentifier(scene.id) { problems.append("scene id \(scene.id) is not [a-z0-9.-]+") }
            if !seenScenes.insert(scene.id).inserted { problems.append("scene id \(scene.id) is not unique") }
            var seenStates = Set<String>()
            for state in scene.states {
                if !isValidIdentifier(state.id) { problems.append("\(scene.id)/\(state.id): id is not [a-z0-9.-]+") }
                if !seenStates.insert(state.id).inserted {
                    problems.append("\(scene.id)/\(state.id): id is not unique")
                }
                if state.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    problems.append("\(scene.id)/\(state.id): summary is empty")
                }
                if state.variants.isEmpty { problems.append("\(scene.id)/\(state.id): no variants") }
            }
        }
        return problems
    }
}

/// A plugin (or the shell) that has gallery scenes. A plugin type declares it in its own target
/// (`extension MeetingsPlugin: GalleryProviding`); the gallery window finds the types through `PluginRegistry.all`.
public protocol GalleryProviding {
    @MainActor static var galleryScenes: [GalleryScene] { get }
}

public enum GalleryError: Error, Equatable, CustomStringConvertible {
    /// The view stayed at zero size.
    case emptyRender(String)
    /// The variant is in another language than the process (`GalleryRenderer.processLanguage`).
    case languageMismatch(state: String, variant: String, process: String)
    /// The bitmap could not be made or written.
    case bitmap(String)
    /// Two renders in a row never came out the same within the settle limit (an animation that does not stop, a task
    /// that keeps changing the view): the picture would not be a golden.
    case didNotSettle(String)

    public var description: String {
        switch self {
        case .emptyRender(let id): "gallery state \(id) rendered at zero size"
        case .languageMismatch(let state, let variant, let process):
            "gallery state \(state): variant \(variant) is not drawn in this process (language \(process))"
        case .bitmap(let message): "gallery bitmap: \(message)"
        case .didNotSettle(let id): "gallery state \(id) did not settle: two renders in a row never matched"
        }
    }
}
#endif

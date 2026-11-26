#if DEBUG
import AppKit
import LintelKit
import LintelUI
import SwiftUI

/// DEBUG only: the design gallery scenes of the shell itself (the screens `LintelApp` owns, which no plugin brings).
/// `GalleryCatalog` adds them as the group "shell". One scene per screen a PR touches (`docs/design-gallery.md`).
enum ShellGallery: GalleryProviding {
    static var galleryScenes: [GalleryScene] { [PermissionHelperGallery.scene] }
}

/// The floating permission helper (spec `2026-11-24-first-run-onboarding`, section 3). Every state draws the REAL
/// `PermissionHelperView` over a fixed icon and a made-up path; no panel is made, no window list is read and no
/// permission is asked.
@MainActor enum PermissionHelperGallery {
    static let sceneID = "onboarding.permission-helper"
    private static let bundleURL = URL(filePath: "/Applications/Lintel.app")
    private static let tilePresentation = GalleryPresentation.window(width: 340)

    static var scene: GalleryScene {
        GalleryScene(id: sceneID, title: "Onboarding → floating permission helper", states: states)
    }

    /// The app icon is not the same in a test runner and in the app bundle, so the gallery draws a fixed stand-in
    /// of it: the ring on the dark tile, in the brand's own palette values.
    private static func icon() -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color(hex: BrandPalette.inkLight))
            LintelMark(ring: Color(hex: BrandPalette.surfaceLight), core: LintelBrand.accent)
                .padding(10)
        }
    }

    private static func helper(_ content: PermissionHelperContent) -> some View {
        PermissionHelperView(content: content, bundleURL: bundleURL, showInFinder: {}, done: {}, icon: { icon() })
    }

    static var states: [GalleryState] {
        [
            GalleryState(
                id: "drag-tile",
                summary:
                    "Full Disk Access: the Lintel icon to drag into the list, one sentence, Show Lintel in Finder and Done.",
                presentation: tilePresentation
            ) { AnyView(helper(.dragTile).padding(20)) },
            GalleryState(
                id: "turn-on-switch",
                summary:
                    "Accessibility and Microphone: Lintel is already in the list, so one sentence and Done, no icon.",
                presentation: tilePresentation
            ) { AnyView(helper(.turnOnSwitch).padding(20)) },
            GalleryState(
                id: "allowed",
                summary: "The grant was detected: a green check and Allowed for one second, then the panel closes.",
                presentation: tilePresentation
            ) { AnyView(helper(.allowed).padding(20)) },
            GalleryState(
                id: "beside-lintel",
                summary:
                    "No System Settings window within 3 seconds: the same panel sits beside Lintel's own window (the outline on the left is a stand-in).",
                presentation: .window(width: 580)
            ) {
                AnyView(
                    HStack(alignment: .center, spacing: PermissionHelperGeometry.gap) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(LintelBrand.windowBackground)
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(LintelBrand.hairline))
                            .frame(width: 200, height: 150)
                        helper(.dragTile)
                    }
                    .padding(20))
            },
        ]
    }
}

extension Color {
    fileprivate init(hex: UInt32) {
        self.init(
            .sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}
#endif

#if DEBUG
import AppKit
import Foundation
import LintelUI
import SwiftUI
import Testing

@testable import LintelApp

/// The gallery scenes of the onboarding pages (`docs/design-gallery.md`, "Adding a scene"; spec
/// `2026-11-24-first-run-onboarding`, UI/UX, "Gallery states"). The pictures are compared by the app bundle in CI,
/// not here: only the app bundle has the accent colour and the string catalog. Their goldens were recorded by the
/// `gallery-goldens.yml` run the owner approved.
@MainActor
@Suite(.serialized)
struct OnboardingGalleryTests {
    private static let lightM = GalleryVariant(appearance: .light, textSize: .medium, language: "en")
    private static let darkM = GalleryVariant(appearance: .dark, textSize: .medium, language: "en")
    private static let lightXL = GalleryVariant(appearance: .light, textSize: .extraLarge, language: "en")

    private static let expectedStates: [String: [String]] = [
        "onboarding.goal": ["both", "dictation", "meeting-notes"],
        "onboarding.privacy": ["with-consent", "without-consent"],
        "onboarding.access": [
            "needs-your-ok", "every-state", "all-allowed", "checking-call-audio", "check-failed", "download-running",
            "move-first",
        ],
        "onboarding.step-rail": ["step-3-of-5", "download-running", "four-steps"],
    ]

    @Test func theScenesAreValidAndHaveTheStatesOfTheSpec() {
        let scenes = ShellGallery.galleryScenes
        #expect(GalleryScene.validationProblems(scenes).isEmpty, "\(GalleryScene.validationProblems(scenes))")
        #expect(
            scenes.map(\.id) == ["onboarding.goal", "onboarding.privacy", "onboarding.access", "onboarding.step-rail"])
        for scene in scenes {
            #expect(scene.states.map(\.id) == Self.expectedStates[scene.id], "\(scene.id)")
        }
    }

    @Test func theCatalogHasTheShellGroupLastAndFindsEveryScene() throws {
        let last = try #require(GalleryCatalog.groups.last)
        #expect(last.id == GalleryCatalog.shellGroupID)
        #expect(last.scenes.map(\.id).filter { $0.hasPrefix("onboarding.") }.count == 4)
        for id in Self.expectedStates.keys {
            #expect(GalleryCatalog.scenes(matching: id).count == 1, "\(id)")
        }
        #expect(GalleryScene.validationProblems(GalleryCatalog.scenes).isEmpty)
    }

    @Test func thePageScenesAreTheWindowAndTheRailIsOnlyTheRail() throws {
        for scene in ShellGallery.galleryScenes {
            for state in scene.states {
                let expected: GalleryPresentation =
                    scene.id == "onboarding.step-rail"
                    ? .window(width: OnboardingLayout.railWidth, height: OnboardingLayout.windowHeight)
                    : .window(width: OnboardingLayout.windowWidth, height: OnboardingLayout.windowHeight)
                #expect(state.presentation == expected, "\(scene.id)/\(state.id)")
            }
        }
    }

    @Test func everyStateDrawsRealContentInTheCIAppearancesAndAtTheLargestSize() async throws {
        for scene in ShellGallery.galleryScenes {
            for state in scene.states {
                for variant in state.variants.filter({ $0.language == "en" }) + [Self.lightXL] {
                    let bitmap = try await GalleryRenderer.render(state, variant)
                    #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0, "\(scene.id)/\(state.id) is empty")
                    #expect(
                        Self.distinctColours(bitmap) > 5, "\(scene.id)/\(state.id) \(variant.name) drew a blank picture"
                    )
                }
            }
        }
    }

    @Test func aStateIsMadeFreshAndNoTwoStatesOfAScenePictureTheSame() async throws {
        for scene in ShellGallery.galleryScenes {
            var first: [String: NSBitmapImageRep] = [:]
            for state in scene.states { first[state.id] = try await GalleryRenderer.render(state, Self.lightM) }
            for state in scene.states.reversed() {
                let again = try await GalleryRenderer.render(state, Self.lightM)
                let (result, _) = GalleryDiff.compare(try #require(first[state.id]), again)
                #expect(result.passes(shareLimit: 0), "\(scene.id)/\(state.id) differs after the other states")
            }
            var byPicture: [String: [String]] = [:]
            for state in scene.states {
                let key = GalleryGoldens.sha256(try GalleryRenderer.pngData(try #require(first[state.id])))
                byPicture[key, default: []].append(state.id)
            }
            #expect(
                byPicture.values.allSatisfy { $0.count == 1 },
                "\(scene.id): these states draw the same picture: \(byPicture.values.filter { $0.count > 1 })")
        }
    }

    @Test func lightAndDarkDrawDifferently() async throws {
        for scene in ShellGallery.galleryScenes {
            let state = try #require(scene.states.first)
            let light = GalleryGoldens.sha256(
                try GalleryRenderer.pngData(try await GalleryRenderer.render(state, Self.lightM)))
            let dark = GalleryGoldens.sha256(
                try GalleryRenderer.pngData(try await GalleryRenderer.render(state, Self.darkM)))
            #expect(light != dark, "\(scene.id)")
        }
    }

    @Test func theTextSizeChangesThePicture() async throws {
        let state = try #require(ShellGallery.galleryScenes.first { $0.id == "onboarding.access" }?.states.first)
        let medium = GalleryGoldens.sha256(
            try GalleryRenderer.pngData(try await GalleryRenderer.render(state, Self.lightM)))
        let large = GalleryGoldens.sha256(
            try GalleryRenderer.pngData(try await GalleryRenderer.render(state, Self.lightXL)))
        #expect(medium != large)
    }

    @Test func aRunningDownloadChangesTheRailAndNothingElse() async throws {
        let titles = ["a", "b", "c", "d", "e"]
        func picture(_ download: OnboardingRailDownload?) async throws -> String {
            let state = GalleryState(
                id: "probe", summary: "probe",
                presentation: .window(width: OnboardingLayout.railWidth, height: OnboardingLayout.windowHeight)
            ) {
                AnyView(
                    OnboardingStepRail(
                        OnboardingStepRailState(titles: titles, currentIndex: 3, download: download)))
            }
            return GalleryGoldens.sha256(
                try GalleryRenderer.pngData(try await GalleryRenderer.render(state, Self.lightM)))
        }
        let without = try await picture(nil)
        let at40 = try await picture(.dictation(progress: 0.4))
        let at80 = try await picture(.dictation(progress: 0.8))
        #expect(without != at40)
        #expect(at40 != at80, "the bar does not follow the progress")
    }

    private static func distinctColours(_ bitmap: NSBitmapImageRep) -> Int {
        guard let data = bitmap.bitmapData else { return 0 }
        var seen = Set<UInt32>()
        let count = bitmap.pixelsWide * bitmap.pixelsHigh
        let stride = max(1, count / 4000)
        var index = 0
        while index < count {
            let p = data + index * 4
            seen.insert(UInt32(p[0]) << 16 | UInt32(p[1]) << 8 | UInt32(p[2]))
            index += stride
        }
        return seen.count
    }
}
#endif

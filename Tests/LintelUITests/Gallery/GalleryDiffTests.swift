#if DEBUG
import AppKit
import LintelKit
import SwiftUI
import Testing

@testable import LintelUI

/// Synthetic pixel buffers, no rendering: `GalleryDiff` is a pure function (spec `2026-11-23-swiftui-design-gallery`).
struct GalleryDiffTests {
    /// 40×20 pixels of mid grey with a 10×6 black block at `x`.
    private func picture(blockAt x: Int = 10, width: Int = 40, height: Int = 20) -> GalleryPixels {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            for column in 0..<width {
                let inBlock = (x..<(x + 10)).contains(column) && (4..<10).contains(row)
                let value: UInt8 = inBlock ? 0 : 128
                let base = (row * width + column) * 4
                bytes[base] = value
                bytes[base + 1] = value
                bytes[base + 2] = value
                bytes[base + 3] = 255
            }
        }
        return GalleryPixels(width: width, height: height, bytes: bytes)
    }

    @Test func identicalPicturesDiffer0() {
        let (result, image) = GalleryDiff.compare(picture(), picture())
        #expect(result.differingShare == 0)
        #expect(result.sizeMatches)
        #expect(image == nil)
        #expect(result.passes(shareLimit: 0))
    }

    @Test func aShiftOfOnePointIsOverTheLimit() {
        // 1 pt at 2x is 2 pixels: the block's edges move, a band of pixels changes.
        let (result, _) = GalleryDiff.compare(picture(blockAt: 10), picture(blockAt: 12))
        #expect(result.differingShare > GalleryDiff.defaultShareLimit)
        #expect(!result.passes())
    }

    @Test func noiseWithinTheChannelToleranceIsNotADifference() {
        let base = picture()
        var noisy = base.bytes
        for index in stride(from: 0, to: noisy.count, by: 4) {
            noisy[index] = noisy[index] &+ 3
            noisy[index + 1] = noisy[index + 1] &- (noisy[index + 1] > 3 ? 3 : 0)
        }
        let (within, _) = GalleryDiff.compare(base, GalleryPixels(width: 40, height: 20, bytes: noisy))
        #expect(within.differingShare == 0)
        // One over the tolerance is a difference.
        var over = base.bytes
        for index in stride(from: 0, to: over.count, by: 4) { over[index] = over[index] &+ 4 }
        let (beyond, _) = GalleryDiff.compare(base, GalleryPixels(width: 40, height: 20, bytes: over))
        #expect(beyond.differingShare == 1)
    }

    @Test func aDifferentSizeIsReportedAsSuch() {
        let (result, image) = GalleryDiff.compare(picture(), picture(width: 41))
        #expect(!result.sizeMatches)
        #expect(result.differingShare == 1)
        #expect(image == nil)
        #expect(!result.passes(shareLimit: 1))
    }

    @Test func theDiffImageIsRedOnlyWhereThePicturesChanged() throws {
        let a = picture(blockAt: 10)
        let b = picture(blockAt: 12)
        let (result, image) = GalleryDiff.compare(a, b)
        let diff = try #require(image.flatMap(GalleryPixels.init))
        #expect(diff.width == 40 && diff.height == 20)
        var red = 0
        for pixel in 0..<(diff.width * diff.height) {
            let base = pixel * 4
            let isRed = diff.bytes[base] == 255 && diff.bytes[base + 1] == 0 && diff.bytes[base + 2] == 0
            let changed = abs(Int(a.bytes[base]) - Int(b.bytes[base])) > Int(GalleryDiff.defaultChannelTolerance)
            #expect(isRed == changed, "pixel \(pixel)")
            if isRed { red += 1 }
        }
        #expect(Double(red) / 800 == result.differingShare)
    }

    @Test func bitmapsAreBroughtToTheSamePixelFormat() throws {
        let a = try #require(picture().bitmap())
        let b = try #require(picture().bitmap())
        let (result, _) = GalleryDiff.compare(a, b)
        #expect(result.differingShare == 0)
        let png = try #require(a.representation(using: .png, properties: [:]))
        let reread = try #require(NSBitmapImageRep(data: png))
        let (afterRoundTrip, _) = GalleryDiff.compare(a, reread)
        #expect(afterRoundTrip.differingShare == 0, "a PNG read back is the same picture")
    }
}

struct GalleryVariantTests {
    @Test func theNamesFollowTheFileFormat() {
        #expect(GalleryVariant.ciSubset.map(\.name) == ["light-m-en", "dark-m-en", "light-xl-pl"])
        #expect(GalleryVariant.fullMatrix.count == 12)
        #expect(Set(GalleryVariant.fullMatrix.map(\.name)).count == 12)
        #expect(!GalleryVariant.fullMatrix.contains { $0.textSize == .large })
        #expect(
            GalleryVariant(name: "dark-xl-pl")
                == GalleryVariant(appearance: .dark, textSize: .extraLarge, language: "pl"))
        #expect(GalleryVariant(name: "dark-xl") == nil)
        #expect(GalleryVariant(name: "blue-m-en") == nil)
    }

    @Test func identifiersAreFileNames() {
        for good in ["meetings.notes-provider", "local", "failed-timed-out", "a1"] {
            #expect(GalleryScene.isValidIdentifier(good))
        }
        for bad in ["", "Local", "a b", "a/b", "ł", "a_b"] {
            #expect(!GalleryScene.isValidIdentifier(bad), "\(bad)")
        }
    }

    @Test func validationFindsDuplicatesEmptySummariesAndBadIds() {
        let make: @MainActor @Sendable () -> AnyView = { AnyView(EmptyView()) }
        let state = { (id: String, summary: String) in
            GalleryState(id: id, summary: summary, presentation: .window(width: 100), make: make)
        }
        let scenes = [
            GalleryScene(
                id: "a", title: "A",
                states: [state("x", "ok"), state("x", "twice"), state("Y", "caps"), state("z", " ")]),
            GalleryScene(id: "a", title: "A again", states: []),
        ]
        let problems = GalleryScene.validationProblems(scenes)
        #expect(problems.count == 4, "\(problems)")
        #expect(
            GalleryScene.validationProblems([GalleryScene(id: "a", title: "A", states: [state("x", "ok")])]).isEmpty)
    }
}

struct GallerySettingsStoreTests {
    @Test func itHoldsValuesInMemoryAndRemovesThemOnNil() {
        let store = GallerySettingsStore(["a": .bool(true)])
        #expect(store.value(forKey: "a") == .bool(true))
        store.setValue(.string("x"), forKey: "b")
        #expect(store.value(forKey: "b") == .string("x"))
        store.setValue(nil, forKey: "a")
        #expect(store.value(forKey: "a") == nil)
        #expect(GallerySettingsStore().value(forKey: "b") == nil)
    }
}

struct GalleryFingerprintTests {
    @Test func aMismatchNamesWhatChanged() {
        let base = GalleryFingerprint(os: "27.0.1 (26A434)", xcode: "27.0 (18A1)", scale: 2, renderer: 1)
        #expect(base.mismatch(comparedTo: base) == nil)
        var other = base
        other.os = "27.1 (26B1)"
        #expect(base.mismatch(comparedTo: other)?.contains("os") == true)
        other = base
        other.xcode = nil
        #expect(base.mismatch(comparedTo: other)?.contains("xcode") == true)
    }
}
#endif

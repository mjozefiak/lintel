#if DEBUG
import Foundation
import LintelUI
import Testing

@testable import LintelApp

/// The `--qa-gallery…` arguments of the design gallery (spec `2026-11-23-swiftui-design-gallery`).
@MainActor
@Suite struct QAGalleryOptionsTests {
    @Test func theWindowIsAFlag() throws {
        let options = try #require(try QAOptions.parse(["--qa-gallery"]))
        #expect(options.showsGallery)
        #expect(!options.runsGalleryBatch)
        #expect(try QAOptions.parse(["--qa"])?.showsGallery == false)
    }

    @Test func theBatchModesTakeAFolder() throws {
        let export = try #require(
            try QAOptions.parse(["--qa-gallery-export", "/tmp/out", "--qa-gallery-scene", "a.b"]))
        #expect(export.galleryExport?.path == "/tmp/out")
        #expect(export.galleryScene == "a.b")
        #expect(export.runsGalleryBatch)
        let compare = try #require(
            try QAOptions.parse(["--qa-gallery-compare", "/tmp/g", "--qa-gallery-language", "pl"]))
        #expect(compare.galleryCompare?.path == "/tmp/g")
        #expect(compare.galleryLanguage == "pl")
        let record = try #require(try QAOptions.parse(["--qa-gallery-record", "/tmp/g"]))
        #expect(record.galleryRecord?.path == "/tmp/g")
        #expect(record.runsGalleryBatch)
    }

    @Test func aBatchModeNeedsItsValue() {
        for argument in ["--qa-gallery-export", "--qa-gallery-compare", "--qa-gallery-record", "--qa-gallery-scene"] {
            #expect(throws: QAOptions.ParseError.missingValue(argument)) { try QAOptions.parse([argument]) }
            #expect(throws: QAOptions.ParseError.invalidValue(argument, "--qa-gallery")) {
                try QAOptions.parse([argument, "--qa-gallery"])
            }
        }
    }

    @Test func theLanguageIsEnglishOrPolish() {
        #expect(throws: QAOptions.ParseError.invalidValue("--qa-gallery-language", "de")) {
            try QAOptions.parse(["--qa-gallery-language", "de"])
        }
        #expect(throws: QAOptions.ParseError.missingValue("--qa-gallery-language")) {
            try QAOptions.parse(["--qa-gallery-language"])
        }
    }

    @Test func aLanguageThatIsNotTheProcessesIsRefusedInsteadOfDrawnHalfTranslated() async throws {
        // `swift test` runs in the test runner's bundle: English.
        let options = try #require(
            try QAOptions.parse(["--qa-gallery-export", "/tmp/unused", "--qa-gallery-language", "pl"]))
        #expect(GalleryRenderer.processLanguage == "en")
        #expect(await GalleryBatch.run(options) == EX_USAGE)
    }

    @Test func theCatalogFindsTheScenesOfEveryPluginThatHasThem() throws {
        let groups = GalleryCatalog.groups
        let meetings = try #require(groups.first { $0.id == "meetings" })
        #expect(meetings.scenes.contains { $0.id == "meetings.notes-provider" })
        #expect(GalleryScene.validationProblems(GalleryCatalog.scenes).isEmpty)
        #expect(GalleryCatalog.scenes(matching: "meetings.notes-provider").count == 1)
        #expect(GalleryCatalog.scenes(matching: "nothing").isEmpty)
    }
}
#endif

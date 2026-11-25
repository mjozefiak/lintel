#if DEBUG
import AppKit
import LintelUI
import Testing

@testable import MeetingsPlugin

/// The scenes of `MeetingsPlugin` for the design gallery: ids, summaries, that every state draws, and that none of
/// them touches the real system (spec `2026-11-23-swiftui-design-gallery`, "Edge Cases").
@MainActor
@Suite(.serialized)
struct GalleryScenesTests {
    private static let lightM = GalleryVariant(appearance: .light, textSize: .medium, language: "en")

    @Test("ids are unique and well formed, every state has a summary")
    func scenesAreValid() {
        let scenes = GalleryTestSupport.scenes
        #expect(GalleryScene.validationProblems(scenes).isEmpty, "\(GalleryScene.validationProblems(scenes))")
        #expect(scenes.map(\.id).contains("meetings.notes-provider"))
        let ids = Set(scenes.flatMap { $0.states.map(\.id) })
        // The states of the spec's pilot table (the host's banner states are the shell's, not this plugin's).
        for id in [
            "local", "local-notes-off", "ready-sonnet", "ready-opus", "not-installed", "not-signed-in",
            "incompatible-version", "newer-version", "checking", "job-running", "confirm-use-local", "details-expanded",
            "earlier-mark", "failed-timed-out", "failed-network", "failed-rate-limited", "failed-other",
            "failed-too-long", "failed-model-not-available", "manual-binary", "try-running", "try-worked", "try-failed",
            "provider-menu", "model-menu",
        ] {
            #expect(ids.contains(id), "the pilot has no state \(id)")
        }
    }

    /// A state that is empty on purpose: Local with notes off hides the whole section.
    private static let emptyOnPurpose: Set<String> = ["local-notes-off"]

    private static func hasContent(_ bitmap: NSBitmapImageRep) -> Bool {
        guard let data = bitmap.bitmapData else { return false }
        let count = bitmap.pixelsWide * bitmap.pixelsHigh
        var distinct = Set<UInt32>()
        for index in stride(from: 0, to: count, by: 7) {
            let base = index * 4
            distinct.insert(UInt32(data[base]) << 16 | UInt32(data[base + 1]) << 8 | UInt32(data[base + 2]))
            if distinct.count > 8 { return true }
        }
        return false
    }

    @Test("every state draws real content in both CI appearances, and none of them reaches the real system")
    func everyStateDrawsWithoutTheRealSystem() async throws {
        MeetingsSystem.installQuiet()
        for scene in GalleryTestSupport.scenes {
            for state in scene.states {
                for variant in state.variants where variant.language == "en" {
                    let bitmap = try await GalleryRenderer.render(state, variant)
                    #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0, "\(state.id) is empty")
                    if !Self.emptyOnPurpose.contains(state.id) {
                        #expect(Self.hasContent(bitmap), "\(state.id) \(variant.name) drew a blank picture")
                    }
                }
            }
        }
        #expect(MeetingsSystem.liveUses.isEmpty, "a gallery scene built the real \(MeetingsSystem.liveUses.sorted())")
    }

    /// States whose pictures are the same on purpose: what tells them apart is the host's banner (issue #280).
    private static let aliasGroups: [Set<String>] = [
        [
            "ready-sonnet", "job-running", "failed-timed-out", "failed-network", "failed-rate-limited", "failed-other",
            "failed-too-long", "failed-model-not-available",
        ],
        ["incompatible-version", "newer-version"],
    ]

    @Test("a state is made fresh each time (every picture is exactly the same in another order) and states differ")
    func statesAreIndependent() async throws {
        let states = try #require(GalleryTestSupport.scenes.first).states
        var first: [String: NSBitmapImageRep] = [:]
        for state in states { first[state.id] = try await GalleryRenderer.render(state, Self.lightM) }
        for state in states.reversed() {
            let again = try await GalleryRenderer.render(state, Self.lightM)
            let (result, _) = GalleryDiff.compare(try #require(first[state.id]), again)
            #expect(result.passes(shareLimit: 0), "\(state.id) differs after the other states were drawn")
        }
        // Two states with the same picture must be declared aliases: otherwise a scene whose set-up never reaches the
        // view (or a golden that guards nothing new) goes unnoticed.
        var byPicture: [String: [String]] = [:]
        for state in states {
            let key = GalleryGoldens.sha256(try GalleryRenderer.pngData(try #require(first[state.id])))
            byPicture[key, default: []].append(state.id)
        }
        for ids in byPicture.values where ids.count > 1 {
            #expect(
                Self.aliasGroups.contains { Set(ids).isSubset(of: $0) },
                "\(ids.sorted()) draw the same picture; make the states differ or declare them aliases")
        }
    }

    @Test("the fake notes control counts calls and holds no data of its own")
    func theControlCounts() async {
        MeetingsSystem.installQuiet()
        let control = GalleryNotesControl(jobRunning: true)
        #expect(control.isBusy)
        await control.refreshAvailability()
        control.selectionChanged()
        control.regenerate(1)
        control.writeOnThisMac(1)
        #expect(control.calls == ["refreshAvailability", "selectionChanged", "regenerate", "writeOnThisMac"])
        #expect(!GalleryNotesControl().isBusy)
        #expect(
            MeetingsSystem.liveUses.isEmpty, "the fake control reached the real \(MeetingsSystem.liveUses.sorted())")
    }

    @Test("a provider chosen in a state shows the notice; Local with notes off shows nothing")
    func localWithNotesOffIsHidden() {
        let off = NotesProviderGalleryRig(NotesProviderGalleryCase(notesEnabled: false))
        #expect(!ProviderChoiceModel.surfacesProvider(notesEnabled: off.notes.enabled, isLocal: off.provider.isLocal))
        let claude = NotesProviderGalleryRig(
            NotesProviderGalleryCase(provider: (NotesProviderGallery.claude, "sonnet")))
        #expect(
            ProviderChoiceModel.surfacesProvider(notesEnabled: claude.notes.enabled, isLocal: claude.provider.isLocal))
    }
}

@MainActor
struct GoldenBudgetTests {
    /// 25 MB per folder of golden images (Q5): past it, the decision is LFS or fewer variants.
    static let budget = 25 * 1_024 * 1_024

    private func files() throws -> [URL] {
        guard
            let walker = FileManager.default.enumerator(at: GalleryTestSupport.goldens, includingPropertiesForKeys: nil)
        else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "png" }
    }

    @Test("the golden images fit the size budget")
    func underBudget() throws {
        let total = try files().reduce(0) { sum, url in
            sum + (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        }
        #expect(total <= Self.budget, "the goldens take \(total) bytes; the budget is \(Self.budget)")
    }

    @Test("no golden image belongs to a state that no longer exists")
    func noOrphans() throws {
        let expected = GalleryGoldens.expectedFiles(GalleryTestSupport.scenes)
        let root = GalleryTestSupport.goldens.standardizedFileURL.path + "/"
        let orphans = try files().map { String($0.standardizedFileURL.path.dropFirst(root.count)) }
            .filter { !expected.contains($0) }
        #expect(orphans.isEmpty, "delete these goldens: \(orphans.sorted())")
        if let manifest = GalleryGoldens.loadManifest(in: GalleryTestSupport.goldens) {
            let listed = Set(manifest.files.keys)
            #expect(listed.subtracting(expected).isEmpty, "goldens.json lists \(listed.subtracting(expected).sorted())")
        }
    }
}
#endif

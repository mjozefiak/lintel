#if DEBUG
import AppKit
import LintelUI
import Testing

@testable import MeetingsPlugin

/// The scenes of `MeetingsPlugin` for the design gallery: ids, summaries, that every state draws, and that none of
/// them touches the real system (spec `2026-11-23-swiftui-design-gallery`, "Edge Cases").
@MainActor
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

    @Test("every state draws something, and none of them reaches the real system")
    func everyStateDrawsWithoutTheRealSystem() async throws {
        MeetingsSystem.installQuiet()
        for scene in GalleryTestSupport.scenes {
            for state in scene.states {
                let bitmap = try await GalleryRenderer.render(state, Self.lightM)
                #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0, "\(state.id) is empty")
            }
        }
        #expect(MeetingsSystem.liveUses.isEmpty, "a gallery scene built the real \(MeetingsSystem.liveUses.sorted())")
    }

    @Test("a state is made fresh each time, so a render never sees an earlier state's models")
    func statesAreIndependent() async throws {
        let scene = try #require(GalleryTestSupport.scenes.first)
        let state = try #require(scene.states.first { $0.id == "ready-sonnet" })
        let first = try await GalleryRenderer.render(state, Self.lightM)
        let second = try await GalleryRenderer.render(state, Self.lightM)
        let (result, _) = GalleryDiff.compare(first, second)
        #expect(result.passes(shareLimit: 0))
    }

    @Test("the fake notes control counts calls and holds no data of its own")
    func theControlCounts() async {
        let control = GalleryNotesControl(jobRunning: true)
        #expect(control.isBusy)
        await control.refreshAvailability()
        control.selectionChanged()
        control.regenerate(1)
        control.writeOnThisMac(1)
        #expect(control.calls == ["refreshAvailability", "selectionChanged", "regenerate", "writeOnThisMac"])
        #expect(!GalleryNotesControl().isBusy)
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

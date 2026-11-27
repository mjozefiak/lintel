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
            "local", "local-model-missing", "local-model-downloading", "local-notes-off", "ready-sonnet", "ready-opus",
            "not-installed", "not-signed-in",
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
        ["ready-sonnet", "job-running"],
        // They draw the Failed · Last meeting row (not the picture of ready-sonnet); the reason is the banner's (#280).
        [
            "failed-timed-out", "failed-network", "failed-rate-limited", "failed-other", "failed-too-long",
            "failed-model-not-available",
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
        // The picture groups with more than one state ARE the declared alias groups, in both directions: a group that
        // falls apart (job-running starts to differ from ready-sonnet) makes its summary false, so it fails here too.
        let shared = Set(byPicture.values.filter { $0.count > 1 }.map { Set($0) })
        #expect(shared == Set(Self.aliasGroups), "the states that draw the same picture are \(shared)")
        for ids in byPicture.values where ids.count > 1 {
            #expect(
                Self.aliasGroups.contains { Set(ids) == $0 },
                "\(ids.sorted()) draw the same picture, which is not a declared alias group: make the states differ or declare them"
            )
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

/// A Git LFS pointer: the whole file a checkout without the LFS objects has (`version`, `oid`, `size`).
struct LFSPointer: Equatable {
    static let signature = "version https://git-lfs.github.com/spec/v1"

    var size: Int

    /// `nil` for anything that is not a pointer: a real picture, or a file only shaped like one.
    init?(data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let lines = text.split(whereSeparator: \.isNewline)
        guard lines.first.map(String.init) == Self.signature else { return nil }
        guard let sizeLine = lines.first(where: { $0.hasPrefix("size ") }) else { return nil }
        guard let size = Int(sizeLine.dropFirst("size ".count)) else { return nil }
        self.size = size
    }
}

@MainActor
struct GoldenBudgetTests {
    /// The pictures' own budget (spec `2026-11-23-swiftui-design-gallery` Q5, owner decision 2026-11-27): past it, the
    /// catalogue grew by accident and needs a decision. The pictures are Git LFS objects now, so this is not the
    /// repository's size: the account's Git LFS plan includes 10 GiB of storage, the budget is under 1 % of it, and the
    /// folder held 17.8 MiB on main before the two open gallery PRs (~31 MiB with both). A budget of plain git blobs
    /// (25 MB) no longer applies: recording a scene rewrites its pictures, and their versions stay in LFS.
    static let budget = 96 * 1_024 * 1_024

    private func files() throws -> [URL] {
        guard
            let walker = FileManager.default.enumerator(at: GalleryTestSupport.goldens, includingPropertiesForKeys: nil)
        else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "png" }
    }

    /// The size of a picture in the repository: the PNG itself, or the `size` line of its Git LFS pointer when the
    /// checkout has no LFS objects (a CI job that did not pull them, a clone without `git lfs install`).
    static func byteCount(ofGoldenAt url: URL) throws -> Int {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        if let head = try handle.read(upToCount: 256), let pointer = LFSPointer(data: head) { return pointer.size }
        return try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    }

    @Test("the golden images fit the size budget")
    func underBudget() throws {
        var total = 0
        var counted = 0
        for url in try files() {
            total += try Self.byteCount(ofGoldenAt: url)
            counted += 1
        }
        #expect(counted > 0, "no golden PNG was found: \(GalleryTestSupport.goldens.path)")
        #expect(total <= Self.budget, "the goldens take \(total) bytes; the budget is \(Self.budget)")
    }

    @Test("a golden counts as its picture whether the checkout holds the picture or its LFS pointer")
    func pointerSizesCount() throws {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "golden-budget-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pointer = """
            version https://git-lfs.github.com/spec/v1
            oid sha256:\(String(repeating: "a", count: 64))
            size 123456

            """
        let pointerURL = folder.appending(path: "pointer.png")
        try Data(pointer.utf8).write(to: pointerURL)
        #expect(try Self.byteCount(ofGoldenAt: pointerURL) == 123_456)
        let picture = Data(repeating: 0x89, count: 3_000)
        let pictureURL = folder.appending(path: "picture.png")
        try picture.write(to: pictureURL)
        #expect(try Self.byteCount(ofGoldenAt: pictureURL) == 3_000)
        // A file only shaped like a pointer is measured as it is.
        let broken = Data(pointer.replacingOccurrences(of: "size 123456", with: "size lots").utf8)
        let brokenURL = folder.appending(path: "broken.png")
        try broken.write(to: brokenURL)
        #expect(try Self.byteCount(ofGoldenAt: brokenURL) == broken.count)
    }

    @Test("every golden picture is stored as a Git LFS pointer, and .gitattributes covers it")
    func everyGoldenIsAnLFSObject() throws {
        let root = TestPaths.repoRoot.standardizedFileURL.path + "/"
        let paths = try files().map { url -> String in
            let path = url.standardizedFileURL.path
            #expect(path.hasPrefix(root), "\(path) is outside \(root)")
            return String(path.dropFirst(root.count))
        }
        #expect(!paths.isEmpty)

        // 1. The attribute: without a matching `.gitattributes` line a new picture is stored as a plain blob.
        let attributes = try Self.git(["check-attr", "filter", "diff", "merge", "--"] + paths, in: TestPaths.repoRoot)
        var attributeProblems: [String] = []
        var attributeSeen = Set<String>()
        for line in attributes.split(separator: "\n") {
            guard let match = line.firstMatch(of: /^(.+): (filter|diff|merge): (.*)$/) else {
                attributeProblems.append(String(line))
                continue
            }
            attributeSeen.insert(String(match.1))
            if match.3 != "lfs" { attributeProblems.append(String(line)) }
        }
        #expect(
            attributeProblems.isEmpty,
            "a golden PNG is not covered by the Git LFS attributes: \(attributeProblems.sorted().prefix(5))")
        #expect(attributeSeen == Set(paths), "git check-attr did not answer for every golden")

        // 2. The stored blob: `git check-attr` reads `.gitattributes` only, so it answers `lfs` for a picture that was
        //    committed as a plain blob too. Read what the index holds and require a pointer — the check that the
        //    attribute one cannot make. Works without git-lfs and with the filters installed.
        let blobs = try Self.indexedBlobs(for: paths)
        let missing = Set(paths).subtracting(blobs.keys)
        #expect(
            missing.isEmpty,
            "a golden PNG is not staged in the Git index (git add): \(missing.sorted().prefix(5))")
        var pointerProblems: [String] = []
        for (path, data) in blobs where LFSPointer(data: data) == nil {
            pointerProblems.append("\(path) (\(data.count) bytes)")
        }
        #expect(
            pointerProblems.isEmpty,
            "a golden PNG is stored as a plain blob, not a Git LFS pointer: \(pointerProblems.sorted().prefix(5))")
    }

    /// The bytes of the blobs the index holds for `paths`, keyed by repo-relative path. Reads the index
    /// (`git ls-files -s`) and the stored objects (`git cat-file --batch`), never the working tree: with the LFS
    /// filters installed the working tree holds the pictures even when a plain blob was committed, so only the stored
    /// object tells the truth. Needs neither git-lfs nor the filters.
    private static func indexedBlobs(for paths: [String]) throws -> [String: Data] {
        let listing = try git(["ls-files", "-s", "--"] + paths, in: TestPaths.repoRoot)
        var entries: [(path: String, oid: String)] = []
        for line in listing.split(separator: "\n") {
            // "<mode> <oid> <stage>\t<path>"
            guard let tab = line.firstIndex(of: "\t") else { continue }
            let fields = line[..<tab].split(separator: " ")
            guard fields.count >= 2 else { continue }
            entries.append((String(line[line.index(after: tab)...]), String(fields[1])))
        }
        guard !entries.isEmpty else { return [:] }
        let input = Data(entries.map { $0.oid + "\n" }.joined().utf8)
        let batch = try gitData(["cat-file", "--batch"], stdin: input, in: TestPaths.repoRoot)
        var blobs: [String: Data] = [:]
        var cursor = batch.startIndex
        for entry in entries {
            guard let newline = batch[cursor...].firstIndex(of: 0x0A) else { break }
            let header = batch[cursor..<newline]
            let fields = String(decoding: header, as: UTF8.self).split(separator: " ")
            let contentStart = batch.index(after: newline)
            guard fields.count == 3, let size = Int(fields[2]) else {
                // "<oid> missing": the object is not in the repository, so the path counts as missing.
                cursor = contentStart
                continue
            }
            let available = batch.distance(from: contentStart, to: batch.endIndex)
            let contentEnd = batch.index(contentStart, offsetBy: min(size, available))
            blobs[entry.path] = Data(batch[contentStart..<contentEnd])
            cursor = contentEnd < batch.endIndex ? batch.index(after: contentEnd) : batch.endIndex
        }
        return blobs
    }

    /// `git` in the repository, for the checks that read its attributes and its stored objects.
    private static func git(_ arguments: [String], in directory: URL) throws -> String {
        String(decoding: try gitData(arguments, stdin: Data(), in: directory), as: UTF8.self)
    }

    private static func gitData(_ arguments: [String], stdin: Data, in directory: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = ["git", "-C", directory.path] + arguments
        process.standardError = FileHandle.nullDevice
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        input.fileHandleForWriting.write(stdin)
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw GitFailure(status: process.terminationStatus, command: arguments.first ?? "")
        }
        return data
    }

    struct GitFailure: Error, CustomStringConvertible {
        var status: Int32
        var command: String
        var description: String { "git \(command) exited with \(status)" }
    }

    /// The folder is shared by every plugin's scenes (CI compares one folder); each plugin's test owns the scenes whose id
    /// starts with its own prefix and leaves the others alone.
    private static let prefix = "meetings."

    @Test("no golden image of this plugin belongs to a state that no longer exists")
    func noOrphans() throws {
        try expectNoOrphans(prefix: Self.prefix, scenes: GalleryTestSupport.scenes)
    }

    /// The shared components' scenes (`LintelUIGallery`, ids `ui.*`) record into the same folder; no plugin test owns
    /// them, so this one does, and a golden of a removed `ui.*` state cannot linger.
    @Test("no golden image of a shared UI scene belongs to a state that no longer exists")
    func noOrphansOfSharedUIScenes() throws {
        try expectNoOrphans(prefix: "ui.", scenes: LintelUIGallery.scenes)
    }

    private func expectNoOrphans(prefix: String, scenes: [GalleryScene]) throws {
        let expected = GalleryGoldens.expectedFiles(scenes)
        let root = GalleryTestSupport.goldens.standardizedFileURL.path + "/"
        let orphans = try files().map { String($0.standardizedFileURL.path.dropFirst(root.count)) }
            .filter { $0.hasPrefix(prefix) && !expected.contains($0) }
        #expect(orphans.isEmpty, "delete these goldens: \(orphans.sorted())")
        if let manifest = GalleryGoldens.loadManifest(in: GalleryTestSupport.goldens) {
            let listed = Set(manifest.files.keys).filter { $0.hasPrefix(prefix) }
            #expect(listed.subtracting(expected).isEmpty, "goldens.json lists \(listed.subtracting(expected).sorted())")
            #expect(
                expected.subtracting(listed).isEmpty,
                "goldens.json does not list \(expected.subtracting(listed).sorted())")
        }
    }
}
#endif

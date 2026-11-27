import Foundation
import Testing

/// The design gallery's golden PNGs are Git LFS objects (spec `2026-11-23-swiftui-design-gallery` Q5, owner decision
/// 2026-11-27). The two workflows that compare or record them must materialise the pictures, and their checkout must
/// not download them itself: `lfs: true` would transfer about 31 MiB on every run, and the account has 10 GiB of Git LFS
/// bandwidth a month. This suite reads the workflow files, like `CIWorkflowTests` and `ReleaseWorkflowTests`.
@Suite struct GalleryLFSWorkflowTests {
    private static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let workflows = ["ci.yml", "gallery-goldens.yml"]

    private func read(_ workflow: String) throws -> String {
        try String(contentsOf: Self.root.appending(path: ".github/workflows/\(workflow)"), encoding: .utf8)
    }

    /// The steps of a workflow: every `      - ` line starts one (the files keep steps at six spaces of indent).
    private func steps(_ workflow: String) throws -> [String] {
        var result: [String] = []
        for line in try read(workflow).components(separatedBy: "\n") {
            if line.hasPrefix("      - ") {
                result.append(line)
            } else if !result.isEmpty, line.hasPrefix("        ") || line.isEmpty {
                result[result.count - 1] += "\n" + line
            }
        }
        return result
    }

    private func step(_ workflow: String, named name: String) throws -> String {
        try #require(
            try steps(workflow).first { $0.hasPrefix("      - name: \(name)\n") },
            "\(workflow) has no step named \(name)")
    }

    /// The position of a step in the file, for the order of the LFS steps.
    private func index(of name: String, in workflow: String) throws -> Int {
        try #require(
            try steps(workflow).firstIndex { $0.hasPrefix("      - name: \(name)\n") },
            "\(workflow) has no step named \(name)")
    }

    /// The file without its comments: the comments say why `lfs: true` is not used, and only the settings count.
    private func settings(_ workflow: String) throws -> String {
        try read(workflow).components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            .joined(separator: "\n")
    }

    private static let key = "lfs-${{ runner.os }}-${{ steps.lfs.outputs.key }}"

    @Test("both workflows fetch the pictures through one cache keyed by the objects the commit needs")
    func bothWorkflowsUseTheLFSCache() throws {
        for workflow in Self.workflows {
            let text = try settings(workflow)
            #expect(!text.contains("lfs: true"), "\(workflow): the checkout downloads every golden on every run")
            let key = try step(workflow, named: "Golden images (Git LFS) key")
            #expect(
                key.contains("git lfs ls-files -l | cut -d' ' -f1 | sort | shasum -a 256"), "\(workflow): the key step")
            let restore = try step(workflow, named: "Restore the golden images (Git LFS)")
            #expect(restore.contains("id: lfs-cache"), "\(workflow): the restore step's id")
            #expect(restore.contains("uses: actions/cache/restore@"), "\(workflow): the restore")
            #expect(restore.contains("path: .git/lfs/objects"), "\(workflow): the cache path")
            #expect(restore.contains("key: \(Self.key)"), "\(workflow): the cache key")
            let save = try step(workflow, named: "Save the golden images (Git LFS)")
            #expect(save.contains("uses: actions/cache/save@"), "\(workflow): the save")
            #expect(
                save.contains("if: steps.lfs-cache.outputs.cache-hit != 'true'"), "\(workflow): the save condition")
            #expect(save.contains("key: \(Self.key)"), "\(workflow): the save key")
            let fetch = try step(workflow, named: "Fetch the golden images (Git LFS)")
            #expect(fetch.contains("        run: git lfs pull\n"), "\(workflow): the fetch")
            // The save has to hold the objects `git lfs pull` just downloaded, so it comes after it.
            let order = try [
                "Golden images (Git LFS) key", "Restore the golden images (Git LFS)",
                "Fetch the golden images (Git LFS)", "Save the golden images (Git LFS)",
            ].map { try index(of: $0, in: workflow) }
            #expect(order == order.sorted(), "\(workflow): the LFS steps are out of order")
        }
    }
}

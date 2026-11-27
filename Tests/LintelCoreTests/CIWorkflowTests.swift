import Foundation
import Testing

/// What must hold in `.github/workflows/ci.yml`, checked on the text of the file like `ReleaseWorkflowTests`: the
/// ruleset of `main` requires the job by name, every suite that has to pass under the Thread Sanitizer is in its one
/// run, and only a docs-only pull request may skip that run.
@Suite struct CIWorkflowTests {
    private static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    /// The suites that run under `--sanitize=thread` (once seven steps, now one filter). Removing a name here is a
    /// decision to stop checking that code for data races, not a cleanup.
    static let sanitizedSuites: Set<String> = [
        "PluginHostTests", "RecoveryOrderingTests", "PluginServicesTests",
        "NotesPluginTests",
        "FilesPluginTests",
        "SpeechEngineLeaseTests", "LLMLeaseTests", "ModelManagerRegistryTests", "ModelManagerQueueTests",
        "DictationSessionLeaseTests",
        "WindowEngineTests", "WindowEngineConcurrencyTests", "EventFlowTests", "EngineStopTests", "StopBudgetTests",
        "EchoAndJournalOrderTests", "RecoveryTests", "StartStopRaceTests", "WaiterLeakTests", "LayoutStrategyTests",
        "ToyStrategyTests", "TilingEngineTests", "ZoneEngineTests", "ZoneDragControllerTests", "ZoneDragSignalTests",
        "LintelProvidersTests", "ProviderNotesMatrixTests", "ProviderNotesGeneratorTests",
        "LintelTestSupportTests",
    ]

    private func workflow() throws -> String {
        try String(contentsOf: Self.root.appending(path: ".github/workflows/ci.yml"), encoding: .utf8)
    }

    /// The steps of the only job: every `      - ` line starts one (the file keeps steps at six spaces of indent).
    private func steps() throws -> [String] {
        var result: [String] = []
        for line in try workflow().components(separatedBy: "\n") {
            if line.hasPrefix("      - ") {
                result.append(line)
            } else if !result.isEmpty, line.hasPrefix("        ") || line.isEmpty {
                result[result.count - 1] += "\n" + line
            }
        }
        return result
    }

    private func step(named name: String) throws -> String {
        try #require(try steps().first { $0.hasPrefix("      - name: \(name)\n") }, "no step named \(name)")
    }

    @Test func theRequiredCheckKeepsItsNameAndIsOneJob() throws {
        let text = try workflow()
        #expect(text.contains("\njobs:\n  test:\n"))
        #expect(text.contains("\n    name: Build, test and lint\n"))
        // One job: a second one could carry the same check name and turn it green without the tests.
        let jobsBlock = try #require(text.components(separatedBy: "\njobs:\n").last)
        let jobs = jobsBlock.components(separatedBy: "\n").filter {
            $0.firstMatch(of: /^  [a-z][a-z0-9_-]*:\s*$/) != nil
        }
        #expect(jobs == ["  test:"])
        #expect(!text.contains("paths-ignore"))
        #expect(!text.contains("\n    paths:"))
    }

    @Test func everySanitizedSuiteRunsInTheOneSanitizerRun() throws {
        let text = try workflow()
        #expect(text.components(separatedBy: "--sanitize=thread").count == 2, "exactly one sanitizer run")
        let tsan = try step(named: "Test under Thread Sanitizer")
        let filter = try #require(tsan.firstMatch(of: /--filter "([^"]+)"/)).1
        let names = filter.split(separator: "|").map(String.init)
        #expect(Set(names) == Self.sanitizedSuites)
        #expect(names.count == Set(names).count, "no suite is named twice")
        #expect(names.allSatisfy { $0.firstMatch(of: /^[A-Za-z]+$/) != nil }, "plain names, no regex operators")
    }

    @Test func theSanitizerRunIsWatchedAndBuildsInItsOwnFolder() throws {
        let tsan = try step(named: "Test under Thread Sanitizer")
        #expect(tsan.contains("        run: scripts/test-with-watchdog.sh --limit "), "under the watchdog")
        #expect(tsan.contains(" --name tsan -- swift test --sanitize=thread --scratch-path .build-tsan --filter "))
        let limitMatch = try #require(tsan.firstMatch(of: #/--limit (\d+) --name tsan/#))
        let limit = try #require(Int(limitMatch.1))
        let minutesMatch = try #require(tsan.firstMatch(of: /timeout-minutes: (\d+)/))
        let minutes = try #require(Int(minutesMatch.1))
        // The step limit leaves the watchdog time to sample the hung processes and kill them (about 1 min).
        #expect(minutes * 60 >= limit + 120)
        let cache = try step(named: "Restore the Thread Sanitizer build cache")
        #expect(cache.contains("path: .build-tsan\n"))
    }

    @Test func onlyADocsOnlyPullRequestSkipsTheSanitizerRun() throws {
        let condition = "        if: steps.changes.outputs.docs_only != 'true'\n"
        for name in ["Restore the Thread Sanitizer build cache", "Test under Thread Sanitizer"] {
            #expect(try step(named: name).contains(condition), "\(name)")
        }
        // Every other step runs for every change: the tests read the docs.
        let conditional = try steps().filter { $0.contains("\n        if: ") }.map {
            $0.components(separatedBy: "\n")[0]
        }
        #expect(
            conditional == [
                // The LFS cache is saved only when the exact key was not restored (the pictures changed).
                "      - name: Save the golden images (Git LFS)",
                "      - name: Restore the Thread Sanitizer build cache", "      - name: Test under Thread Sanitizer",
                // The design gallery: its step does not fail the job itself (so it never hides the steps after it);
                // these two report a difference at the end.
                "      - name: Upload gallery diffs", "      - name: Fail on gallery differences",
                "      - name: Upload watchdog diagnostics",
            ])
        let classify = try step(named: "Classify changes")
        #expect(classify.contains("[ \"$GITHUB_EVENT_NAME\" = pull_request ]"))
        #expect(classify.contains("git diff --name-only --no-renames HEAD^1 HEAD"))
        #expect(classify.contains("scripts/ci-docs-only.sh"))
        #expect(try workflow().contains("          fetch-depth: 2\n"))
    }

    @Test func thePlainTestsStillRunEverything() throws {
        #expect(
            try step(named: "Test").contains(
                "        run: scripts/test-with-watchdog.sh --limit 800 --name test -- swift test\n"))
        #expect(try step(named: "Build").contains("        run: swift build\n"))
        #expect(try step(named: "Script tests").contains("        run: zsh scripts/tests/run.zsh\n"))
        #expect(try step(named: "Format lint").contains("        run: swift format lint --strict -r Sources Tests\n"))
    }

    @Test func theCachesAreKeyedOnTheToolchainAndThePins() throws {
        for (name, prefix) in [
            ("Restore the build cache", "build"), ("Restore the Thread Sanitizer build cache", "build-tsan"),
        ] {
            let cache = try step(named: name)
            #expect(cache.contains("uses: actions/cache@"))
            #expect(
                cache.contains(
                    "key: \(prefix)-${{ runner.os }}-${{ runner.arch }}-${{ steps.toolchain.outputs.id }}-"
                        + "${{ hashFiles('Package.resolved') }}\n"))
        }
    }
}

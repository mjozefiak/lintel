#if DEBUG
import AppKit
import CryptoKit
import SwiftUI
import Testing

@testable import LintelUI

/// A pane with the controls that `ImageRenderer` cannot draw: a grouped `Form`, `Toggle`, `TextField`, `Picker`.
private struct ControlsPane: View {
    @State private var on = true
    @State private var text = "Orchard weekly sync"

    var body: some View {
        Form {
            Section {
                Toggle("Write notes after a meeting", isOn: $on)
                TextField("Title", text: $text)
                Picker("Model", selection: .constant(1)) {
                    Text("One").tag(1)
                    Text("Two").tag(2)
                }
            } header: {
                Text("Basics").settingsSectionHeader()
            }
        }
        .formStyle(.grouped)
        .lintelFormSurfaces()
    }
}

private func state(
    _ id: String = "controls", presentation: GalleryPresentation = .window(width: 480, height: 260),
    view: @escaping @MainActor @Sendable () -> AnyView = { AnyView(ControlsPane()) }
) -> GalleryState {
    GalleryState(id: id, summary: "A pane with controls", presentation: presentation, make: view)
}

private let lightM = GalleryVariant(appearance: .light, textSize: .medium, language: "en")
private let darkM = GalleryVariant(appearance: .dark, textSize: .medium, language: "en")

private func digest(_ bitmap: NSBitmapImageRep) -> String {
    guard let bytes = GalleryPixels(bitmap)?.bytes else { return "" }
    return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
}

/// A view whose model changes every few milliseconds for as long as `running`: it never settles.
@MainActor @Observable private final class Flicker {
    var tick = 0
    var running = true

    private var started = false

    /// Called when the view appears, so a render waiting behind the gate does not load the main actor meanwhile.
    func start() {
        guard !started else { return }
        started = true
        Task { @MainActor [weak self] in
            while let self, self.running {
                self.tick += 1
                try? await Task.sleep(for: .milliseconds(3))
            }
        }
    }
}

private struct FlickerView: View {
    let model: Flicker
    var body: some View {
        Text(verbatim: "tick \(model.tick)").frame(width: 200, height: 40).onAppear { model.start() }
    }
}

@MainActor
struct GalleryRendererTests {
    @Test("a pane with a Form, Toggle and TextField draws pixels for the controls")
    func controlsAreDrawn() async throws {
        let withControls = try await GalleryRenderer.render(state(), lightM)
        let empty = try await GalleryRenderer.render(
            state(view: { AnyView(Color.clear) }), lightM)
        let (result, _) = GalleryDiff.compare(withControls, empty)
        #expect(result.sizeMatches)
        // The controls are a large part of the pane: far more than the diff limit.
        #expect(result.differingShare > 0.05)
    }

    @Test("the bitmap is 2x whatever the machine's displays say")
    func scaleIsForced() async throws {
        let bitmap = try await GalleryRenderer.render(state(), lightM)
        #expect(bitmap.pixelsWide == 960)
        #expect(bitmap.pixelsHigh == 520)
        #expect(bitmap.size == NSSize(width: 480, height: 260))
    }

    @Test("light and dark draw differently")
    func appearanceMatters() async throws {
        let light = try await GalleryRenderer.render(state(), lightM)
        let dark = try await GalleryRenderer.render(state(), darkM)
        let (result, _) = GalleryDiff.compare(light, dark)
        #expect(result.differingShare > 0.3)
    }

    @Test("the same state rendered 20 times in one process is the same picture")
    func renderIsDeterministic() async throws {
        var digests = Set<String>()
        var drawing = Duration.zero
        for _ in 0..<20 {
            digests.insert(digest(try await GalleryRenderer.render(state(), lightM)))
            drawing += GalleryRenderer.lastDrawDuration
        }
        #expect(digests.count == 1, "20 renders gave \(digests.count) different pictures")
        // Measurement for docs/perf.md; printed, not asserted. Only the time a render held the gate counts, not the
        // time it waited behind other suites' renders.
        print("GALLERY-PERF 20 renders of the controls pane, drawing only: \(drawing)")
        if let path = ProcessInfo.processInfo.environment["LINTEL_GALLERY_DIGEST_FILE"], let one = digests.first {
            try? one.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    @Test("a variant in another language than the process is not drawn")
    func languageMismatch() async throws {
        let polish = GalleryVariant(appearance: .light, textSize: .medium, language: "pl")
        let process = GalleryRenderer.processLanguage
        #expect(process == "en", "swift test runs in the test runner's bundle, which has no Polish catalog")
        await #expect(throws: GalleryError.languageMismatch(state: "controls", variant: "light-m-pl", process: "en")) {
            _ = try await GalleryRenderer.render(state(), polish)
        }
    }

    @Test("a popover, a sheet and a HUD are drawn on an opaque backdrop")
    func presentationsDrawContent() async throws {
        let label: @MainActor @Sendable () -> AnyView = {
            AnyView(Text(verbatim: "Hello").padding(12).frame(minWidth: 80))
        }
        let popover = try await GalleryRenderer.render(
            state("p", presentation: .popover(width: 200), view: label), lightM)
        let sheet = try await GalleryRenderer.render(state("s", presentation: .sheet(width: 300), view: label), lightM)
        let hud = try await GalleryRenderer.render(state("h", presentation: .hud(shape: .capsule), view: label), lightM)
        for bitmap in [popover, sheet, hud] {
            #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
            let centre = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2))
            #expect(centre.alphaComponent == 1)
        }
        // A capsule HUD keeps its corners transparent.
        let corner = try #require(hud.colorAt(x: 0, y: 0))
        #expect(corner.alphaComponent == 0)
    }

    @Test("a state that stays at zero size is an error, not an empty PNG")
    func emptyRenderIsAnError() async throws {
        let zero = state("zero", presentation: .window(width: 100, height: 0))
        await #expect(throws: GalleryError.emptyRender("zero")) {
            _ = try await GalleryRenderer.render(zero, lightM)
        }
    }

    @Test("a view that never stops changing is an error, not a picture")
    func anUnsettledViewIsAnError() async {
        let model = Flicker()
        defer { model.running = false }
        let flicker = state("flicker", view: { AnyView(FlickerView(model: model)) })
        await #expect(throws: GalleryError.didNotSettle("flicker")) {
            _ = try await GalleryRenderer.render(flicker, lightM, maxAttempts: 25)
        }
    }

    @Test("renders started together run one after the other and all come out the same")
    func rendersStartedTogetherAreSerialized() async throws {
        // Three main-actor tasks started together: the gate lets them in one at a time.
        let tasks = (0..<3).map { _ in Task { @MainActor in digest(try await GalleryRenderer.render(state(), lightM)) }
        }
        var digests = Set<String>()
        for task in tasks { digests.insert(try await task.value) }
        #expect(digests.count == 1)
        #expect(GalleryRenderer.peakInFlight == 1, "the gate lets one render in at a time")
    }

    @Test("a render cancelled while it waits for the gate does not strand the next one")
    func aCancelledRenderReleasesTheGate() async throws {
        let first = Task { @MainActor in try await GalleryRenderer.render(state(), lightM).pixelsWide }
        let second = Task { @MainActor in try await GalleryRenderer.render(state(), lightM).pixelsWide }
        second.cancel()
        _ = try? await second.value
        _ = try await first.value
        let later = try await GalleryRenderer.render(state(), lightM)
        #expect(later.pixelsWide > 0)
    }
}
#endif

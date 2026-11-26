#if DEBUG
import SwiftUI

/// DEBUG only: the design gallery scenes of the shared UI components (spec `2026-11-24-notes-explorer-main-window`, step
/// 2.1: the ring's window states). They draw the real `LintelRing` over no data at all. The turning and the breathing
/// are Core Animation layer animations: the live gallery shows them moving, and a picture (`cacheDisplay`) draws the
/// layer's model values, so it is always the first frame.
public enum LintelUIGallery {
    @MainActor public static var scenes: [GalleryScene] { [LintelRingGallery.scene] }
}

/// One state of the ring: a row for a meeting mark and a row for a dictation mark, each at three sizes (a row mark,
/// a button, a panel), with the state's own spoken name beside it. The names are the real `LintelRingLabels`, so the
/// sheet shows the English and the Polish words VoiceOver says.
private struct LintelRingSheet: View {
    let title: String
    let rows: [(state: LintelRingState, label: String?)]
    let motion: LintelRingMotion
    /// The rings sit on a Verdigris fill, like the Record button.
    var onAccent = false

    @Environment(\.lintelTextSize) private var textSize
    static let sizes: [CGFloat] = [16, 28, 64]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                ForEach([LintelRingMark.meeting, .dictation], id: \.self) { mark in
                    HStack(spacing: 14) {
                        HStack(alignment: .center, spacing: 12) {
                            ForEach(Self.sizes, id: \.self) { size in
                                LintelRing(row.state, mark: mark, baseSize: size, onAccentFill: onAccent)
                                    .frame(width: 70 * textSize.scale, height: 70 * textSize.scale)
                            }
                        }
                        Text(row.label ?? LintelRingLabels.label(state: row.state, mark: mark))
                            .font(textSize.font(.body))
                            .foregroundStyle(onAccent ? LintelBrand.onAccent : .primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(onAccent ? LintelBrand.accent : .clear)
        .environment(\.lintelRingMotion, motion)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

@MainActor enum LintelRingGallery {
    static var scene: GalleryScene {
        GalleryScene(id: "ui.ring", title: "LintelRing: the working ring", states: states)
    }

    private static let window = GalleryPresentation.window(width: 560)

    private static func state(
        _ id: String, _ summary: String, _ states: [LintelRingState], motion: LintelRingMotion = .frozen,
        onAccent: Bool = false
    ) -> GalleryState {
        GalleryState(
            id: id, summary: summary, presentation: window
        ) {
            AnyView(LintelRingSheet(title: id, rows: states.map { ($0, nil) }, motion: motion, onAccent: onAccent))
        }
    }

    static var states: [GalleryState] {
        [
            state(
                "idle",
                "Idle: the static cut ring, in the quiet colour. A meeting has the centre dot, a dictation has none. The Record button and the type mark of a row.",
                [.idle]),
            state(
                "listening",
                "Listening: a Verdigris ring (turning slowly live; the picture is one frame) and, for a meeting, the breathing centre dot. The live pill, the Now row, the recording panel.",
                [.listening]),
            state(
                "warning",
                "Warning (silence, the call is not heard): the ring keeps turning in Verdigris and only the centre dot is amber; a dictation ring gets the dot too. The text that says what is wrong is always beside it.",
                [.warning]),
            state(
                "processing",
                "Processing with a known progress: the ring closes, at 0, 25, 50, 75 and 100 percent. The row of a meeting being transcribed or written.",
                [0, 0.25, 0.5, 0.75, 1].map { .processing(progress: $0) }),
            state(
                "processing-unknown",
                "Processing with no known progress: a short arc that sweeps round (the picture is one frame).",
                [.processing(progress: nil)]),
            state(
                "error",
                "Error: an open ring in the error colour with a wider opening than the idle ring, no dot, never colour alone. The row Notes not written, a failed recording.",
                [.error]),
            state(
                "on-verdigris",
                "On a Verdigris fill, as on the Record button: idle, listening and processing in the on-accent colour (white in light, the dark surface colour in dark). A warning or an error is not drawn on the fill.",
                [.idle, .listening, .processing(progress: 0.5)], onAccent: true),
            state(
                "reduced-motion",
                "Reduce Motion: nothing turns or breathes; the sweep without a known progress becomes a static half ring. Listening, warning and processing shown as the system draws them with Reduce Motion on.",
                [.listening, .warning, .processing(progress: nil)], motion: .reduced),
        ]
    }
}
#endif

import AppKit
import SwiftUI

/// The ring of the Lintel mark on its 256-point grid: an outer radius of 112, an inner radius of 66 and a 60° cut
/// centred on the upper left (-135°), so the edges of the cut sit on multiples of 15°. The small cut (menu bar,
/// 24 pt and below) has a thinner ring so the core stays readable. `sweep` draws only the first part of the open
/// ring, from the clockwise edge of the cut (a closing ring); `cutWidth` opens it wider (the error ring).
public nonisolated struct LintelRingShape: Shape {
    public var small: Bool
    public var cutWidth: Double
    public var sweep: Double

    public static let outerRadius: CGFloat = 112
    public static let innerRadius: CGFloat = 66
    public static let smallOuterRadius: CGFloat = 116
    public static let smallInnerRadius: CGFloat = 60
    public static let cutCenter: Double = -135
    public static let cutWidth: Double = 60
    /// The core's diameter on the 256 grid.
    public static let coreDiameter: CGFloat = 68
    public static let smallCoreDiameter: CGFloat = 80

    public init(small: Bool = false, cutWidth: Double = LintelRingShape.cutWidth, sweep: Double = 1) {
        self.small = small
        self.cutWidth = cutWidth
        self.sweep = sweep
    }

    public func path(in rect: CGRect) -> Path {
        guard sweep > 0.0001 else { return Path() }
        let unit = min(rect.width, rect.height) / 256
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = (small ? Self.smallOuterRadius : Self.outerRadius) * unit
        let inner = (small ? Self.smallInnerRadius : Self.innerRadius) * unit
        let start = Self.cutCenter + cutWidth / 2
        let fullEnd = Self.cutCenter - cutWidth / 2 + 360
        let end = start + min(sweep, 1) * (fullEnd - start)
        func point(_ radius: CGFloat, _ degrees: Double) -> CGPoint {
            CGPoint(
                x: center.x + radius * CGFloat(cos(degrees * .pi / 180)),
                y: center.y + radius * CGFloat(sin(degrees * .pi / 180)))
        }
        var path = Path()
        path.move(to: point(outer, start))
        // SwiftUI measures `clockwise` as if y pointed up, so the on-screen clockwise sweep is `false`.
        path.addArc(
            center: center, radius: outer, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        path.addLine(to: point(inner, end))
        path.addArc(
            center: center, radius: inner, startAngle: .degrees(end), endAngle: .degrees(start), clockwise: true)
        path.closeSubpath()
        return path
    }
}

extension EnvironmentValues {
    /// How every `LintelRing` below moves (`.system`: the system's Reduce Motion). A gallery picture sets `.frozen`.
    @Entry public var lintelRingMotion: LintelRingMotion = .system
}

/// The working ring: the Lintel mark's cut ring in five looks (`LintelRingState`), drawn as Core Animation layers so
/// the turning and the breathing run on the render server and SwiftUI never redraws it per frame. Static under
/// Reduce Motion. It draws no text: the word (or the time, or the percent) always stands beside it, and the
/// accessibility label says the same.
public struct LintelRing: View {
    private let state: LintelRingState
    private let mark: LintelRingMark
    private let baseSize: CGFloat
    private let label: String?
    private let onAccentFill: Bool

    @Environment(\.lintelTextSize) private var textSize
    @Environment(\.lintelRingMotion) private var motion
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    /// - Parameters:
    ///   - baseSize: points at the S and M text sizes; the ring grows with L and XL.
    ///   - onAccentFill: the ring is drawn on a Verdigris fill (the Record button), so it uses `onAccent`.
    ///   - accessibilityLabel: what the screen knows and the ring does not ("Recording, 12 minutes"); the default
    ///     is the state's own words (`LintelRingLabels`).
    public init(
        _ state: LintelRingState, mark: LintelRingMark = .meeting, baseSize: CGFloat = 16,
        onAccentFill: Bool = false, accessibilityLabel: String? = nil
    ) {
        self.state = state
        self.mark = mark
        self.baseSize = baseSize
        self.onAccentFill = onAccentFill
        self.label = accessibilityLabel
    }

    public var body: some View {
        let points = LintelRingMetrics.points(base: baseSize, textSize: textSize)
        let reduce = motion == .reduced || (motion == .system && systemReduceMotion)
        let appearance = LintelRingAppearance(
            state: state, mark: mark, reduceMotion: reduce, onAccentFill: onAccentFill)
        RingLayers(
            appearance: appearance, small: LintelRingMetrics.usesSmallCut(points: points),
            animates: motion != .frozen
        )
        .frame(width: points, height: points)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? LintelRingLabels.label(state: state, mark: mark))
        .accessibilityAddTraits(.isImage)
    }
}

/// The spoken name of each state, used when the screen has nothing more specific to say.
public enum LintelRingLabels {
    public static func label(state: LintelRingState, mark: LintelRingMark) -> String {
        switch state {
        case .idle:
            mark == .meeting
                ? String(localized: "Meeting", comment: "Spoken name of the idle ring of a meeting")
                : String(localized: "Dictation", comment: "Spoken name of the idle ring of a dictation")
        case .listening:
            mark == .meeting
                ? String(localized: "Recording", comment: "Spoken name of the turning ring while a meeting is recorded")
                : String(localized: "Dictating", comment: "Spoken name of the turning ring while the user dictates")
        case .warning:
            mark == .meeting
                ? String(
                    localized: "Recording, needs attention",
                    comment: "Spoken name of the turning ring with the amber dot")
                : String(
                    localized: "Dictating, needs attention",
                    comment: "Spoken name of the turning ring of a dictation with the amber dot")
        case .processing(let progress):
            if let progress = LintelRingAppearance.clamped(progress) {
                String(
                    localized: "Working, \(LintelRingAppearance.percent(progress)) percent",
                    comment: "Spoken name of the closing ring with a progress, e.g. 60 percent")
            } else {
                String(localized: "Working", comment: "Spoken name of the closing ring without a known progress")
            }
        case .error:
            String(localized: "Something went wrong", comment: "Spoken name of the open ring in the error colour")
        }
    }
}

/// The layers: a faint track, the arc (turning when the look says so) and the centre dot (breathing when it says so).
private struct RingLayers: NSViewRepresentable {
    let appearance: LintelRingAppearance
    let small: Bool
    let animates: Bool

    func makeNSView(context: Context) -> RingLayerView { RingLayerView() }

    func updateNSView(_ view: RingLayerView, context: Context) {
        view.configure(appearance: appearance, small: small, animates: animates)
    }
}

@MainActor
final class RingLayerView: NSView {
    static let turnKey = "lintel.ring.turn"
    static let breatheKey = "lintel.ring.breathe"

    private let spinLayer = CALayer()
    private let trackLayer = CAShapeLayer()
    private let arcLayer = CAShapeLayer()
    private let dotLayer = CAShapeLayer()
    private(set) var look: LintelRingAppearance?
    private var small = false
    private var animates = true

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(spinLayer)
        spinLayer.addSublayer(trackLayer)
        spinLayer.addSublayer(arcLayer)
        layer?.addSublayer(dotLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// What the layers hold, for tests: the keys of the running animations.
    var runningAnimationKeys: Set<String> {
        Set(
            [
                spinLayer.animation(forKey: Self.turnKey) != nil ? Self.turnKey : nil,
                dotLayer.animation(forKey: Self.breatheKey) != nil ? Self.breatheKey : nil,
            ].compactMap { $0 })
    }

    func configure(appearance: LintelRingAppearance, small: Bool, animates: Bool) {
        guard appearance != self.look || small != self.small || animates != self.animates else { return }
        self.look = appearance
        self.small = small
        self.animates = animates
        rebuild()
    }

    override func layout() {
        super.layout()
        rebuild()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        rebuild()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // A layer's animations do not survive leaving a window (a tab switch, a reused row).
        applyAnimations()
    }

    private func rebuild() {
        guard let appearance = look, bounds.width > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let rect = CGRect(origin: .zero, size: bounds.size)
        let side = min(rect.width, rect.height)
        let square = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        spinLayer.bounds = CGRect(origin: .zero, size: square.size)
        spinLayer.position = CGPoint(x: square.midX, y: square.midY)
        // AppKit layers are y-up and the ring is built y-down: flip once, here.
        let flip = CGAffineTransform(translationX: 0, y: side).scaledBy(x: 1, y: -1)
        let local = CGRect(origin: .zero, size: square.size)
        func path(_ sweep: Double) -> CGPath {
            LintelRingShape(small: small, cutWidth: appearance.cutWidth, sweep: sweep).path(in: local)
                .cgPath.copy(using: [flip]) ?? CGPath(rect: .zero, transform: nil)
        }
        for sublayer in [trackLayer, arcLayer] { sublayer.frame = local }
        trackLayer.path = path(1)
        trackLayer.fillColor = Self.cgColor(LintelBrand.hairlineColor, in: self)
        trackLayer.isHidden = !appearance.showsTrack
        arcLayer.path = path(appearance.sweep)
        arcLayer.fillColor = Self.cgColor(appearance.ringTone, in: self)

        let unit = side / 256
        let diameter = (small ? LintelRingShape.smallCoreDiameter : LintelRingShape.coreDiameter) * unit
        dotLayer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        dotLayer.position = CGPoint(x: square.midX, y: square.midY)
        dotLayer.path = CGPath(ellipseIn: dotLayer.bounds, transform: nil)
        dotLayer.isHidden = appearance.dotTone == nil
        if let tone = appearance.dotTone { dotLayer.fillColor = Self.cgColor(tone, in: self) }
        applyAnimations()
    }

    private func applyAnimations() {
        spinLayer.removeAnimation(forKey: Self.turnKey)
        dotLayer.removeAnimation(forKey: Self.breatheKey)
        guard animates, window != nil, let appearance = look else { return }
        if let seconds = appearance.secondsPerTurn {
            let turn = CABasicAnimation(keyPath: "transform.rotation.z")
            turn.fromValue = 0
            // Negative: layers are y-up, so this is the clockwise turn on screen.
            turn.toValue = -2 * Double.pi
            turn.duration = seconds
            turn.repeatCount = .infinity
            turn.isRemovedOnCompletion = false
            spinLayer.add(turn, forKey: Self.turnKey)
        }
        if appearance.dotBreathes {
            let breathe = CABasicAnimation(keyPath: "opacity")
            breathe.fromValue = 1
            breathe.toValue = 0.4
            breathe.duration = 1.6
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            breathe.isRemovedOnCompletion = false
            dotLayer.add(breathe, forKey: Self.breatheKey)
        }
    }

    private static func cgColor(_ tone: LintelRingAppearance.Tone, in view: NSView) -> CGColor {
        let color: NSColor =
            switch tone {
            case .quiet: LintelBrand.secondaryTextColor
            case .ink: LintelBrand.inkColor
            case .live: LintelBrand.accentColor
            case .attention: LintelBrand.statusAttentionColor
            case .error: LintelBrand.statusErrorColor
            case .onAccent: LintelBrand.onAccentColor
            }
        return cgColor(color, in: view)
    }

    private static func cgColor(_ color: NSColor, in view: NSView) -> CGColor {
        var resolved = color.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance { resolved = color.cgColor }
        return resolved
    }
}

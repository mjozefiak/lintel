import SwiftUI

/// What the access page shows: the rail, one row per permission the chosen goal needs, and the footer's button.
public nonisolated struct OnboardingAccessState: Equatable, Sendable {
    public var rail: OnboardingStepRailState
    public var rows: [OnboardingAccessRow]
    /// Lintel runs from the disk image or a translocated path: grants given there are lost, so the rows give way
    /// to one "Move Lintel to Applications first" row (R9).
    public var needsMoveToApplications: Bool
    public var primaryTitle: String

    public init(
        rail: OnboardingStepRailState, rows: [OnboardingAccessRow], needsMoveToApplications: Bool = false,
        primaryTitle: String
    ) {
        self.rail = rail
        self.rows = rows
        self.needsMoveToApplications = needsMoveToApplications
        self.primaryTitle = primaryTitle
    }

    /// Every needed permission is allowed (a row that is not needed does not count).
    public var allAllowed: Bool {
        let needed = rows.filter { $0.state != .notNeededNow }
        return !needed.isEmpty && needed.allSatisfy { $0.state == .allowed }
    }
}

/// Step 3, "Lintel needs your OK for a few things" (prototype `onb.access`, C14): a row per permission with the
/// reason in plain words and one of three states, Allowed with a check, Needs your OK with an Allow button, or
/// Not needed now. The footer's button is never disabled: any row can be skipped and allowed later in Settings.
/// Pure view over a value state; it asks for nothing itself, the shell does when `onAllow` fires.
public struct OnboardingAccessPage: View {
    private let state: OnboardingAccessState
    private let onAllow: (String) -> Void
    private let onCheckAgain: (String) -> Void
    private let onMove: () -> Void
    private let onBack: () -> Void
    private let onPrimary: () -> Void
    @Environment(\.lintelTextSize) private var textSize

    public init(
        _ state: OnboardingAccessState,
        onAllow: @escaping (String) -> Void = { _ in },
        onCheckAgain: @escaping (String) -> Void = { _ in },
        onMove: @escaping () -> Void = {},
        onBack: @escaping () -> Void = {},
        onPrimary: @escaping () -> Void = {}
    ) {
        self.state = state
        self.onAllow = onAllow
        self.onCheckAgain = onCheckAgain
        self.onMove = onMove
        self.onBack = onBack
        self.onPrimary = onPrimary
    }

    public static var heading: String {
        String(localized: "Lintel needs your OK for a few things", comment: "Onboarding access page heading")
    }

    public static var subheading: String {
        String(localized: "macOS asks you to confirm each one.", comment: "Onboarding access page line")
    }

    public static var skipNote: String {
        String(
            localized: "You can skip any of these and allow them later in Settings → Privacy & data.",
            comment: "Onboarding access page: nothing here is forced")
    }

    public static var needsYourOK: String {
        String(localized: "Needs your OK", comment: "Onboarding permission state: not allowed yet")
    }

    public static var notNeededNow: String {
        String(localized: "Not needed now", comment: "Onboarding permission state: the chosen goal does not use it")
    }

    public static var allow: String {
        String(localized: "Allow", comment: "Onboarding button that asks for a permission")
    }

    public static var allowed: String { String(localized: "Allowed", comment: "Permission state") }

    public static var checkFailedText: String {
        String(
            localized:
                "Lintel couldn't hear the test sound. Turn up the volume or pick your speakers, then Check Again.",
            comment: "Onboarding: the call audio check did not hear the sound")
    }

    public static var checkAgain: String { String(localized: "Check Again", comment: "Button that repeats a check") }

    public static var checking: String { String(localized: "Checking…", comment: "A check is running") }

    public static var moveFirst: String {
        String(
            localized: "Move Lintel to Applications first",
            comment: "Onboarding access page: Lintel runs from the disk image, so grants would be lost")
    }

    public static var moveFirstReason: String {
        String(
            localized: "macOS remembers your choices only for the copy in Applications.",
            comment: "Onboarding access page: why the move comes first")
    }

    public static var moveButton: String {
        String(localized: "Move to Applications", comment: "Onboarding button that moves the app to Applications")
    }

    public var body: some View {
        OnboardingWindowFrame(
            rail: state.rail, heading: Self.heading, subheading: Self.subheading,
            primaryTitle: state.primaryTitle, showsBack: true, onBack: onBack, onPrimary: onPrimary
        ) {
            OnboardingGroup {
                if state.needsMoveToApplications {
                    moveRow
                } else {
                    ForEach(Array(state.rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { LintelDivider() }
                        rowView(row)
                    }
                }
            }
            if !state.needsMoveToApplications {
                OnboardingNote(text: Self.skipNote)
            }
        }
    }

    private var moveRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.moveFirst)
                    .font(textSize.font(.title3, weight: .semibold))
                    .foregroundStyle(LintelBrand.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Self.moveFirstReason)
                    .foregroundStyle(LintelBrand.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onMove) { Text(Self.moveButton) }
                .buttonStyle(LintelSecondaryButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private func rowView(_ row: OnboardingAccessRow) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(textSize.font(.title3, weight: .semibold))
                    .foregroundStyle(row.state == .notNeededNow ? LintelBrand.secondaryText : LintelBrand.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if row.state == .checkFailed {
                    // What happened and what to do, across the whole row; the repair button goes under it, so
                    // the sentence is not squeezed beside the button at the largest text size.
                    Label {
                        Text(Self.checkFailedText).foregroundStyle(LintelBrand.ink)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(LintelBrand.statusAttention)
                            .accessibilityHidden(true)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    control(row).padding(.top, 4)
                } else {
                    Text(row.reason)
                        .foregroundStyle(LintelBrand.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if row.state != .checkFailed { control(row) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func control(_ row: OnboardingAccessRow) -> some View {
        switch row.state {
        case .allowed:
            Label {
                Text(Self.allowed).foregroundStyle(LintelBrand.ink)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(LintelBrand.statusOk)
                    .accessibilityHidden(true)
            }
            .fixedSize()
        case .needsOK:
            HStack(spacing: 10) {
                Text(Self.needsYourOK)
                    .foregroundStyle(LintelBrand.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    onAllow(row.id)
                } label: {
                    Text(Self.allow)
                }
                .buttonStyle(LintelSecondaryButtonStyle())
                .accessibilityLabel("\(Self.allow), \(row.title)")
            }
        case .notNeededNow:
            Text(Self.notNeededNow)
                .foregroundStyle(LintelBrand.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        case .checking:
            HStack(spacing: 8) {
                LintelRing(.processing(progress: nil), mark: .meeting, baseSize: 16)
                Text(Self.checking).foregroundStyle(LintelBrand.ink)
            }
            .accessibilityElement(children: .combine)
        case .checkFailed:
            Button {
                onCheckAgain(row.id)
            } label: {
                Text(Self.checkAgain)
            }
            .buttonStyle(LintelSecondaryButtonStyle())
            .accessibilityLabel("\(Self.checkAgain), \(row.title)")
        }
    }
}

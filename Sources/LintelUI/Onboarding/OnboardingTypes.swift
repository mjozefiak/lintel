import SwiftUI

/// The measurements of the onboarding window (spec `2026-11-24-first-run-onboarding`, section 2; prototype `.onbw`,
/// `.oside`, `.obody`, `.ofoot`): one 820 x 580 window, a 240 pt step rail on the left, the page and its footer on
/// the right.
public nonisolated enum OnboardingLayout {
    public static let windowWidth: CGFloat = 820
    public static let windowHeight: CGFloat = 580
    public static let railWidth: CGFloat = 240
    /// The page's inset (prototype `.obody` padding: 44 pt on the sides).
    public static let bodyInset: CGFloat = 44
    /// The top of the page: less than the sides so that the longest Polish page still fits at XL.
    public static let bodyTopInset: CGFloat = 32
    public static let footerHorizontalPadding: CGFloat = 20
    public static let footerVerticalPadding: CGFloat = 14
    public static let cornerRadius: CGFloat = 10
}

/// What the user wants Lintel to do (step 1). The page draws the three choices; what a choice turns on or off is
/// the shell's business, never the view's. Raw values are the spec's `app.onboarding.goal` values.
public nonisolated enum OnboardingGoalChoice: String, CaseIterable, Identifiable, Sendable {
    case dictation
    case meetingNotes
    case both

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dictation:
            String(localized: "Type what I say", comment: "Onboarding goal choice: dictation")
        case .meetingNotes:
            String(localized: "Write my meeting notes", comment: "Onboarding goal choice: meeting notes")
        case .both:
            String(localized: "Both", comment: "Onboarding goal choice: dictation and meeting notes")
        }
    }

    public var detail: String {
        switch self {
        case .dictation:
            String(
                localized: "Hold a key and talk. Your words appear in any app.",
                comment: "Onboarding goal choice: what dictation does")
        case .meetingNotes:
            String(
                localized: "Lintel listens to your calls and writes the notes.",
                comment: "Onboarding goal choice: what meeting notes do")
        case .both:
            String(
                localized: "You can turn either one off later.",
                comment: "Onboarding goal choice: both features, reversible")
        }
    }

    /// The footer's one button names its result (owner decision 5).
    public var primaryTitle: String {
        switch self {
        case .dictation:
            String(localized: "Set Up Dictation", comment: "Onboarding goal page button for the dictation goal")
        case .meetingNotes:
            String(
                localized: "Set Up Meeting Notes", comment: "Onboarding goal page button for the meeting notes goal")
        case .both:
            String(localized: "Set Up Both", comment: "Onboarding goal page button when both goals are chosen")
        }
    }
}

/// The words of the footer's primary button on the steps after the goal. Each names what happens next.
public nonisolated enum OnboardingPrimaryTitles {
    public static var allowAccess: String {
        String(localized: "Next: Allow Access", comment: "Onboarding privacy page button")
    }

    public static var tryDictation: String {
        String(localized: "Next: Try Dictation", comment: "Onboarding access page button before the dictation step")
    }

    public static var firstMeeting: String {
        String(localized: "Next: First Meeting", comment: "Onboarding access page button before the meeting step")
    }

    public static var openLintel: String {
        String(localized: "Open Lintel", comment: "Onboarding button on the last step")
    }
}

/// The names of the five steps in the rail (prototype `onb.names`).
public nonisolated enum OnboardingStepNames {
    public static var goal: String { String(localized: "Your goal", comment: "Onboarding step name in the rail") }
    public static var privacy: String { String(localized: "Privacy", comment: "Onboarding step name in the rail") }
    public static var access: String { String(localized: "Access", comment: "Onboarding step name in the rail") }
    public static var tryDictation: String {
        String(localized: "Try dictation", comment: "Onboarding step name in the rail")
    }
    public static var firstMeeting: String {
        String(localized: "First meeting", comment: "Onboarding step name in the rail")
    }
}

/// One step in the rail.
public nonisolated struct OnboardingRailStep: Equatable, Identifiable, Sendable {
    public enum Status: Equatable, Sendable {
        case done
        case current
        case upcoming
    }

    public var id: String
    public var title: String
    public var status: Status

    public init(id: String, title: String, status: Status) {
        self.id = id
        self.title = title
        self.status = status
    }
}

/// A speech download that runs in the background while the user goes on. Never blocks Continue.
public nonisolated struct OnboardingRailDownload: Equatable, Sendable {
    /// "Getting dictation ready".
    public var title: String
    /// 0 to 1.
    public var progress: Double

    public init(title: String, progress: Double) {
        self.title = title
        self.progress = min(max(progress, 0), 1)
    }

    public static func dictation(progress: Double) -> OnboardingRailDownload {
        OnboardingRailDownload(
            title: String(
                localized: "Getting dictation ready", comment: "Onboarding step rail: the speech download is running"),
            progress: progress)
    }

    public var percent: Int { Int((progress * 100).rounded()) }

    /// "Getting dictation ready · 40 %".
    public var text: String { "\(title) · \(percent) %" }
}

/// What the rail shows: the steps for the chosen goal with the current one marked, and a running download.
public nonisolated struct OnboardingStepRailState: Equatable, Sendable {
    public var steps: [OnboardingRailStep]
    public var download: OnboardingRailDownload?

    public init(steps: [OnboardingRailStep], download: OnboardingRailDownload? = nil) {
        self.steps = steps
        self.download = download
    }

    /// Steps before `currentIndex` are done, the one at it is current, the rest are upcoming.
    public init(titles: [String], currentIndex: Int, download: OnboardingRailDownload? = nil) {
        self.init(
            steps: titles.enumerated().map { index, title in
                OnboardingRailStep(
                    id: "\(index)", title: title,
                    status: index < currentIndex ? .done : index == currentIndex ? .current : .upcoming)
            }, download: download)
    }

    public var currentIndex: Int? { steps.firstIndex { $0.status == .current } }

    /// "Step 3 of 5" above the page's heading.
    public var stepLabel: String? {
        guard let index = currentIndex else { return nil }
        return OnboardingStepRailState.stepOf(index + 1, steps.count)
    }

    public static func stepOf(_ step: Int, _ count: Int) -> String {
        String(
            localized: "Step \(step) of \(count)", comment: "Onboarding: the position in the steps, e.g. Step 3 of 5")
    }

    /// What VoiceOver says for the step at `index`: "Access, Step 3 of 5, current".
    public func spokenLabel(at index: Int) -> String {
        guard steps.indices.contains(index) else { return "" }
        let status =
            switch steps[index].status {
            case .done: String(localized: "done", comment: "Onboarding rail, spoken: the step is finished")
            case .current: String(localized: "current", comment: "Onboarding rail, spoken: the step the user is on")
            case .upcoming: String(localized: "not yet", comment: "Onboarding rail, spoken: a later step")
            }
        return "\(steps[index].title), \(OnboardingStepRailState.stepOf(index + 1, steps.count)), \(status)"
    }
}

/// The state of one permission row (spec C14: three states, plus the two states of the call-audio check).
public nonisolated struct OnboardingAccessRow: Identifiable, Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case allowed
        case needsOK
        case notNeededNow
        /// The call-audio check is running (a sound plays and Lintel listens for it).
        case checking
        /// The call-audio check did not hear the sound.
        case checkFailed
    }

    public var id: String
    public var title: String
    /// Why Lintel asks, in plain words.
    public var reason: String
    public var state: State

    public init(id: String, title: String, reason: String, state: State) {
        self.id = id
        self.title = title
        self.reason = reason
        self.state = state
    }

    public static func microphone(_ state: State) -> OnboardingAccessRow {
        OnboardingAccessRow(
            id: "microphone",
            title: String(localized: "Microphone", comment: "Permission name"),
            reason: String(
                localized: "To hear you when you dictate or record.",
                comment: "Onboarding: why the microphone is needed"
            ), state: state)
    }

    public static func typeIntoApps(_ state: State) -> OnboardingAccessRow {
        OnboardingAccessRow(
            id: "accessibility",
            title: String(localized: "Type into other apps", comment: "Permission name for Accessibility"),
            reason: String(
                localized: "So your words appear where your cursor is.",
                comment: "Onboarding: why Accessibility is needed"), state: state)
    }

    public static func callAudio(_ state: State) -> OnboardingAccessRow {
        OnboardingAccessRow(
            id: "system-audio",
            title: String(
                localized: "Hear other people in a call", comment: "Permission name for System Audio Recording"),
            reason: String(
                localized: "So notes include what the others say.",
                comment: "Onboarding: why System Audio Recording is needed"), state: state)
    }
}

import Foundation
import LintelKit

/// The goal page's three choices (spec `2026-11-24-first-run-onboarding`, step 3.3). It is not an
/// `OnboardingGoal`: a step declares the one goal it serves, and "Both" is the choice that narrows nothing.
enum OnboardingGoalChoice: String, CaseIterable, Sendable {
    case both
    case dictation
    case meetingNotes

    /// Reads `app.onboarding.goal` (spec Data Model): a missing or unknown value means "Both", the default.
    init(stored: String?) {
        self = stored.flatMap(Self.init(rawValue:)) ?? .both
    }

    /// Whether the choice shows a step that serves `goal`. A narrowed choice hides only the steps of the other
    /// goal on the goal page; a step with no goal, or with a goal the page does not offer, serves every choice
    /// (`OnboardingGoal` is an open set and an unknown value is ignored), so its plugin is never switched off.
    func shows(_ goal: OnboardingGoal?) -> Bool {
        switch self {
        case .both: true
        case .dictation: goal != .meetingNotes
        case .meetingNotes: goal != .dictation
        }
    }

    /// The goal page's primary button: it names what it sets up (owner decision 5).
    var setupTitle: LocalizedStringResource {
        switch self {
        case .both:
            return LocalizedStringResource(
                "Set Up Both",
                comment: "Onboarding goal page: primary button that sets up dictation and meeting notes")
        case .dictation:
            return LocalizedStringResource(
                "Set Up Dictation", comment: "Onboarding goal page: primary button that sets up dictation")
        case .meetingNotes:
            return LocalizedStringResource(
                "Set Up Meeting Notes", comment: "Onboarding goal page: primary button that sets up meeting notes")
        }
    }
}

/// The onboarding steps one active plugin contributes, with the plugin id the flow needs to write its switch.
struct OnboardingPluginSteps {
    let pluginID: PluginID
    let steps: [OnboardingStep]
}

/// The first-run onboarding's pure state machine (spec `2026-11-24-first-run-onboarding`, step 3.3): the steps
/// for the chosen goal, their primary buttons, Skip, Back, completion, and what Escape does. It reads no settings
/// and draws no view; the shell applies `goalWrites` and what it records, through `SettingsStore` (step 3.4 wires
/// it into the window). Nothing here is used by the app yet.
struct OnboardingFlow {
    /// One page on screen.
    struct Page: Identifiable {
        enum Kind {
            /// "What would you like Lintel to do?".
            case goal
            /// "Your words stay on this Mac".
            case privacy
            /// "Lintel needs your OK for a few things".
            case access
            /// A step contributed by an active plugin.
            case plugin(OnboardingStep)
        }

        static let goalID = "goal"
        static let privacyID = "privacy"
        static let accessID = "access"

        let kind: Kind

        var id: String {
            switch kind {
            case .goal: Self.goalID
            case .privacy: Self.privacyID
            case .access: Self.accessID
            case .plugin(let step): step.id
            }
        }

        /// The page's name in the step rail and in a "Next: …" button.
        var title: LocalizedStringResource {
            switch kind {
            case .goal:
                return LocalizedStringResource("Your goal", comment: "Onboarding step rail: the goal page")
            case .privacy:
                return LocalizedStringResource("Privacy", comment: "Onboarding step rail: the privacy page")
            case .access:
                return LocalizedStringResource("Access", comment: "Onboarding step rail: the permissions page")
            case .plugin(let step):
                return step.title
            }
        }
    }

    /// How a page was left forward.
    enum Outcome: Equatable, Sendable {
        case finished
        case skipped
    }

    /// What the primary button on the page on screen does.
    enum PrimaryAction: Equatable {
        /// The goal page: "Set Up Both", "Set Up Dictation" or "Set Up Meeting Notes".
        case setGoal(OnboardingGoalChoice)
        /// The privacy page: "Next: Allow Access".
        case allowAccess
        /// "Next: <title of the page with this id>".
        case next(String)
        /// The last page: "Open Lintel", which finishes the flow.
        case openLintel
        /// A plugin step's own `primaryActionTitle`.
        case stepDeclared
    }

    /// What Escape does on the page on screen.
    enum EscapeAction: Equatable, Sendable {
        /// Closes the window; the steps left undone stay in the setup checklist.
        case closeWindow
        /// Asks first ("Close setup? Downloads continue in the background."), so a stray key press does not end
        /// a flow that is downloading (spec UI/UX).
        case askToClose
    }

    /// The steps of the active plugins the flow knows, in plugin order.
    let plugins: [OnboardingPluginSteps]
    private(set) var goal: OnboardingGoalChoice
    private(set) var index: Int = 0
    /// How each page was left forward. A page not reached has no entry, which the setup checklist counts as
    /// unfinished.
    private(set) var outcomes: [String: Outcome] = [:]
    private(set) var isComplete = false
    /// Set by the shell while a model download runs; it changes only what Escape does.
    var isDownloading = false

    init(plugins: [OnboardingPluginSteps] = [], goal: OnboardingGoalChoice = .both) {
        self.plugins = plugins
        self.goal = goal
    }

    /// The flow for the chosen goal: the three shell pages, then the plugin steps that serve the goal.
    var pages: [Page] {
        var pages = [Page(kind: .goal), Page(kind: .privacy), Page(kind: .access)]
        for plugin in plugins {
            pages += plugin.steps.filter { goal.shows($0.goal) }.map { Page(kind: .plugin($0)) }
        }
        return pages
    }

    var current: Page? { pages.indices.contains(index) ? pages[index] : nil }
    var isFirst: Bool { index == 0 }
    var isLast: Bool { index == pages.count - 1 }

    /// Whether Skip is offered: only on a plugin's step, where it means "set this up later". The shell's own pages
    /// are answered by their primary button, and the Access page lets each permission be left for later on its own
    /// row.
    var showsSkip: Bool {
        guard case .plugin = current?.kind else { return false }
        return true
    }

    /// "Continue is never greyed out" (C10, spec Resolved assumption 5): no page and no state may disable the
    /// primary button. The flow reports it as a fact, so a view cannot decide otherwise.
    var isPrimaryEnabled: Bool { true }

    /// What the primary button does on the page on screen; `nil` once the flow is finished.
    var primaryAction: PrimaryAction? {
        guard let current else { return nil }
        switch current.kind {
        case .goal:
            return .setGoal(goal)
        case .privacy:
            return .allowAccess
        case .access:
            return isLast ? .openLintel : .next(pages[index + 1].id)
        case .plugin(let step):
            if step.primaryActionTitle != nil {
                return .stepDeclared
            }
            return isLast ? .openLintel : .next(pages[index + 1].id)
        }
    }

    /// The primary button's title: a plugin step's own title when it declares one, otherwise the shell's wording
    /// that names the next page.
    var primaryTitle: LocalizedStringResource? {
        guard let action = primaryAction else { return nil }
        switch action {
        case .setGoal(let choice):
            return choice.setupTitle
        case .allowAccess:
            return LocalizedStringResource(
                "Next: Allow Access",
                comment: "Onboarding privacy page: primary button that leads to the permissions page")
        case .next(let id):
            guard let next = pages.first(where: { $0.id == id }) else { return nil }
            return LocalizedStringResource(
                "Next: \(next.title)", comment: "Onboarding button that names the step it leads to")
        case .openLintel:
            return LocalizedStringResource(
                "Open Lintel", comment: "Onboarding button on the last step that finishes setup")
        case .stepDeclared:
            guard case .plugin(let step) = current?.kind else { return nil }
            return step.primaryActionTitle
        }
    }

    /// What Escape does on the page on screen: it asks before closing while a download runs.
    var escapeAction: EscapeAction { isDownloading ? .askToClose : .closeWindow }

    /// The switches leaving the goal page writes: only `plugins.<id>.enabled`, and only for a plugin whose
    /// contributed steps all serve another goal. "Both" writes nothing (Dictation and Meetings are on by default),
    /// and a plugin with no steps is never touched.
    var goalWrites: [OnboardingSettingWrite] {
        Self.switchWrites(for: goal, plugins: plugins)
    }

    static func switchWrites(
        for choice: OnboardingGoalChoice, plugins: [OnboardingPluginSteps]
    ) -> [OnboardingSettingWrite] {
        guard choice != .both else { return [] }
        return plugins.compactMap { plugin in
            guard !plugin.steps.isEmpty, !plugin.steps.contains(where: { choice.shows($0.goal) }) else {
                return nil
            }
            return OnboardingSettingWrite(
                key: SettingsKeys.pluginEnabled(plugin.pluginID), value: .bool(false))
        }
    }

    /// Picks the goal on the goal page; it decides which plugin steps follow and what `goalWrites` holds.
    mutating func choose(_ choice: OnboardingGoalChoice) {
        guard current?.id == Page.goalID else { return }
        goal = choice
    }

    /// Continue (Return): records the page as finished and moves on, and finishes the flow after the last page.
    mutating func advance() {
        guard let current else { return }
        outcomes[current.id] = .finished
        moveOn()
    }

    /// Skip: the step is set up later, its id is recorded like a finished one, and the flow moves on. It does
    /// nothing on a page that does not offer Skip.
    mutating func skip() {
        guard showsSkip, let current else { return }
        outcomes[current.id] = .skipped
        moveOn()
    }

    /// Back: one page back, never before the goal page, and nothing once the flow is finished.
    mutating func back() {
        guard !isComplete, index > 0 else { return }
        index -= 1
    }

    private mutating func moveOn() {
        if isLast {
            isComplete = true
            index = pages.count
        } else {
            index += 1
        }
    }
}

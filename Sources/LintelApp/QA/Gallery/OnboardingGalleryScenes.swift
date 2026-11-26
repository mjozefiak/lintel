#if DEBUG
import LintelUI
import SwiftUI

/// DEBUG only: the gallery scenes of the onboarding pages (spec `2026-11-24-first-run-onboarding`, UI/UX, "Gallery
/// states", step 3.2): Goal, Privacy, Access and the step rail. Every state draws the REAL page view of `LintelUI`
/// over a value state made up here; nothing is wired to the flow, no permission is asked, no process starts and no
/// file is read. The pages that follow (Try dictation, First meeting) come with the plugins' steps (phase 4).
@MainActor enum OnboardingGallery {
    static let goalID = "onboarding.goal"
    static let privacyID = "onboarding.privacy"
    static let accessID = "onboarding.access"
    static let stepRailID = "onboarding.step-rail"

    static var scenes: [GalleryScene] { [goal, privacy, accessScene, stepRail] }

    private static let window = GalleryPresentation.window(
        width: OnboardingLayout.windowWidth, height: OnboardingLayout.windowHeight)
    private static let railOnly = GalleryPresentation.window(
        width: OnboardingLayout.railWidth, height: OnboardingLayout.windowHeight)

    // MARK: rails

    /// The five steps of the goal "Both"; `current` is the 0-based index of the step on screen.
    private static func rail(current: Int, download: OnboardingRailDownload? = nil) -> OnboardingStepRailState {
        OnboardingStepRailState(
            titles: [
                OnboardingStepNames.goal, OnboardingStepNames.privacy, OnboardingStepNames.access,
                OnboardingStepNames.tryDictation, OnboardingStepNames.firstMeeting,
            ], currentIndex: current, download: download)
    }

    // MARK: goal

    static var goal: GalleryScene {
        func state(_ id: String, _ summary: String, _ choice: OnboardingGoalChoice) -> GalleryState {
            GalleryState(id: id, summary: summary, presentation: window) {
                AnyView(OnboardingGoalPage(OnboardingGoalState(rail: rail(current: 0), selection: choice)))
            }
        }
        return GalleryScene(
            id: goalID, title: "Onboarding → 1 Your goal",
            states: [
                state(
                    "both",
                    "Both is chosen (the default): three choices, \"You can change this later in Settings.\", the one button reads Set Up Both.",
                    .both),
                state(
                    "dictation", "Type what I say is chosen: the button reads Set Up Dictation.", .dictation),
                state(
                    "meeting-notes", "Write my meeting notes is chosen: the button reads Set Up Meeting Notes.",
                    .meetingNotes),
            ])
    }

    // MARK: privacy

    static var privacy: GalleryScene {
        func state(_ id: String, _ summary: String, consent: Bool) -> GalleryState {
            GalleryState(id: id, summary: summary, presentation: window) {
                AnyView(
                    OnboardingPrivacyPage(
                        OnboardingPrivacyState(rail: rail(current: 1), includesMeetingConsent: consent)))
            }
        }
        return GalleryScene(
            id: privacyID, title: "Onboarding → 2 Privacy",
            states: [
                state(
                    "with-consent",
                    "Three points about where the words stay, then the sentence about telling the people in a meeting (goals with meetings). Button: Next: Allow Access.",
                    consent: true),
                state(
                    "without-consent",
                    "The same three points and no consent sentence (the dictation goal).", consent: false),
            ])
    }

    // MARK: access

    private static func accessPage(
        rows: [OnboardingAccessRow], current: Int = 2, primary: String = OnboardingPrimaryTitles.tryDictation,
        needsMove: Bool = false, download: OnboardingRailDownload? = nil
    ) -> AnyView {
        AnyView(
            OnboardingAccessPage(
                OnboardingAccessState(
                    rail: rail(current: current, download: download), rows: rows,
                    needsMoveToApplications: needsMove, primaryTitle: primary)))
    }

    static var accessScene: GalleryScene {
        GalleryScene(
            id: accessID, title: "Onboarding → 3 Access",
            states: [
                GalleryState(
                    id: "needs-your-ok",
                    summary:
                        "Both goals, nothing allowed yet: a row per permission with its reason, Needs your OK and an Allow button. Next stays active.",
                    presentation: window
                ) {
                    accessPage(rows: [.microphone(.needsOK), .typeIntoApps(.needsOK), .callAudio(.needsOK)])
                },
                GalleryState(
                    id: "every-state",
                    summary:
                        "The three states side by side: Microphone is Allowed with a check, Type into other apps needs your OK, Hear other people in a call is Not needed now.",
                    presentation: window
                ) {
                    accessPage(rows: [.microphone(.allowed), .typeIntoApps(.needsOK), .callAudio(.notNeededNow)])
                },
                GalleryState(
                    id: "all-allowed",
                    summary: "Every row is Allowed with a check; the page goes on by itself or with Next.",
                    presentation: window
                ) {
                    accessPage(
                        rows: [.microphone(.allowed), .typeIntoApps(.allowed), .callAudio(.allowed)],
                        primary: OnboardingPrimaryTitles.tryDictation)
                },
                GalleryState(
                    id: "checking-call-audio",
                    summary:
                        "The call audio check is running: the working ring and Checking… in place of the Allow button.",
                    presentation: window
                ) {
                    accessPage(rows: [.microphone(.allowed), .typeIntoApps(.allowed), .callAudio(.checking)])
                },
                GalleryState(
                    id: "check-failed",
                    summary:
                        "The call audio check did not hear the test sound: what happened, what to do and a Check Again button. Next still works.",
                    presentation: window
                ) {
                    accessPage(rows: [.microphone(.allowed), .typeIntoApps(.allowed), .callAudio(.checkFailed)])
                },
                GalleryState(
                    id: "download-running",
                    summary:
                        "The same page while the speech files download in the background: the step rail shows Getting dictation ready · 40 %.",
                    presentation: window
                ) {
                    accessPage(
                        rows: [.microphone(.allowed), .typeIntoApps(.needsOK), .callAudio(.needsOK)],
                        download: .dictation(progress: 0.4))
                },
                GalleryState(
                    id: "move-first",
                    summary:
                        "Lintel runs from the disk image: one row, Move Lintel to Applications first, with one Move button, instead of permission rows (grants given there would be lost).",
                    presentation: window
                ) {
                    accessPage(
                        rows: [.microphone(.needsOK), .typeIntoApps(.needsOK), .callAudio(.needsOK)], needsMove: true)
                },
            ])
    }

    // MARK: step rail

    static var stepRail: GalleryScene {
        GalleryScene(
            id: stepRailID, title: "Onboarding → step rail",
            states: [
                GalleryState(
                    id: "step-3-of-5",
                    summary:
                        "Five steps: two done with a check, Access is current (bar and tint), two to come. Spoken: Access, Step 3 of 5, current.",
                    presentation: railOnly
                ) { AnyView(OnboardingStepRail(rail(current: 2))) },
                GalleryState(
                    id: "download-running",
                    summary:
                        "A speech download is running: one line and a thin progress bar at the bottom, Getting dictation ready · 40 %. It never blocks Next.",
                    presentation: railOnly
                ) { AnyView(OnboardingStepRail(rail(current: 3, download: .dictation(progress: 0.4)))) },
                GalleryState(
                    id: "four-steps",
                    summary:
                        "The goal Dictation has four steps (no First meeting): Privacy is current, so Step 2 of 4.",
                    presentation: railOnly
                ) {
                    AnyView(
                        OnboardingStepRail(
                            OnboardingStepRailState(
                                titles: [
                                    OnboardingStepNames.goal, OnboardingStepNames.privacy,
                                    OnboardingStepNames.access, OnboardingStepNames.tryDictation,
                                ], currentIndex: 1)))
                },
            ])
    }
}
#endif

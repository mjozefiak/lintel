import Foundation
import LintelKit

/// Every settings key the shell owns, declared in one place. Settings keys are a protected
/// contract (`BACKWARD_COMPATIBILITY.md` section 3): never rename one without a migration.
enum SettingsKeys {
    /// `plugins.<id>.enabled`, a `Bool`; missing means `manifest.defaultEnabled`.
    static func pluginEnabled(_ id: PluginID) -> String {
        "plugins.\(id.rawValue).enabled"
    }

    /// `Bool`: the user recorded the main shortcut themselves, so Lintel never replaces it with a default
    /// (Q10). The shortcut itself is stored by KeyboardShortcuts under `KeyboardShortcuts_mainHotkey`.
    static let hotkeyUserDefined = "app.hotkey.userDefined"

    /// `[String]`: plugin command ids whose default shortcut was already applied once, so a shortcut the
    /// user cleared is not restored.
    static let commandShortcutDefaultsApplied = "app.hotkey.commandDefaultsApplied"

    /// `Bool`: the first-launch Shortcut step was accepted or skipped.
    static let onboardingShortcutCompleted = "app.onboarding.shortcutCompleted"

    /// `[String]`: ids of plugin onboarding steps (`OnboardingStep.id`) finished or skipped; each is shown
    /// once. Added in Phase 2.
    static let onboardingCompletedSteps = "app.onboarding.completedSteps"

    /// `[String]`: plugin ids in the order their result sections appear (issue #5). Plugins not listed
    /// follow in `manifest.order`. Added in Phase 3.
    static let sectionOrder = "app.sectionOrder"

    /// `Bool`, default `true`: show Lintel's icon in the Dock. `false` keeps it a menu bar app only. Either way
    /// `LSUIElement` stays in `Info.plist`; the shell switches the activation policy at runtime. Added with the
    /// Lintel rebrand.
    static let showInDock = "app.showInDock"

    /// `String`: `s`, `m` (default), `l` or `xl`, the panel's text size.
    static let textSize = "app.textSize"

    /// `String`: `floating` (default) or `statusBar`, the panel's window level. `statusBar` is the spec's
    /// fallback (spike 1.2) if the panel does not appear over full-screen apps.
    static let panelLevel = "app.panelLevel"

    /// `String`: `workspace` or `settings`, the main window's mode when it was last shown (`MainWindowState`).
    /// Added with the main window (spec `2026-11-04-lintel-main-window`, step 1.2).
    static let mainWindowMode = "app.mainWindow.mode"

    /// `String`: the id of the workspace section the main window showed last (`WorkspaceSection.id`).
    static let mainWindowSection = "app.mainWindow.section"

    /// `String`: the id of the Settings pane the main window showed last (a shell pane or a plugin id).
    static let mainWindowSettingsPane = "app.mainWindow.settingsPane"

    /// `Bool`: updates include pre-releases (the `beta` channel). Written once as `true` by the first pre-release
    /// build that finds it absent (`UpdateChannel.includeBeta`); absent on a stable build means `false`.
    /// Added with in-app updates (spec `2026-11-19-updates-and-open-source-hygiene`, Step 4.3).
    static let updatesIncludeBeta = "app.updates.includeBeta"

    /// `Bool`, default `false`: the user chose "Don't ask again" in the launch-time "Move Lintel to Applications?"
    /// alert (spec `2026-11-19-updates-and-open-source-hygiene`, step 4.2).
    static let moveDeclined = "app.install.moveDeclined"

    /// `String`, `auto` or `single`; missing or unknown means `auto`: the language of meetings and dictation is
    /// recognised automatically, or pinned to `speechSingleLanguage`. Shared by Dictation and Meetings through
    /// `PluginContext.speechLanguages` (spec `2026-11-23-automatic-language-detection`, step 2.1). The four `app.speech.*` keys are `nonisolated`
    /// because `HostSpeechLanguageSettings` reads them from any thread.
    nonisolated static let speechLanguageMode = "app.speech.languageMode"

    /// `[String]` of catalog language codes, ordered, at most 10: Languages I speak. Missing or empty means the
    /// list derived from the Mac's languages (else `["en"]`), which is never written until the user edits it.
    nonisolated static let speechLanguages = "app.speech.languages"

    /// `String`, a catalog language code, used only in `single` mode; missing or unknown means the first language
    /// of the list.
    nonisolated static let speechSingleLanguage = "app.speech.singleLanguage"

    /// `Bool`, default `false`: the one-time move of `plugins.meetings.speechLanguage` and
    /// `plugins.dictation.speechLanguage` into the shared list ran (`SpeechLanguageMigration`, spec step 2.3).
    nonisolated static let speechLegacyLanguageMigrated = "app.speech.legacyLanguageMigrated"
}

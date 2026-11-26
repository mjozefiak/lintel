import LintelKit
import SwiftUI

/// The Languages row with its sheet, as the Dictation and Meetings panes place it in their speech card (spec
/// `2026-11-23-automatic-language-detection`, step 2.3). It reads the shared setting, follows every change made
/// elsewhere (the other pane, the other plugin) through its own `changes` stream, and stores the sheet's result
/// only on Done.
public struct SpeechLanguagesSetting: View {
    private let settings: any SpeechLanguageSettings
    private let options: [SpeechLanguageOption]
    private let whisperInstalled: Bool
    private let getWhisper: () -> Void
    @State private var selection: SpeechLanguageSelection
    @State private var isEditing = false

    /// - Parameters:
    ///   - settings: `PluginContext.speechLanguages`.
    ///   - options: every language that can be listed, built by the plugin from `SpeechLanguageCatalog`.
    ///   - whisperInstalled: the Whisper model is on this Mac (the sheet then offers no "Get It in Models").
    ///   - getWhisper: opens the Models pane on the Whisper model; the draft is stored first.
    public init(
        settings: any SpeechLanguageSettings, options: [SpeechLanguageOption], whisperInstalled: Bool,
        getWhisper: @escaping () -> Void
    ) {
        self.settings = settings
        self.options = options
        self.whisperInstalled = whisperInstalled
        self.getWhisper = getWhisper
        _selection = State(initialValue: settings.current())
    }

    public var body: some View {
        SpeechLanguagesRow(selection: selection, options: options) { isEditing = true }
            .sheet(isPresented: $isEditing) {
                SpeechLanguagesSheet(
                    model: SpeechLanguagesSheetModel(
                        selection: selection, options: options, whisperInstalled: whisperInstalled),
                    onDone: { edited in
                        store(edited)
                        isEditing = false
                    },
                    onCancel: { isEditing = false },
                    onGetWhisper: { draft in
                        store(draft)
                        isEditing = false
                        getWhisper()
                    })
            }
            .task {
                selection = settings.current()
                for await _ in settings.changes {
                    selection = settings.current()
                }
            }
    }

    private func store(_ edited: SpeechLanguageSelection) {
        settings.update(edited)
        selection = settings.current()
    }
}

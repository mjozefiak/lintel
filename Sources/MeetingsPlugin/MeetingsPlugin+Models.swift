import Foundation
import LintelKit
import LintelSpeech

/// The models Meetings uses, for the shell's Models pane (spec `2026-11-04-lintel-main-window`, step 3.2, D6).
///
/// - The speech model is required (recording needs it) unless the user chose a folder for it; the diarization model
///   is not (finishing falls back to one speaker without it). A chosen folder of either is reported as
///   `customFolder`, so the Models pane shows its state. Both are guarded by `MeetingsModelUsage.live`, the check
///   the model cards use: a meeting recording or finishing holds them, and its reservation keeps a new recording
///   from starting while a model is being removed.
/// - The notes model is optional; it is in use while `NotesService` has work or a lease holds its file.
/// - The speech model is the one the next recording would use (`MeetingEngineRouting`, spec
///   `2026-11-23-automatic-language-detection` D3): Whisper when the languages need it and it is installed, so the
///   Models pane shows it as used and needed and its removal is guarded. A folder can be chosen only for the model
///   chosen in Settings: Whisper reached through the router is always its download.
extension MeetingsPlugin {
    public var modelUsage: [ModelUsage] {
        let settings = settings
        let usage = ui.usage
        let selected = ModelCatalog.package(id: settings.speechModelID) ?? ModelCatalog.parakeetUltra
        let speech = MeetingEngineRouting.package(
            selected: selected, selection: context.speechLanguages.current(),
            whisperInstalled: ui.model.whisperInstalled)
        let isChosen = speech.id == selected.id
        let speechFolder = isChosen ? settings.speechModelFolder : nil
        // "Choose Folder…" writes the chosen model's key: offered only when the routed model is that one.
        func speechUsage(chooseFolder: (@MainActor @Sendable (URL?) -> Void)?) -> ModelUsage {
            ModelUsage(
                packageID: speech.id, kind: .speech,
                role: LocalizedStringResource(
                    "Meeting transcripts", comment: "Models pane: what Meetings uses the speech model for"),
                // With a chosen folder the downloaded copy is not needed; the pane shows the folder's state.
                isRequired: speechFolder == nil, isSelected: true, chooseFolder: chooseFolder,
                customFolder: speechFolder, isInUse: { await usage.isInUse(speech) },
                reserveRemoval: usage.reserveRemoval)
        }
        let speechModel =
            isChosen ? speechUsage(chooseFolder: { settings.setSpeechModelFolder($0) }) : speechUsage(chooseFolder: nil)
        let diarization = ModelCatalog.diarizationCommunity1
        let notesModel = settings.builtInLLMModel
        let notes = notes
        let llmManager = ui.llmManager
        return [
            speechModel,
            ModelUsage(
                packageID: diarization.id, kind: .diarization,
                role: LocalizedStringResource(
                    "Speakers", comment: "Models pane: what Meetings uses the diarization model for"),
                isRequired: false, isSelected: settings.diarization,
                chooseFolder: { settings.setDiarizationModelFolder($0) },
                customFolder: settings.diarizationModelFolder,
                isInUse: { await usage.isInUse(diarization) },
                reserveRemoval: usage.reserveRemoval),
            ModelUsage(
                packageID: notesModel.id, kind: .llm,
                role: LocalizedStringResource(
                    "Meeting notes", comment: "Models pane: what Meetings uses the language model for"),
                isRequired: false, isSelected: settings.notesEnabled,
                isInUse: {
                    if notes.isBusy { return true }
                    guard let folder = await llmManager.location(of: notesModel.package).folder,
                        let file = notesModel.fileURL(in: folder)
                    else { return false }
                    return await LLMLease.shared.isInUse(modelID: file.path)
                }),
        ]
    }
}

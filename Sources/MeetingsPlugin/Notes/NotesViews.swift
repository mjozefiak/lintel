import LintelSpeech
import LintelUI
import SwiftUI

/// What the "Notes on this Mac" part of the `meetings.setup` step offers (issue #252; spec
/// `2026-11-24-first-run-onboarding`, step 5 and the downloads edge cases). Notes are on by default, so the step
/// offers the model that writes them; nothing is downloaded until the button is clicked, and Continue never waits.
enum NotesModelOffer: Equatable {
    /// The switch is off: only the switch is shown.
    case off
    case installed
    case downloading(ModelProgress)
    /// The free space the download needs is not there: both numbers, no Download button.
    case noSpace(ModelSpaceCheck)
    /// The last download stopped (offline, a server error); Try Again continues where it stopped.
    case failed(message: String)
    /// The download is offered; `remainingBytes` is set when an earlier download stopped part of the way.
    case download(totalBytes: Int, remainingBytes: Int?)

    /// Whether the line "notes are written once the model is on this Mac" belongs under the offer.
    var waitsForModel: Bool {
        switch self {
        case .off, .installed: false
        case .downloading, .noSpace, .failed, .download: true
        }
    }
}

extension NotesSettingsModel {
    var offer: NotesModelOffer {
        guard enabled else { return .off }
        if let progress { return .downloading(progress) }
        if isInstalled { return .installed }
        if let space, !space.fits { return .noSpace(space) }
        if let errorMessage { return .failed(message: errorMessage) }
        let total = model.package.totalBytes
        if case .partial(let bytes) = location, bytes > 0, bytes < total {
            return .download(totalBytes: total, remainingBytes: total - bytes)
        }
        return .download(totalBytes: total, remainingBytes: nil)
    }
}

/// The `meetings.setup` step's "Notes on this Mac" rows: the switch, then the offer of the model in its state.
struct NotesOnThisMacRows: View {
    @Bindable var model: NotesSettingsModel

    static let text = Text(
        "Notes on this Mac: Lintel writes your meeting notes here, without the internet.",
        comment: "Meetings onboarding step about the notes model")

    private func bytes(_ value: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $model.enabled) {
                Text("Write notes after each meeting", comment: "Meetings settings toggle of automatic notes")
            }
            let offer = model.offer
            offerRow(offer)
            if offer.waitsForModel {
                Text(
                    "You can record now. Notes are written once the model is on this Mac.",
                    comment: "Meetings onboarding: notes wait for the notes model, recording does not"
                )
                .font(.callout).foregroundStyle(LintelBrand.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func offerRow(_ offer: NotesModelOffer) -> some View {
        switch offer {
        case .off:
            EmptyView()
        case .installed:
            Label {
                Text("Downloaded", comment: "Dictation model status")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true)
            }
        case .downloading(let progress):
            ProgressView(value: progress.fraction) {
                Text("Downloading…", comment: "Dictation settings progress label")
            }
            .accessibilityValue(Text(progress.fraction, format: .percent.precision(.fractionLength(0))))
            Button {
                model.cancelDownload()
            } label: {
                Text("Cancel", comment: "Button that cancels the model download")
            }
        case .noSpace(let space):
            warning(
                Text(
                    "Not enough free space. The notes model needs \(bytes(space.needed)), and \(bytes(space.available)) is free.",
                    comment: "Meetings onboarding: the disk is too full for the notes model; needed and free space"))
            Button {
                Task { await model.refresh() }
            } label: {
                Text(
                    "Check Again", comment: "Meetings onboarding: reads the free space again after the user freed some")
            }
        case .failed(let message):
            warning(Text(verbatim: message))
            Button {
                model.download()
            } label: {
                Text("Try Again", comment: "Meetings onboarding: continues the notes model download where it stopped")
            }
        case .download(let total, let remaining):
            Button {
                model.download()
            } label: {
                if let remaining {
                    Text(
                        "Continue Download (\(bytes(remaining)) left)",
                        comment: "Meetings onboarding: resumes a notes model download that stopped part of the way")
                } else {
                    Text(
                        "Download (≈ \(bytes(total)))",
                        comment: "Button that downloads the built-in formatting model")
                }
            }
        }
    }

    private func warning(_ text: Text) -> some View {
        Label {
            text.fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle").accessibilityHidden(true)
        }
        // The brand's attention colour has text contrast in both appearances (`BrandContrastTests`); system orange
        // does not on a light background.
        .foregroundStyle(LintelBrand.statusAttention)
    }
}

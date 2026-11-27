import LintelProviders
import LintelUI
import SwiftUI

/// What the "Tidy up with" rows say about themselves (spec `2026-11-25-dictation-cleanup-levels`, UI/UX "Source row" and
/// "Source: external AI provider", point 3). Pure texts over the descriptor's names, so a company name is never typed in
/// a sentence of ours.
enum TidySourceText {
    static var label: Text {
        Text("Tidy up with", comment: "Settings → Dictation: the row that says where the tidying runs")
    }

    static var thisMac: Text {
        Text("This Mac", comment: "Settings → Dictation, Tidy up with: the built-in model on this Mac")
    }

    static var myServer: Text {
        Text("My server", comment: "Dictation settings choice of the user's formatting server")
    }

    static var addProvider: Text {
        Text(
            "Add a provider…", comment: "Settings → Dictation, Tidy up with: the row for a provider that is not set up")
    }

    static func providerName(_ descriptor: ProviderDescriptor) -> Text {
        Text(verbatim: descriptor.shortName)
    }

    /// The fixed sentence beside the choice: what leaves the Mac and what does not. The company is the descriptor's
    /// `recipient` (bold), the tool its `displayName`.
    static func disclosure(_ descriptor: ProviderDescriptor) -> Text {
        Text(
            "Text you dictate is sent to **\(descriptor.recipient)** through your \(descriptor.displayName). Audio stays on this Mac.",
            comment:
                "Settings → Dictation, next to the choice of an AI provider: what leaves the Mac for the tidying. Audio never does"
        )
    }

    /// The same sentence as plain text for VoiceOver and for tests (no Markdown).
    static func spokenDisclosure(_ descriptor: ProviderDescriptor) -> String {
        String(
            localized:
                "Text you dictate is sent to \(descriptor.recipient) through your \(descriptor.displayName). Audio stays on this Mac.",
            comment: "Settings → Dictation: VoiceOver text of the sentence about what is sent to the AI provider")
    }

    /// The line under the row while the provider is not ready; `nil` while it works or nothing is known yet.
    static func status(_ check: FormattingSettingsModel.ProviderCheck, _ descriptor: ProviderDescriptor) -> Text? {
        let name = descriptor.displayName
        switch check {
        case .unknown:
            return nil
        case .checking:
            return Text("Checking \(name)…", comment: "Settings → Dictation: the AI provider is being checked")
        case .known(let status):
            switch status {
            case .ready:
                return nil
            case .notInstalled:
                return Text(
                    "\(name) isn’t installed. Install it, then check again.",
                    comment: "Settings → Dictation: the AI provider's command-line tool is not found")
            case .notSignedIn:
                return Text(
                    "\(name) isn’t signed in. In Terminal, run: claude auth login",
                    comment: "Settings → Dictation: the AI provider is installed but signed out")
            case .incompatibleVersion:
                return Text(
                    "This \(name) is too old. Update it, then check again.",
                    comment: "Settings → Dictation: the AI provider's tool is older than Lintel supports")
            case .newerVersion:
                return Text(
                    "This \(name) is newer than this Lintel supports. Update Lintel.",
                    comment: "Settings → Dictation: the AI provider's tool is newer than Lintel was checked with")
            }
        }
    }

    /// Whether the status line has a "Check Again" button.
    static func offersCheckAgain(_ check: FormattingSettingsModel.ProviderCheck) -> Bool {
        if case .known(let status) = check { return status != .ready }
        return false
    }

    static var checkAgain: Text {
        Text("Check Again", comment: "Settings → Dictation: reads the AI provider’s state again")
    }

    /// The note under a model that is slower and uses more of the plan's limit.
    static func heavierModel(_ descriptor: ProviderDescriptor) -> Text {
        Text(
            "Slower and uses more of your \(descriptor.shortName) limit. A late answer is pasted as spoken.",
            comment: "Settings → Dictation: note under a heavier AI model")
    }

    /// The line that says what runs instead when the provider does not serve the chosen level. `nil` when it does.
    /// Shown only then; with both levels offered (the current constant) it never shows.
    static func fallbackLine(
        _ descriptor: ProviderDescriptor, level: FormattingSettingsModel.TidyChoice,
        offered: Set<DictationSettings.CleanupLevel>, fallback: FormattingSettingsModel.LocalFallback
    ) -> Text? {
        guard let modelLevel = level.modelLevel, !offered.contains(modelLevel) else { return nil }
        let name = descriptor.shortName
        let servesFull = offered.contains(.full)
        let servesStandard = offered.contains(.standard)
        switch (servesFull, servesStandard, fallback) {
        case (true, _, .thisMac):
            return Text(
                "\(name) is used for Full. Standard runs on this Mac.",
                comment: "Settings → Dictation: the provider serves Full only; Standard runs on the built-in model")
        case (true, _, .myServer):
            return Text(
                "\(name) is used for Full. Standard runs on your server.",
                comment: "Settings → Dictation: the provider serves Full only; Standard runs on the user's server")
        case (true, _, .none):
            return Text(
                "\(name) is used for Full. Standard pastes your text untidied.",
                comment: "Settings → Dictation: the provider serves Full only; Standard has nothing to run on")
        case (false, true, .thisMac):
            return Text(
                "\(name) is used for Standard. Full runs on this Mac.",
                comment: "Settings → Dictation: the provider serves Standard only; Full runs on the built-in model")
        case (false, true, .myServer):
            return Text(
                "\(name) is used for Standard. Full runs on your server.",
                comment: "Settings → Dictation: the provider serves Standard only; Full runs on the user's server")
        case (false, true, .none):
            return Text(
                "\(name) is used for Standard. Full pastes your text untidied.",
                comment: "Settings → Dictation: the provider serves Standard only; Full has nothing to run on")
        case (false, false, _):
            return nil
        }
    }
}

/// The "Tidy up with" row and, with the provider chosen, what belongs to it: the model, the sentence about what is sent,
/// and the provider's status. Used by the Dictation pane (after the "Tidy up my text" row, for Standard and Full) and
/// drawn alone by the gallery. The built-in model's and the server's own rows stay in the pane.
struct TidySourceRows: View {
    @Bindable var formatting: FormattingSettingsModel
    /// The levels Claude serves; the constant, except in the gallery (which draws the line of a level it does not serve).
    var offered: Set<DictationSettings.CleanupLevel> = ProviderLevels.offered
    @Environment(\.lintelTextSize) private var textSize

    /// What the picker's tags stand for. The "Add a provider…" row has a tag of its own so the menu can list it, but it is
    /// disabled and never chosen: it must never write a source.
    enum SourceTag: Hashable {
        case thisMac, myServer, provider, addProvider
    }

    private var tag: Binding<SourceTag> {
        Binding(
            get: {
                switch formatting.source {
                case .builtIn: .thisMac
                case .server: .myServer
                case .provider: .provider
                }
            },
            set: { value in
                switch value {
                case .thisMac: formatting.source = .builtIn
                case .myServer: formatting.source = .server
                case .provider: formatting.source = .provider
                case .addProvider: break
                }
            })
    }

    var body: some View {
        if formatting.offersBuiltIn || formatting.offersProvider {
            MenuPicker(selection: tag) {
                if formatting.offersBuiltIn {
                    TidySourceText.thisMac.font(textSize.font(.body)).tag(SourceTag.thisMac)
                }
                TidySourceText.myServer.font(textSize.font(.body)).tag(SourceTag.myServer)
                if formatting.providerIsListed, let descriptor = FormattingSettingsModel.descriptor {
                    TidySourceText.providerName(descriptor).font(textSize.font(.body)).tag(SourceTag.provider)
                }
                if formatting.offersProvider {
                    TidySourceText.addProvider.font(textSize.font(.body)).tag(SourceTag.addProvider).disabled(true)
                }
            } label: {
                TidySourceText.label.font(textSize.font(.body))
            }
        }
        if formatting.isProvider, let descriptor = FormattingSettingsModel.descriptor {
            providerRows(descriptor)
        }
    }

    @ViewBuilder private func providerRows(_ descriptor: ProviderDescriptor) -> some View {
        MenuPicker(
            selection: Binding(
                get: { formatting.providerModelID }, set: { formatting.chooseProviderModel($0) }),
            title: Text("Model", comment: "Dictation settings label of the formatting model")
        ) {
            ForEach(formatting.providerModels, id: \.id) { model in
                Text(verbatim: model.displayName).font(textSize.font(.body)).tag(model.id)
            }
        } label: {
            Text("Model", comment: "Dictation settings label of the formatting model")
                .font(textSize.font(.body))
            if formatting.chosenProviderModel?.heavier == true {
                TidySourceText.heavierModel(descriptor).font(textSize.font(.callout))
                    .foregroundStyle(LintelBrand.secondaryText)
            }
        }
        // The fixed sentence: what leaves the Mac and what does not. One element for VoiceOver, without Markdown.
        TidySourceText.disclosure(descriptor)
            .font(textSize.font(.callout))
            .foregroundStyle(LintelBrand.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: TidySourceText.spokenDisclosure(descriptor)))
        if let line = TidySourceText.fallbackLine(
            descriptor, level: formatting.choice, offered: offered, fallback: formatting.localFallback)
        {
            line.font(textSize.font(.callout)).foregroundStyle(LintelBrand.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let status = TidySourceText.status(formatting.providerCheck, descriptor) {
            LabeledContent {
                if TidySourceText.offersCheckAgain(formatting.providerCheck) {
                    Button {
                        formatting.checkProviderAgain()
                    } label: {
                        TidySourceText.checkAgain.font(textSize.font(.body))
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
            } label: {
                status.font(textSize.font(.callout)).foregroundStyle(LintelBrand.statusAttention)
            }
        }
    }
}

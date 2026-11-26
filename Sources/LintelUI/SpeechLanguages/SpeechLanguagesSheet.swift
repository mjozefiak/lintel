import LintelKit
import SwiftUI

/// The editor of the shared language setting (spec `2026-11-23-automatic-language-detection`, "UI/UX"): Automatic
/// or Always one language, the ordered list "Languages I speak" as chips with a remove button each, drag to reorder,
/// a searchable Add Language… list, the Whisper lines and note, and Done / Cancel. Cancel is the default button and
/// Escape cancels (`ConfirmSheet` conventions). Nothing is stored before Done.
public struct SpeechLanguagesSheet: View {
    @State private var model: SpeechLanguagesSheetModel
    @State private var addIsPresented = false
    @State private var query = ""
    @State private var dropTarget: String?
    @FocusState private var searchIsFocused: Bool
    private let onDone: (SpeechLanguageSelection) -> Void
    private let onCancel: () -> Void
    private let onGetWhisper: (SpeechLanguageSelection) -> Void
    @Environment(\.lintelTextSize) private var textSize

    /// - Parameters:
    ///   - model: the draft as the sheet opens.
    ///   - onDone: receives the edited selection; the caller stores it and closes the sheet.
    ///   - onCancel: closes the sheet; nothing changes.
    ///   - onGetWhisper: "Get It in Models"; receives the draft, so the caller can keep it before it closes the sheet
    ///     and opens the Models pane.
    public init(
        model: SpeechLanguagesSheetModel,
        onDone: @escaping (SpeechLanguageSelection) -> Void,
        onCancel: @escaping () -> Void,
        onGetWhisper: @escaping (SpeechLanguageSelection) -> Void
    ) {
        _model = State(initialValue: model)
        self.onDone = onDone
        self.onCancel = onCancel
        self.onGetWhisper = onGetWhisper
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(SpeechLanguagesRow.title)
                .font(textSize.font(.headline))
                .accessibilityAddTraits(.isHeader)
            modeSection
            LintelDivider()
            languagesSection
            if let note = model.whisperNote {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(textSize.font(.callout))
                        .foregroundStyle(LintelBrand.secondaryText)
                        .accessibilityHidden(true)
                    Text(note)
                        .font(textSize.font(.callout))
                        .foregroundStyle(LintelBrand.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            buttons
        }
        // As in `ConfirmSheet`: Esc goes through a second, invisible Cancel button; the exit command covers a focused
        // control that swallows the shortcut.
        .background {
            Button(action: onCancel) { EmptyView() }
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .onExitCommand(perform: onCancel)
        .padding(20)
        .frame(width: 460)
        .presentationBackground(LintelBrand.windowBackground)
    }

    // MARK: Mode

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            radio(.automatic, title: Self.automaticTitle, detail: Self.automaticDetail)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                radio(.single, title: Self.singleTitle, detail: nil)
                Picker(
                    selection: Binding(
                        get: { model.singleLanguage ?? "" },
                        set: { code in
                            model.chooseSingleLanguage(code)
                            model.modeChoice = .single
                        })
                ) {
                    ForEach(model.listedOptions) { option in
                        Text(option.name).font(textSize.font(.body)).tag(option.code)
                    }
                } label: {
                    Text(Self.singleLanguageLabel)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .font(textSize.font(.body))
                .fixedSize()
                .lintelSecondaryTint()
                .disabled(model.languages.isEmpty)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(Self.modeGroupLabel))
    }

    private func radio(
        _ choice: SpeechLanguagesSheetModel.ModeChoice, title: LocalizedStringResource,
        detail: LocalizedStringResource?
    ) -> some View {
        let isSelected = model.modeChoice == choice
        return Button {
            model.modeChoice = choice
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: isSelected ? "inset.filled.circle" : "circle")
                    .font(textSize.font(.body))
                    .foregroundStyle(isSelected ? LintelBrand.accent : LintelBrand.secondaryText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(textSize.font(.body))
                        .foregroundStyle(LintelBrand.ink)
                    if let detail {
                        Text(detail)
                            .font(textSize.font(.callout))
                            .foregroundStyle(LintelBrand.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: Languages

    private var languagesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.listTitle)
                    .font(textSize.font(.body, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                if let caption = model.listCaption {
                    Text(caption)
                        .font(textSize.font(.callout))
                        .foregroundStyle(LintelBrand.secondaryText)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.listedOptions) { option in
                    chip(option)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button {
                    query = ""
                    addIsPresented = true
                } label: {
                    Label {
                        Text(Self.addTitle)
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
                .buttonStyle(LintelSecondaryButtonStyle())
                .disabled(!model.canAdd)
                .popover(isPresented: $addIsPresented, arrowEdge: .bottom) { addPopover }
                if let caption = model.capCaption {
                    Text(caption)
                        .font(textSize.font(.callout))
                        .foregroundStyle(LintelBrand.secondaryText)
                }
            }
        }
    }

    private func chip(_ option: SpeechLanguageOption) -> some View {
        let code = option.code
        let isTarget = dropTarget == code
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(textSize.font(.callout))
                    .foregroundStyle(LintelBrand.secondaryText)
                    .accessibilityHidden(true)
                Text(option.name)
                    .font(textSize.font(.body))
                    .foregroundStyle(LintelBrand.ink)
                    .accessibilityLabel(Text(option.name))
                    .accessibilityHint(Text(Self.reorderHint))
                    .accessibilityAction(named: Text(Self.moveUpTitle)) { model.moveUp(code) }
                    .accessibilityAction(named: Text(Self.moveDownTitle)) { model.moveDown(code) }
                Spacer(minLength: 8)
                Button {
                    model.remove(code)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(textSize.font(.body))
                        .foregroundStyle(LintelBrand.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(Self.removeLabel(option.name)))
            }
            if model.needsWhisper(code) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Self.needsWhisperLine)
                        .font(textSize.font(.callout))
                        .foregroundStyle(LintelBrand.secondaryText)
                    if model.offersWhisperDownload(for: code) {
                        Button {
                            onGetWhisper(model.selection)
                        } label: {
                            Text(Self.getWhisperTitle).font(textSize.font(.callout))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(LintelBrand.accentText)
                    }
                }
                .padding(.leading, 24)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(LintelBrand.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isTarget ? LintelBrand.accent : LintelBrand.hairline, lineWidth: isTarget ? 2 : 1)
                .accessibilityHidden(true)
        }
        .draggable(code) {
            Text(option.name)
                .font(textSize.font(.body))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(LintelBrand.card, in: RoundedRectangle(cornerRadius: 8))
        }
        .dropDestination(for: String.self) { items, _ in
            guard let dragged = items.first, model.languages.contains(dragged) else { return false }
            model.move(dragged, to: code)
            return true
        } isTargeted: { targeted in
            if targeted {
                dropTarget = code
            } else if dropTarget == code {
                dropTarget = nil
            }
        }
    }

    private var addPopover: some View {
        let matches = model.addableOptions(matching: query)
        return VStack(alignment: .leading, spacing: 8) {
            TextField(text: $query, prompt: Text(Self.searchPrompt)) {
                Text(Self.searchPrompt)
            }
            .textFieldStyle(.roundedBorder)
            .font(textSize.font(.body))
            .focused($searchIsFocused)
            .onSubmit {
                if let first = matches.first { add(first.code) }
            }
            if matches.isEmpty {
                Text(Self.noMatches)
                    .font(textSize.font(.callout))
                    .foregroundStyle(LintelBrand.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(matches) { option in
                            Button {
                                add(option.code)
                            } label: {
                                Text(option.name)
                                    .font(textSize.font(.body))
                                    .foregroundStyle(LintelBrand.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(Self.addLabel(option.name)))
                        }
                    }
                }
                .frame(height: 240)
            }
        }
        .padding(12)
        .frame(width: 260)
        .onAppear { searchIsFocused = true }
    }

    private func add(_ code: String) {
        model.add(code)
        addIsPresented = false
    }

    // MARK: Buttons

    private var buttons: some View {
        HStack(spacing: 8) {
            Spacer()
            Button(action: onCancel) {
                Text("Cancel", comment: "Languages sheet: closes the sheet and keeps the setting as it was")
            }
            .buttonStyle(LintelSecondaryButtonStyle())
            .keyboardShortcut(.defaultAction)
            .overlay {
                RoundedRectangle(cornerRadius: LintelPrimaryButtonStyle.cornerRadius + 1)
                    .stroke(LintelBrand.accent, lineWidth: 2)
                    .padding(-1)
                    .accessibilityHidden(true)
            }
            Button {
                onDone(model.selection)
            } label: {
                Text("Done", comment: "Languages sheet: stores the edited languages and closes the sheet")
            }
            .buttonStyle(LintelPrimaryButtonStyle())
        }
    }

    // MARK: Words

    static let automaticTitle = LocalizedStringResource(
        "Automatic (recommended)", comment: "Languages sheet: mode in which Lintel recognises the language itself")
    static let automaticDetail = LocalizedStringResource(
        "Lintel recognises the language by itself. The list helps with short phrases.",
        comment: "Languages sheet: explanation under Automatic (recommended)")
    static let singleTitle = LocalizedStringResource(
        "Always one language", comment: "Languages sheet: mode in which every recording uses the one chosen language")
    static let singleLanguageLabel = LocalizedStringResource(
        "Language", comment: "Languages sheet: spoken name of the picker of the one pinned language")
    static let modeGroupLabel = LocalizedStringResource(
        "How Lintel picks the language", comment: "Languages sheet: spoken name of the Automatic / Always one choice")
    static let listTitle = LocalizedStringResource(
        "Languages I speak", comment: "Languages sheet: heading of the ordered list of the user's languages")
    static let addTitle = LocalizedStringResource(
        "Add Language…", comment: "Languages sheet: button that opens the searchable list of languages")
    static let searchPrompt = LocalizedStringResource(
        "Search Languages", comment: "Languages sheet: placeholder of the search field in Add Language")
    static let noMatches = LocalizedStringResource(
        "No languages found.", comment: "Languages sheet: the search in Add Language matches nothing")
    static let needsWhisperLine = LocalizedStringResource(
        "Needs the Whisper model.", comment: "Languages sheet: under a language the standard speech model cannot write")
    static let getWhisperTitle = LocalizedStringResource(
        "Get It in Models", comment: "Languages sheet: opens the Models pane to get the Whisper model")
    static let moveUpTitle = LocalizedStringResource(
        "Move Up", comment: "Languages sheet: spoken action that moves a language up")
    static let moveDownTitle = LocalizedStringResource(
        "Move Down", comment: "Languages sheet: spoken action that moves a language down")
    static let reorderHint = LocalizedStringResource(
        "Drag to change the order.", comment: "Languages sheet: spoken hint on a listed language")

    static func removeLabel(_ name: String) -> LocalizedStringResource {
        LocalizedStringResource(
            "Remove \(name)", comment: "Languages sheet: spoken name of the button that removes a language")
    }

    static func addLabel(_ name: String) -> LocalizedStringResource {
        LocalizedStringResource("Add \(name)", comment: "Languages sheet: spoken name of a language in Add Language")
    }
}

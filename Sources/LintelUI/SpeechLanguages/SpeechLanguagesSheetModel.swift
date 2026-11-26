import LintelKit
import SwiftUI

/// One language the Languages sheet can offer (spec `2026-11-23-automatic-language-detection`, step 2.2). The
/// plugins build the list from `SpeechLanguageCatalog`, which this target never sees.
public struct SpeechLanguageOption: Sendable, Hashable, Identifiable {
    /// Whisper's language code (`pl`, `uk`, `yue`).
    public let code: String
    /// The standard model cannot transcribe it, so a list with it records with the Whisper model.
    public let needsWhisper: Bool
    /// The name shown in the sheet, in the language of Lintel's own interface.
    public let name: String

    public var id: String { code }

    /// - Parameter name: the display name; `nil` asks `Locale` for the name in the interface language.
    public init(code: String, needsWhisper: Bool, name: String? = nil) {
        self.code = code
        self.needsWhisper = needsWhisper
        self.name = name ?? Self.displayName(for: code)
    }

    /// The language's name in the language Lintel's interface is shown in (English or Polish), not the Mac's
    /// region: a Polish Mac that shows Lintel in English gets "Polish", not "polski". The code itself when the
    /// system has no name for it.
    public static func displayName(for code: String, interfaceLanguage: String? = nil) -> String {
        let language = interfaceLanguage ?? Bundle.main.preferredLocalizations.first ?? "en"
        let name = Locale(identifier: language).localizedString(forLanguageCode: code)
        guard let name, !name.isEmpty else { return code }
        return name
    }
}

/// The editing state of `SpeechLanguagesSheet`: a draft of the shared selection that only reaches the setting
/// on Done. Pure, so every rule of the sheet is tested without a view.
public struct SpeechLanguagesSheetModel: Sendable, Equatable {
    /// The two choices of the radio group.
    public enum ModeChoice: Hashable, Sendable {
        case automatic
        case single
    }

    /// "You can list up to 10 languages."
    public static let maximumLanguages = 10

    /// The listed languages, in order.
    public private(set) var languages: [String]
    /// The list is the one derived from the Mac's languages (nothing stored).
    public private(set) var isDerived: Bool
    public var modeChoice: ModeChoice
    /// The language of "Always one language". Always one of `languages` while the list has any.
    public private(set) var singleLanguage: String?
    public let whisperInstalled: Bool

    private let derivedLanguages: [String]
    private let options: [SpeechLanguageOption]
    private let optionsByCode: [String: SpeechLanguageOption]

    /// - Parameters:
    ///   - selection: the setting as the sheet opens.
    ///   - options: every language that can be listed (the catalog, with names).
    ///   - derivedLanguages: the list from the Mac's languages, shown again when the user removes the last
    ///     language. `nil` takes `selection.languages` when the selection is derived, else an empty list (the host
    ///     derives it again after Done).
    ///   - whisperInstalled: the Whisper model is on this Mac.
    public init(
        selection: SpeechLanguageSelection, options: [SpeechLanguageOption], derivedLanguages: [String]? = nil,
        whisperInstalled: Bool
    ) {
        let byCode = Dictionary(options.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
        self.options = options
        self.optionsByCode = byCode
        self.whisperInstalled = whisperInstalled
        let derived = Self.known(derivedLanguages ?? (selection.isDerived ? selection.languages : []), in: byCode)
        self.derivedLanguages = derived
        let listed = Self.known(selection.languages, in: byCode)
        if listed.isEmpty {
            languages = derived
            isDerived = true
        } else {
            languages = listed
            isDerived = selection.isDerived
        }
        switch selection.mode {
        case .automatic:
            modeChoice = .automatic
            singleLanguage = languages.first
        case .single(let code):
            modeChoice = .single
            singleLanguage = languages.contains(code) ? code : languages.first
        }
    }

    // MARK: The result

    /// What Done stores. In "Always one language" mode without any listed language (nothing to pin), the mode
    /// stays Automatic.
    public var selection: SpeechLanguageSelection {
        let mode: SpeechLanguageSelection.Mode
        if modeChoice == .single, let singleLanguage {
            mode = .single(singleLanguage)
        } else {
            mode = .automatic
        }
        return SpeechLanguageSelection(mode: mode, languages: languages, isDerived: isDerived)
    }

    // MARK: Editing

    /// Below the cap: Add Language… is enabled.
    public var canAdd: Bool { languages.count < Self.maximumLanguages }

    /// Appends a language. Does nothing at the cap, for a listed language or for a code with no option.
    public mutating func add(_ code: String) {
        guard canAdd, !languages.contains(code), optionsByCode[code] != nil else { return }
        languages.append(code)
        isDerived = false
        if singleLanguage == nil { singleLanguage = code }
    }

    /// Removes a language. Removing the last one goes back to the list from the Mac's languages (nothing stored).
    public mutating func remove(_ code: String) {
        guard let index = languages.firstIndex(of: code) else { return }
        languages.remove(at: index)
        if languages.isEmpty {
            languages = derivedLanguages
            isDerived = true
        } else {
            isDerived = false
        }
        if let singleLanguage, languages.contains(singleLanguage) { return }
        singleLanguage = languages.first
    }

    /// Moves `code` to the place of `target` (a drop on another language).
    public mutating func move(_ code: String, to target: String) {
        guard let from = languages.firstIndex(of: code), let to = languages.firstIndex(of: target), from != to
        else { return }
        languages.remove(at: from)
        languages.insert(code, at: to)
        isDerived = false
    }

    /// `List`-style move.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let before = languages
        languages.move(fromOffsets: source, toOffset: destination)
        if languages != before { isDerived = false }
    }

    /// One place up or down (the VoiceOver actions).
    public mutating func moveUp(_ code: String) {
        guard let index = languages.firstIndex(of: code), index > 0 else { return }
        languages.swapAt(index, index - 1)
        isDerived = false
    }

    public mutating func moveDown(_ code: String) {
        guard let index = languages.firstIndex(of: code), index < languages.count - 1 else { return }
        languages.swapAt(index, index + 1)
        isDerived = false
    }

    public func canMoveUp(_ code: String) -> Bool { (languages.firstIndex(of: code) ?? 0) > 0 }

    public func canMoveDown(_ code: String) -> Bool {
        guard let index = languages.firstIndex(of: code) else { return false }
        return index < languages.count - 1
    }

    /// Picks the language of "Always one language"; only a listed one.
    public mutating func chooseSingleLanguage(_ code: String) {
        guard languages.contains(code) else { return }
        singleLanguage = code
    }

    // MARK: What the sheet shows

    /// The listed languages with their names.
    public var listedOptions: [SpeechLanguageOption] { languages.compactMap { optionsByCode[$0] } }

    public func option(for code: String) -> SpeechLanguageOption? { optionsByCode[code] }

    public func name(of code: String) -> String { optionsByCode[code]?.name ?? code }

    /// The languages Add Language… offers for a search: not listed yet, whose name or code contains the text
    /// (ignoring case and accents), sorted by name.
    public func addableOptions(matching query: String) -> [SpeechLanguageOption] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return
            options
            .filter { !languages.contains($0.code) }
            .filter { option in
                text.isEmpty
                    || option.name.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    || option.code.compare(text, options: .caseInsensitive) == .orderedSame
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// "Needs the Whisper model." under the chip.
    public func needsWhisper(_ code: String) -> Bool { optionsByCode[code]?.needsWhisper ?? false }

    /// "Get It in Models" next to that line: the language needs Whisper and Whisper is not installed.
    public func offersWhisperDownload(for code: String) -> Bool { needsWhisper(code) && !whisperInstalled }

    /// The note above Done. It follows the model choice of `SpeechEngineRouter`: in Automatic mode every listed
    /// language counts, in "Always one language" only that language.
    public var whisperNote: LocalizedStringResource? {
        switch modeChoice {
        case .automatic:
            guard languages.contains(where: needsWhisper) else { return nil }
            return LocalizedStringResource(
                "With this list, meetings and dictation use the Whisper model. It is slower than the standard one.",
                comment: "Languages sheet: note above Done when a listed language needs the Whisper model")
        case .single:
            guard let singleLanguage, needsWhisper(singleLanguage) else { return nil }
            return LocalizedStringResource(
                "With this language, meetings and dictation use the Whisper model. It is slower than the standard one.",
                comment: "Languages sheet: note above Done when the one pinned language needs the Whisper model")
        }
    }

    /// "From your Mac's languages." while the list is the derived one.
    public var listCaption: LocalizedStringResource? {
        guard isDerived else { return nil }
        return LocalizedStringResource(
            "From your Mac’s languages.",
            comment: "Languages sheet: the list comes from the languages set in macOS, nothing was chosen yet")
    }

    /// "You can list up to 10 languages." at the cap.
    public var capCaption: LocalizedStringResource? {
        guard !canAdd else { return nil }
        return LocalizedStringResource(
            "You can list up to 10 languages.",
            comment: "Languages sheet: Add Language is disabled because the list is full")
    }

    private static func known(_ codes: [String], in options: [String: SpeechLanguageOption]) -> [String] {
        var seen: Set<String> = []
        return codes.filter { options[$0] != nil && seen.insert($0).inserted }.prefix(maximumLanguages).map { $0 }
    }
}

extension SpeechLanguageSelection {
    /// The one-line summary of the Languages row: "Automatic · Polish, English" or "Always Polish".
    public func summary(names: (String) -> String) -> String {
        switch mode {
        case .automatic:
            let list = languages.map(names).joined(separator: ", ")
            return String(
                localized: "Automatic · \(list)",
                comment: "Settings Languages row: automatic detection and the listed languages, e.g. Polish, English")
        case .single(let code):
            let name = names(code)
            return String(
                localized: "Always \(name)",
                comment: "Settings Languages row: every recording is in this one language, e.g. Always Polish")
        }
    }
}

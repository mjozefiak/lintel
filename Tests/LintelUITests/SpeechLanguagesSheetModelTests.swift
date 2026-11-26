import AppKit
import LintelKit
import SwiftUI
import Testing

@testable import LintelUI

/// Spec `2026-11-23-automatic-language-detection`, step 2.2: the rules of the Languages sheet, without a view.
@Suite struct SpeechLanguagesSheetModelTests {
    /// Fixed names, so the tests do not depend on the Mac's languages.
    static let options: [SpeechLanguageOption] = [
        ("pl", false, "Polish"), ("en", false, "English"), ("uk", false, "Ukrainian"), ("de", false, "German"),
        ("fr", false, "French"), ("es", false, "Spanish"), ("it", false, "Italian"), ("cs", false, "Czech"),
        ("sk", false, "Slovak"), ("sv", false, "Swedish"), ("el", false, "Greek"), ("ja", true, "Japanese"),
        ("tr", true, "Turkish"), ("is", true, "Icelandic"),
    ].map { SpeechLanguageOption(code: $0.0, needsWhisper: $0.1, name: $0.2) }

    private func model(
        _ languages: [String], mode: SpeechLanguageSelection.Mode = .automatic, derived isDerived: Bool = false,
        derivedLanguages: [String]? = nil, whisperInstalled: Bool = false
    ) -> SpeechLanguagesSheetModel {
        SpeechLanguagesSheetModel(
            selection: SpeechLanguageSelection(mode: mode, languages: languages, isDerived: isDerived),
            options: Self.options, derivedLanguages: derivedLanguages, whisperInstalled: whisperInstalled)
    }

    private static let tenLanguages = ["pl", "en", "uk", "de", "fr", "es", "it", "cs", "sk", "sv"]

    // MARK: Opening

    @Test func aDerivedListOpensWithTheMacCaption() {
        let sheet = model(["pl", "en"], derived: true)
        #expect(sheet.languages == ["pl", "en"])
        #expect(sheet.isDerived)
        #expect(sheet.listCaption != nil)
        #expect(sheet.selection == SpeechLanguageSelection(mode: .automatic, languages: ["pl", "en"], isDerived: true))
    }

    @Test func anEditedListOpensWithoutTheCaption() {
        let sheet = model(["uk", "pl"])
        #expect(sheet.listCaption == nil)
        #expect(sheet.listedOptions.map(\.name) == ["Ukrainian", "Polish"])
    }

    @Test func unknownAndRepeatedCodesAreNotShown() {
        #expect(model(["pl", "xx", "pl", "en"]).languages == ["pl", "en"])
    }

    @Test func aSingleLanguageThatIsNotListedOpensOnTheFirstListedOne() {
        let sheet = model(["uk", "pl"], mode: .single("ja"))
        #expect(sheet.modeChoice == .single)
        #expect(sheet.singleLanguage == "uk")
    }

    // MARK: Add

    @Test func addingAppendsAndTheListIsNoLongerDerived() {
        var sheet = model(["pl", "en"], derived: true)
        sheet.add("uk")
        #expect(sheet.languages == ["pl", "en", "uk"])
        #expect(!sheet.isDerived)
        #expect(sheet.listCaption == nil)
        #expect(sheet.selection.isDerived == false)
    }

    @Test func addingAListedOrUnknownLanguageDoesNothing() {
        var sheet = model(["pl", "en"], derived: true)
        sheet.add("pl")
        sheet.add("xx")
        #expect(sheet.languages == ["pl", "en"])
        #expect(sheet.isDerived)
    }

    @Test func theListIsCappedAtTenWithItsCaption() {
        var sheet = model(Array(Self.tenLanguages.prefix(9)))
        #expect(sheet.canAdd)
        #expect(sheet.capCaption == nil)
        sheet.add("sv")
        #expect(sheet.languages.count == 10)
        #expect(!sheet.canAdd)
        #expect(sheet.capCaption != nil)
        sheet.add("el")
        #expect(sheet.languages == Self.tenLanguages)
        sheet.remove("de")
        #expect(sheet.canAdd)
        #expect(sheet.capCaption == nil)
    }

    @Test func theCapCaptionReadsAsTheSpecSays() {
        let caption = model(Self.tenLanguages).capCaption.map { String(localized: $0) }
        #expect(caption == "You can list up to 10 languages.")
    }

    // MARK: Remove

    @Test func removingALanguageKeepsTheOrderOfTheRest() {
        var sheet = model(["pl", "en", "uk"], derived: true)
        sheet.remove("en")
        #expect(sheet.languages == ["pl", "uk"])
        #expect(!sheet.isDerived)
    }

    @Test func removingTheLastLanguageGoesBackToTheMacsLanguages() {
        var sheet = model(["uk"], derivedLanguages: ["pl", "en"])
        sheet.remove("uk")
        #expect(sheet.languages == ["pl", "en"])
        #expect(sheet.isDerived)
        #expect(sheet.listCaption != nil)
        #expect(sheet.selection == SpeechLanguageSelection(mode: .automatic, languages: ["pl", "en"], isDerived: true))
    }

    @Test func removingTheLastLanguageWithoutAKnownDerivedListStoresNoList() {
        var sheet = model(["uk"])
        sheet.remove("uk")
        #expect(sheet.languages.isEmpty)
        #expect(sheet.isDerived)
        #expect(sheet.listCaption != nil)
        #expect(sheet.selection.isDerived)
    }

    @Test func removingTheSingleLanguageMovesItToTheFirstListedOne() {
        var sheet = model(["pl", "en", "uk"], mode: .single("en"))
        sheet.remove("en")
        #expect(sheet.singleLanguage == "pl")
        #expect(sheet.selection.mode == .single("pl"))
    }

    // MARK: Reorder

    @Test func droppingALanguageOnAnotherTakesItsPlace() {
        var sheet = model(["pl", "en", "uk", "de"], derived: true)
        sheet.move("pl", to: "uk")
        #expect(sheet.languages == ["en", "uk", "pl", "de"])
        #expect(!sheet.isDerived)
        sheet.move("de", to: "en")
        #expect(sheet.languages == ["de", "en", "uk", "pl"])
    }

    @Test func droppingALanguageOnItselfChangesNothing() {
        var sheet = model(["pl", "en"], derived: true)
        sheet.move("pl", to: "pl")
        #expect(sheet.languages == ["pl", "en"])
        #expect(sheet.isDerived)
    }

    @Test func listMovesFollowTheOffsets() {
        var sheet = model(["pl", "en", "uk"], derived: true)
        sheet.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(sheet.languages == ["uk", "pl", "en"])
        #expect(!sheet.isDerived)
    }

    @Test func voiceOverMovesStopAtTheEnds() {
        var sheet = model(["pl", "en", "uk"])
        #expect(!sheet.canMoveUp("pl"))
        #expect(!sheet.canMoveDown("uk"))
        sheet.moveUp("pl")
        sheet.moveDown("uk")
        #expect(sheet.languages == ["pl", "en", "uk"])
        sheet.moveDown("pl")
        #expect(sheet.languages == ["en", "pl", "uk"])
        sheet.moveUp("uk")
        #expect(sheet.languages == ["en", "uk", "pl"])
    }

    // MARK: Mode

    @Test func alwaysOneLanguagePinsTheChosenListedLanguage() {
        var sheet = model(["pl", "en"])
        sheet.modeChoice = .single
        #expect(sheet.selection.mode == .single("pl"))
        sheet.chooseSingleLanguage("en")
        #expect(sheet.selection.mode == .single("en"))
        sheet.chooseSingleLanguage("uk")
        #expect(sheet.selection.mode == .single("en"))
        sheet.modeChoice = .automatic
        #expect(sheet.selection.mode == .automatic)
    }

    @Test func alwaysOneLanguageWithNothingListedStaysAutomatic() {
        var sheet = model(["uk"])
        sheet.modeChoice = .single
        sheet.remove("uk")
        #expect(sheet.selection.mode == .automatic)
    }

    // MARK: Whisper

    @Test func aLanguageThatNeedsWhisperGetsTheLineAndTheDownloadWhileWhisperIsMissing() {
        let missing = model(["pl", "ja"])
        #expect(!missing.needsWhisper("pl"))
        #expect(missing.needsWhisper("ja"))
        #expect(missing.offersWhisperDownload(for: "ja"))
        #expect(!missing.offersWhisperDownload(for: "pl"))
        let installed = model(["pl", "ja"], whisperInstalled: true)
        #expect(installed.needsWhisper("ja"))
        #expect(!installed.offersWhisperDownload(for: "ja"))
    }

    @Test func theWhisperNoteShowsWhileAListedLanguageNeedsIt() {
        var sheet = model(["pl", "en"])
        #expect(sheet.whisperNote == nil)
        sheet.add("ja")
        #expect(
            sheet.whisperNote.map { String(localized: $0) }
                == "With this list, meetings and dictation use the Whisper model. It is slower than the standard one.")
        sheet.remove("ja")
        #expect(sheet.whisperNote == nil)
    }

    @Test func inOneLanguageModeOnlyThatLanguageCountsForTheNote() {
        var sheet = model(["pl", "ja"], mode: .single("pl"))
        #expect(sheet.whisperNote == nil)
        sheet.chooseSingleLanguage("ja")
        #expect(sheet.whisperNote != nil)
        sheet.modeChoice = .automatic
        #expect(sheet.whisperNote != nil)
    }

    // MARK: Add Language…

    @Test func addLanguageOffersTheUnlistedLanguagesByName() {
        let sheet = model(["pl", "en", "uk", "de", "fr", "es", "it", "cs", "sk"])
        #expect(sheet.addableOptions(matching: "").map(\.code) == ["el", "is", "ja", "sv", "tr"])
    }

    @Test func addLanguageSearchesNamesIgnoringCaseAndAccentsAndExactCodes() {
        let options = [
            SpeechLanguageOption(code: "pl", needsWhisper: false, name: "Polish"),
            SpeechLanguageOption(code: "fr", needsWhisper: false, name: "Français"),
            SpeechLanguageOption(code: "fi", needsWhisper: false, name: "Finnish"),
        ]
        let sheet = SpeechLanguagesSheetModel(
            selection: SpeechLanguageSelection(mode: .automatic, languages: ["pl"], isDerived: false),
            options: options, whisperInstalled: false)
        #expect(sheet.addableOptions(matching: "FRANCAIS").map(\.code) == ["fr"])
        #expect(sheet.addableOptions(matching: " fi ").map(\.code) == ["fi"])
        #expect(sheet.addableOptions(matching: "pol").isEmpty)
        #expect(sheet.addableOptions(matching: "zzz").isEmpty)
    }

    // MARK: Row

    @MainActor @Test func theRowSummaryNamesTheModeAndTheLanguages() {
        let automatic = SpeechLanguageSelection(mode: .automatic, languages: ["pl", "en"], isDerived: true)
        let row = SpeechLanguagesRow(selection: automatic, options: Self.options) {}
        #expect(row.summary == "Automatic · Polish, English")
        let single = SpeechLanguageSelection(mode: .single("pl"), languages: ["pl", "en"], isDerived: false)
        #expect(SpeechLanguagesRow(selection: single, options: Self.options) {}.summary == "Always Polish")
    }

    @Test func theRowWordsReadAsTheSpecSays() {
        #expect(String(localized: SpeechLanguagesRow.title) == "Languages")
        #expect(String(localized: SpeechLanguagesRow.editTitle) == "Edit…")
        #expect(String(localized: SpeechLanguagesRow.caption) == "Shared by Dictation and Meetings.")
    }

    @Test func displayNamesFollowTheInterfaceLanguage() {
        #expect(SpeechLanguageOption.displayName(for: "pl", interfaceLanguage: "en") == "Polish")
        #expect(SpeechLanguageOption.displayName(for: "pl", interfaceLanguage: "pl") == "polski")
        #expect(SpeechLanguageOption(code: "uk", needsWhisper: false, name: "Custom").name == "Custom")
        #expect(!SpeechLanguageOption.displayName(for: "yue", interfaceLanguage: "en").isEmpty)
    }
}

/// The row and the sheet draw in every state the spec names.
@MainActor
@Suite struct SpeechLanguagesViewTests {
    private func render(_ view: some View) throws -> NSSize {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return try #require(renderer.nsImage).size
    }

    @Test func theRowAndTheSheetRender() throws {
        let options = SpeechLanguagesSheetModelTests.options
        let selection = SpeechLanguageSelection(mode: .automatic, languages: ["pl", "en", "ja"], isDerived: false)
        let row = try render(SpeechLanguagesRow(selection: selection, options: options) {})
        #expect(row.width > 0 && row.height > 0)
        let sheet = try render(
            SpeechLanguagesSheet(
                model: SpeechLanguagesSheetModel(selection: selection, options: options, whisperInstalled: false),
                onDone: { _ in }, onCancel: {}, onGetWhisper: { _ in }))
        #expect(sheet.width == 460)
        #expect(sheet.height > 200)
    }
}

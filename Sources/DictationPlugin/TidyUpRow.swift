import LintelUI
import SwiftUI

/// What each value of "Tidy up my text" says about itself (spec `2026-11-25-dictation-cleanup-levels`, UI/UX): a name, a
/// one-line help and, for the levels that change the text, one invented sentence before and after. People choose by
/// the result, not by a description of the machinery. Every sentence here is invented; none comes from a real dictation.
enum TidyUpText {
    /// An invented sentence as dictated and as it is pasted at a level.
    struct Example: Equatable {
        var before: String
        var after: String
    }

    static var title: Text {
        Text("Tidy up my text", comment: "Settings → Dictation: the popup that says how much Lintel tidies the text")
    }

    static func name(_ choice: FormattingSettingsModel.TidyChoice) -> Text {
        switch choice {
        case .off: Text("Off", comment: "Settings → Dictation, Tidy up my text: the text is pasted as spoken")
        case .light: Text("Light", comment: "Settings → Dictation, Tidy up my text: only filler words are removed")
        case .standard: Text("Standard", comment: "Settings → Dictation, Tidy up my text: corrections and lists")
        case .full:
            Text("Full", comment: "Settings → Dictation, Tidy up my text: layout, paragraphs and a smoother style")
        }
    }

    static func help(_ choice: FormattingSettingsModel.TidyChoice) -> Text {
        switch choice {
        case .off:
            Text(
                "Pastes exactly what you said.",
                comment: "Settings → Dictation: help under Tidy up my text when it is off")
        case .light:
            Text(
                "Removes “um” and “uh”. Never changes your words.",
                comment: "Settings → Dictation: help under Tidy up my text at the Light level")
        case .standard:
            Text(
                "Also keeps only your corrections and turns spoken lists into lists.",
                comment: "Settings → Dictation: help under Tidy up my text at the Standard level")
        case .full:
            Text(
                "Also lays out emails and long texts and smooths the style. Numbers and names stay.",
                comment: "Settings → Dictation: help under Tidy up my text at the Full level")
        }
    }

    /// The line under Full's help while the built-in model is the smallest one (spec A6).
    static var smallModelHint: Text {
        Text(
            "Works best with the Recommended assistant.",
            comment: "Settings → Dictation: under Tidy up my text at Full, shown with the smallest built-in model")
    }

    /// The example line of a value; `nil` for Off, which changes nothing. Read from the language of the process.
    static func example(_ choice: FormattingSettingsModel.TidyChoice) -> Example? {
        switch choice {
        case .off:
            return nil
        case .light:
            return Example(
                before: String(
                    localized: "Um, so the meeting is on Tuesday.",
                    comment: "Settings → Dictation: invented sentence as dictated, Light example"),
                after: String(
                    localized: "So the meeting is on Tuesday.",
                    comment: "Settings → Dictation: the Light example after tidying"))
        case .standard:
            return Example(
                before: String(
                    localized: "The meeting is on Tuesday, sorry, Wednesday.",
                    comment: "Settings → Dictation: invented sentence as dictated, Standard example"),
                after: String(
                    localized: "The meeting is on Wednesday.",
                    comment: "Settings → Dictation: the Standard example after tidying"))
        case .full:
            // "⏎" stands for a line break, so the example fits two lines; the pasted text has real ones.
            return Example(
                before: String(
                    localized: "Hi Anna, the report is ready. We still need to talk about the budget. Thanks, Tom",
                    comment: "Settings → Dictation: invented sentence as dictated, Full example"),
                after: String(
                    localized:
                        "Hi Anna,⏎⏎The report is ready.⏎⏎We still need to talk about the budget.⏎⏎Thanks,⏎Tom",
                    comment: "Settings → Dictation: the Full example after tidying; ⏎ marks a line break"))
        }
    }

    /// What VoiceOver reads for an example: one element, with the arrow said as "becomes".
    static func spokenExample(_ example: Example) -> String {
        let after = example.after.replacingOccurrences(of: "⏎⏎", with: " ").replacingOccurrences(of: "⏎", with: " ")
        return String(
            localized: "Example: \(example.before) becomes \(after)",
            comment: "Settings → Dictation: VoiceOver text of the example under Tidy up my text")
    }
}

/// The "Tidy up my text" row: the popup (Off, Light, Standard), its help line and the example of the chosen value.
/// Used by the Dictation pane and drawn alone by the gallery.
struct TidyUpRow: View {
    @Binding var choice: FormattingSettingsModel.TidyChoice
    /// The values the popup lists (Full only while it is offered).
    var choices: [FormattingSettingsModel.TidyChoice] = FormattingSettingsModel.TidyChoice.allCases
    /// Whether the line "Works best with the Recommended assistant." shows (Full on the smallest built-in model).
    var showsSmallModelHint = false
    @Environment(\.lintelTextSize) private var textSize

    var body: some View {
        MenuPicker(selection: $choice, title: TidyUpText.title) {
            ForEach(choices, id: \.self) { value in
                TidyUpText.name(value).font(textSize.font(.body)).tag(value)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                TidyUpText.title.font(textSize.font(.body))
                TidyUpText.help(choice).font(textSize.font(.callout)).foregroundStyle(LintelBrand.secondaryText)
                if showsSmallModelHint {
                    TidyUpText.smallModelHint.font(textSize.font(.callout)).foregroundStyle(LintelBrand.secondaryText)
                }
                if let example = TidyUpText.example(choice) {
                    TidyUpExample(example: example).padding(.top, 2)
                }
            }
        }
    }
}

/// Two lines: what was said (secondary) and what is pasted (primary) after an arrow.
struct TidyUpExample: View {
    let example: TidyUpText.Example
    @Environment(\.lintelTextSize) private var textSize

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: "“\(example.before)”").foregroundStyle(LintelBrand.secondaryText)
            Text(verbatim: "→ “\(example.after)”")
        }
        .font(textSize.font(.callout))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: TidyUpText.spokenExample(example)))
    }
}

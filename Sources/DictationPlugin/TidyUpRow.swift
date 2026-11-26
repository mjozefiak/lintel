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
        }
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
        }
    }

    /// What VoiceOver reads for an example: one element, with the arrow said as "becomes".
    static func spokenExample(_ example: Example) -> String {
        String(
            localized: "Example: \(example.before) becomes \(example.after)",
            comment: "Settings → Dictation: VoiceOver text of the example under Tidy up my text")
    }
}

/// The "Tidy up my text" row: the popup (Off, Light, Standard), its help line and the example of the chosen value.
/// Used by the Dictation pane and drawn alone by the gallery.
struct TidyUpRow: View {
    @Binding var choice: FormattingSettingsModel.TidyChoice
    @Environment(\.lintelTextSize) private var textSize

    var body: some View {
        MenuPicker(selection: $choice, title: TidyUpText.title) {
            ForEach(FormattingSettingsModel.TidyChoice.allCases, id: \.self) { value in
                TidyUpText.name(value).font(textSize.font(.body)).tag(value)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                TidyUpText.title.font(textSize.font(.body))
                TidyUpText.help(choice).font(textSize.font(.callout)).foregroundStyle(LintelBrand.secondaryText)
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

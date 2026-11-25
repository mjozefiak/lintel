import Foundation

/// Reads the writing system and the length of a piece of transcribed text. Pure, no model: the language logic
/// uses it on the text of a segment.
public enum TextScript {
    /// The script most of the letters of `text` are written in, or `nil` when it has no letters ("...", "42").
    public static func dominant(in text: String) -> LanguageScript? {
        var counts: [LanguageScript: Int] = [:]
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            counts[script(of: scalar), default: 0] += 1
        }
        // A tie goes to the first script of `allCases`, so the answer never depends on hashing order.
        var best: (script: LanguageScript, count: Int)?
        for script in LanguageScript.allCases {
            guard let count = counts[script], count > (best?.count ?? 0) else { continue }
            best = (script, count)
        }
        return best?.script
    }

    static func script(of scalar: Unicode.Scalar) -> LanguageScript {
        switch scalar.value {
        case 0x41...0x5A, 0x61...0x7A, 0xAA, 0xBA, 0xC0...0xD6, 0xD8...0xF6, 0xF8...0x24F, 0x1E00...0x1EFF,
            0x2C60...0x2C7F, 0xA720...0xA7FF:
            return .latin
        case 0x400...0x52F, 0x1C80...0x1C8F, 0x2DE0...0x2DFF, 0xA640...0xA69F:
            return .cyrillic
        case 0x370...0x3FF, 0x1F00...0x1FFF:
            return .greek
        default:
            return .other
        }
    }

    /// Words as the system's word boundaries see them, so Chinese, Japanese and Thai (no spaces) count too.
    public static func wordCount(_ text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords]) { word, _, _, _ in
            if word != nil { count += 1 }
        }
        return count
    }
}

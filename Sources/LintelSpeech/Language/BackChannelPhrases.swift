import Foundation

/// Short acknowledgements and the phrases speech models invent on silence, per language, as data.
///
/// `backChannel` entries are whole utterances ("thank you", "tak"): a text matches when it is one of them or one
/// repeated ("yeah yeah"). `hallucinations` entries are phrases a model writes on noise ("Thanks for watching",
/// "Napisy stworzone przez społeczność Amara.org"): a text matches when it contains one. Both are compared after
/// `normalize` (lowercase, no punctuation or accents, single spaces). The lists are deliberately short and
/// extended only from measurements (spec, measurement gate); they are not a language model.
public enum BackChannelPhrases {
    static let backChannel: [String: Set<String>] = [
        "en": [
            "thank you", "thanks", "yeah", "yes", "yep", "okay", "ok", "all right", "alright", "right", "sure",
            "mm hmm", "mhm", "uh huh", "hmm", "uh", "um", "bye", "bye bye", "you", "great",
            "i see", "got it",
        ],
        "pl": [
            "dziekuje", "dzieki", "dziekuje bardzo", "tak", "no", "nie", "okej", "ok", "dobrze", "dobra", "aha", "mhm",
            "mm", "hm", "yhm", "no tak", "no dobra", "super", "swietnie", "jasne", "cos", "czesc", "do widzenia",
            "prosze",
        ],
        "de": ["danke", "ja", "nein", "okay", "ok", "genau", "gut", "hm", "mhm", "tschuss", "also", "stimmt"],
        "es": ["gracias", "si", "no", "vale", "bien", "claro", "ajá", "aja", "hm", "mhm", "adios", "bueno"],
        "fr": ["merci", "oui", "non", "ok", "d'accord", "daccord", "bien", "ah", "hm", "mhm", "au revoir", "voila"],
        "it": ["grazie", "si", "no", "ok", "va bene", "bene", "certo", "ah", "hm", "mhm", "ciao", "allora"],
        "nl": ["dank je", "dankjewel", "bedankt", "ja", "nee", "ok", "oke", "goed", "hm", "mhm", "doei"],
        "pt": ["obrigado", "obrigada", "sim", "nao", "ok", "certo", "bem", "hm", "mhm", "tchau"],
        "cs": ["dekuji", "dik", "ano", "ne", "ok", "dobre", "no", "hm", "mhm", "nashledanou", "jo"],
        "uk": ["дякую", "так", "ні", "ага", "добре", "гм", "ок", "добре дякую"],
        "ru": ["спасибо", "да", "нет", "ага", "хорошо", "угу", "ок", "ладно"],
    ]

    static let hallucinations: [String: Set<String>] = [
        "en": [
            "thanks for watching", "thank you for watching", "please subscribe", "subtitles by the amara org community",
            "like and subscribe", "see you in the next video",
        ],
        "pl": [
            "napisy stworzone przez spolecznosc amara org", "dziekuje za ogladanie", "dziekuje za uwage",
            "subskrybuj", "do zobaczenia w nastepnym odcinku",
        ],
        "de": [
            "untertitel der amara org community", "vielen dank fur ihre aufmerksamkeit",
            "untertitel im auftrag des zdf",
        ],
        "es": ["subtitulos realizados por la comunidad de amara org", "gracias por ver el video"],
        "fr": ["sous titres realises para la communaute d amara org", "merci d avoir regarde cette video"],
        "it": ["sottotitoli creati dalla comunita amara org", "grazie per la visione"],
        "ru": ["продолжение следует", "субтитры сделал dimatorzok", "субтитры создавал dimatorzok"],
        "uk": ["субтитри створив dimatorzok", "дякую за перегляд"],
    ]

    /// Lowercase, accents removed, punctuation turned into spaces, single spaces. Polish `ł` and `ø`-like letters
    /// are not decomposed by Unicode, so they are folded by hand.
    public static func normalize(_ text: String) -> String {
        var folded = text.lowercased().folding(options: [.diacriticInsensitive], locale: nil)
        folded = folded.replacingOccurrences(of: "ł", with: "l").replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "ø", with: "o")
        let scalars = folded.unicodeScalars.map { scalar -> Character in
            // Keep the apostrophe of "d'accord" meaningful by dropping it, like the other punctuation inside a word.
            scalar.properties.isAlphabetic || CharacterSet.decimalDigits.contains(scalar) ? Character(scalar) : " "
        }
        return String(scalars).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Whether `text` is a back-channel utterance of `language` (or that utterance repeated).
    public static func isBackChannel(_ text: String, language: String) -> Bool {
        matchesUtterance(normalize(text), in: backChannelSet(for: language))
    }

    /// Whether `text` is a back-channel utterance of any language.
    public static func isBackChannelInAnyLanguage(_ text: String) -> Bool {
        let normalized = normalize(text)
        return backChannel.values.contains { matchesUtterance(normalized, in: foldAll($0)) }
    }

    /// Whether `text` contains a phrase models are known to invent on silence, in any language.
    public static func isHallucination(_ text: String) -> Bool {
        let padded = " \(normalize(text)) "
        guard padded.count > 2 else { return false }
        return hallucinations.values.contains { phrases in
            phrases.contains { padded.contains(" \(normalize($0)) ") }
        }
    }

    private static func backChannelSet(for language: String) -> Set<String> {
        foldAll(backChannel[language] ?? [])
    }

    private static func foldAll(_ set: Set<String>) -> Set<String> { Set(set.map(normalize)) }

    private static func matchesUtterance(_ normalized: String, in phrases: Set<String>) -> Bool {
        guard !normalized.isEmpty else { return false }
        if phrases.contains(normalized) { return true }
        // One phrase repeated ("yeah yeah", "thank you thank you").
        let words = normalized.split(separator: " ").map(String.init)
        for length in 1...max(1, words.count / 2) where words.count % length == 0 && words.count / length >= 2 {
            let unit = words[0..<length].joined(separator: " ")
            guard phrases.contains(unit) else { continue }
            let repeated = stride(from: 0, to: words.count, by: length).allSatisfy {
                words[$0..<($0 + length)].joined(separator: " ") == unit
            }
            if repeated { return true }
        }
        return false
    }
}

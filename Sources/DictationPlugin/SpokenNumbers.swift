import Foundation

/// Numbers in dictated text, for `FormatterGuard`: which numbers a transcript holds (as digits or as Polish and
/// English number words) and which numbers a cleaned text holds. Pure logic.
///
/// The guard asks one question: does the cleaned text contain a number the transcript does not? So the words are
/// read leniently: every number word is a number on its own, and every run of consecutive number words counts
/// in every contiguous split ("pięćset jeden dwieście trzydzieści cztery" gives 501, 234 and the parts). Letting
/// a few more numbers through costs nothing; rejecting a correct "25 000" for "dwadzieścia pięć tysięcy" costs
/// the cleaning of the whole chunk.
enum SpokenNumbers {
    /// How a number word combines with the words next to it.
    private enum Word {
        /// A unit, teen, ten or (Polish) hundred: added to the current number.
        case add(Int)
        /// "hundred": multiplies the current number (1 when there is none).
        case hundred
        case thousand
        case million
        case billion
    }

    // MARK: Digits

    private static let digitRuns = try? NSRegularExpression(
        pattern: #"\d{1,3}(?:[   ]\d{3})+|\d+"#)

    /// A number written in digits. "501 234 567" is read both as one number and as three groups, because it may be
    /// one number ("25 000") or a phone number said in groups.
    struct Written: Equatable {
        var joined: Int
        var groups: [Int]
    }

    /// Every number written in digits, in order: "25 000" (groups of three digits after a space join), "12:00"
    /// is 12 and 0, "2,5" is 2 and 5, "1989" is 1989.
    static func written(in text: String) -> [Written] {
        guard let digitRuns else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return digitRuns.matches(in: text, range: range).compactMap { match in
            guard let found = Range(match.range, in: text) else { return nil }
            let digits = text[found].filter { $0.isASCII && $0.isNumber }
            let groups = text[found].split { !($0.isASCII && $0.isNumber) }.map { Int($0) ?? Int.max }
            return Written(joined: Int(digits) ?? Int.max, groups: groups)
        }
    }

    // MARK: Words

    /// Every number the text says in words, with the parts of every run of number words (see the type's note).
    static func spokenNumbers(in text: String) -> Set<Int> {
        var numbers: Set<Int> = []
        var run: [Word] = []
        func flush() {
            guard !run.isEmpty else { return }
            let limit = min(run.count, 8)
            for start in 0..<limit {
                for end in start..<min(run.count, start + 8) {
                    if let value = evaluate(run[start...end]) { numbers.insert(value) }
                }
            }
            run = []
        }
        for token in tokens(in: text) {
            if let word = word(for: token) {
                run.append(word)
            } else if let value = special[token] {
                flush()
                numbers.formUnion(value)
            } else {
                flush()
            }
        }
        flush()
        return numbers
    }

    /// Whether a word is part of a spoken number, for counting a spoken number as one word.
    static func isNumberWord(_ token: String) -> Bool { word(for: token) != nil }

    /// Whether the text says a number in words.
    static func containsNumberWord(_ text: String) -> Bool { tokens(in: text).contains { isNumberWord($0) } }

    /// The text's words, where a run of numbers (digits or number words, "25 000" and "dwadzieścia pięć tysięcy"
    /// alike) counts as one.
    static func wordCount(in text: String) -> Int {
        var count = 0
        var inRun = false
        for part in text.split(whereSeparator: \.isWhitespace) {
            for piece in part.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
                let token = String(piece)
                let isNumber = token.allSatisfy { $0.isASCII && $0.isNumber } || isNumberWord(token)
                // "000" after a number is the rest of "25 000" even when a space came between.
                if isNumber {
                    if !inRun { count += 1 }
                } else {
                    count += 1
                }
                inRun = isNumber
            }
        }
        return count
    }

    /// Every number of a text, in digits or in words, that a cleaned version may keep.
    static func allowed(in text: String) -> Set<Int> {
        var numbers = spokenNumbers(in: text)
        for number in written(in: text) {
            numbers.insert(number.joined)
            numbers.formUnion(number.groups)
        }
        // Zero is also the "00" of a time and the "000" of a thousand.
        numbers.insert(0)
        return numbers
    }

    /// The numbers written in digits in `output` that `input` does not hold, in digits or in words.
    static func newNumbers(in output: String, comparedTo input: String) -> [Int] {
        let known = allowed(in: input)
        return written(in: output).compactMap { number in
            if known.contains(number.joined) || number.groups.allSatisfy(known.contains) { return nil }
            return number.joined
        }
    }

    private static func tokens(in text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static func evaluate(_ words: ArraySlice<Word>) -> Int? {
        var total = 0
        var current = 0
        var sawAny = false
        for word in words {
            sawAny = true
            switch word {
            case .add(let value): current += value
            case .hundred: current = max(current, 1) * 100
            case .thousand:
                total += max(current, 1) * 1000
                current = 0
            case .million:
                total += max(current, 1) * 1_000_000
                current = 0
            case .billion:
                total += max(current, 1) * 1_000_000_000
                current = 0
            }
        }
        return sawAny ? total + current : nil
    }

    private static func word(for token: String) -> Word? {
        if let word = exact[token] { return word }
        for (stem, word) in stems where token.hasPrefix(stem) { return word }
        return nil
    }

    /// Words that stand for a fraction or a part of an hour: "dwa i pół" is 2,5, "half past ten" is 10:30.
    private static let special: [String: Set<Int>] = [
        "pół": [5, 30, 50], "półtora": [1, 5], "półtorej": [1, 5], "połowa": [5, 50], "połowy": [5, 50],
        "half": [5, 30, 50], "kwadrans": [15, 45], "kwadransa": [15, 45], "quarter": [15, 45, 25],
        "południe": [12], "południa": [12], "noon": [12], "północ": [0, 12, 24], "midnight": [0, 12, 24],
        "tuzin": [12], "dozen": [12], "para": [2], "pair": [2], "couple": [2],
    ]

    private static let exact: [String: Word] = {
        var words: [String: Word] = [:]
        func add(_ value: Int, _ forms: String) {
            for form in forms.split(separator: " ") { words[String(form)] = .add(value) }
        }
        // Polish cardinals and ordinals, every case that people say a number in (dates, hours, amounts).
        add(0, "zero zerowy")
        add(
            1,
            "jeden jedna jedno jednego jednej jedną jednemu jednym jedynka pierwszy pierwsza pierwsze pierwszego pierwszej pierwszym pierwszą pierwszych"
        )
        add(2, "dwa dwie dwóch dwu dwoma dwom dwoje drugi druga drugie drugiego drugiej drugim drugą drugich")
        add(3, "trzy trzech trzem trzema trzej trzeci trzecia trzecie trzeciego trzeciej trzecim trzecią trzecich")
        add(4, "cztery czterech czterem czterema czwarty czwarta czwarte czwartego czwartej czwartym czwartą czwartych")
        add(5, "pięć pięciu pięcioma piąty piąta piąte piątego piątej piątym piątą piątych")
        add(6, "sześć sześciu sześcioma szósty szósta szóste szóstego szóstej szóstym szóstą szóstych")
        add(7, "siedem siedmiu siedmioma siódmy siódma siódme siódmego siódmej siódmym siódmą siódmych")
        add(8, "osiem ośmiu ośmioma ósmy ósma ósme ósmego ósmej ósmym ósmą ósmych")
        add(
            9,
            "dziewięć dziewięciu dziewięcioma dziewiąty dziewiąta dziewiąte dziewiątego dziewiątej dziewiątym dziewiątą dziewiątych"
        )
        add(
            10,
            "dziesięć dziesięciu dziesięcioma dziesiąty dziesiąta dziesiąte dziesiątego dziesiątej dziesiątym dziesiątą dziesiątych"
        )
        add(100, "sto stu setny setna setne")
        add(200, "dwieście dwustu")
        add(300, "trzysta trzystu")
        add(400, "czterysta czterystu")
        add(500, "pięćset pięciuset")
        add(600, "sześćset sześciuset")
        add(700, "siedemset siedmiuset")
        add(800, "osiemset ośmiuset")
        add(900, "dziewięćset dziewięciuset")
        for form in ["tysiąc", "tysiące", "tysięcy", "tysiąca", "tysiącu", "tysiącem", "tysiącach", "tysięczny"] {
            words[form] = .thousand
        }
        for form in ["milion", "miliony", "milionów", "miliona", "milionie", "milionem"] { words[form] = .million }
        for form in ["miliard", "miliardy", "miliardów", "miliarda"] { words[form] = .billion }

        // English cardinals and ordinals.
        add(0, "nought")
        add(1, "one first")
        add(2, "two second")
        add(3, "three third")
        add(4, "four fourth")
        add(5, "five fifth")
        add(6, "six sixth")
        add(7, "seven seventh")
        add(8, "eight eighth")
        add(9, "nine ninth")
        add(10, "ten tenth")
        add(11, "eleven eleventh")
        add(12, "twelve twelfth")
        add(13, "thirteen thirteenth")
        add(14, "fourteen fourteenth")
        add(15, "fifteen fifteenth")
        add(16, "sixteen sixteenth")
        add(17, "seventeen seventeenth")
        add(18, "eighteen eighteenth")
        add(19, "nineteen nineteenth")
        add(20, "twenty twentieth")
        add(30, "thirty thirtieth")
        add(40, "forty fortieth")
        add(50, "fifty fiftieth")
        add(60, "sixty sixtieth")
        add(70, "seventy seventieth")
        add(80, "eighty eightieth")
        add(90, "ninety ninetieth")
        words["hundred"] = .hundred
        words["thousand"] = .thousand
        words["million"] = .million
        words["billion"] = .billion
        return words
    }()

    /// Polish teens and tens by stem, with their ordinals and cases: "jedenaście", "jedenastej", "dwudziestego".
    private static let stems: [(String, Word)] = [
        ("jedenast", .add(11)), ("dwunast", .add(12)), ("trzynast", .add(13)), ("czternast", .add(14)),
        ("piętnast", .add(15)), ("szesnast", .add(16)), ("siedemnast", .add(17)), ("osiemnast", .add(18)),
        ("dziewiętnast", .add(19)),
        ("jedenaści", .add(11)), ("dwunaści", .add(12)), ("dwanaści", .add(12)), ("trzynaści", .add(13)),
        ("czternaści", .add(14)), ("piętnaści", .add(15)), ("szesnaści", .add(16)), ("siedemnaści", .add(17)),
        ("osiemnaści", .add(18)), ("dziewiętnaści", .add(19)),
        ("dwadzieści", .add(20)), ("dwudziest", .add(20)), ("dwudziestu", .add(20)),
        ("trzydzie", .add(30)), ("czterdzie", .add(40)),
        ("pięćdziesi", .add(50)), ("sześćdziesi", .add(60)), ("siedemdziesi", .add(70)),
        ("osiemdziesi", .add(80)), ("dziewięćdziesi", .add(90)),
    ]
}

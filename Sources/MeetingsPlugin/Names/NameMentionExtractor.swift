import Foundation

/// Finds the places in a transcript where somebody's name may have been said, and the excerpts around them that
/// go to the notes model (spec `2026-11-25-meeting-speaker-names`: Architecture → `NameMentionExtractor`). Pure
/// and cheap: it is a first filter, not an interpretation. The model (`SpeakerNamePass`, step 1.3) decides what
/// each candidate is and `NameEvidenceGuard` checks its answer against the transcript, so a candidate here is a
/// hint and a false one costs an excerpt, never a name.
///
/// A candidate is:
/// - a name of the platform's or the calendar's list (`knownNames`), in any form the transcript uses (`Marku`,
///   `Markiem`) — `NotesText.namesMatch` carries the Polish stem rule, while `NotesText.wordsMatch` needs five
///   shared letters and would miss `Marek`/`Marku` and `Anna`/`Anno`;
/// - a capitalised word that is not the start of a sentence, not a weekday or a month (`Temporal`) and not in
///   `ignored`: a bare capital is a hint (a person, a product, a city), and the model reads the excerpt;
/// - a capitalised word that follows one of the introduction and announcement phrases below; the candidate
///   carries that kind, so step 1.3 knows what the excerpt holds;
/// - a capitalised word followed by a comma: a vocative ("Marku, zrobisz to?"), `addressed`. A sentence that
///   opens with a capital and a comma is a vocative only when it is a question, so "Widzę, że…" is none.
///
/// The `ignored` list cannot name every product, city or company, and that is on purpose: it keeps the most
/// common ones (the tools a meeting talks about, a few cities, the greetings that open a sentence with a comma)
/// out of the 40 excerpts so the budget goes to names. The final interpretation is the model's.
struct NameMentionExtractor: Sendable {
    /// The most excerpts one pass sends to the model (spec 1.2: 40).
    static let maximumExcerpts = 40

    /// The most words between a trigger and the name it introduces ("głos ma pan poseł Kowalski": three).
    static let lookahead = 4

    /// The names the platform or the calendar already has; empty in F1. A name of the list is a candidate in
    /// every form the transcript uses, and its nominative spelling wins over the transcript's.
    var knownNames: [String]

    init(knownNames: [String] = []) {
        self.knownNames = knownNames
    }

    /// One name the extractor found, with the segment it stands in.
    struct Candidate: Equatable, Sendable {
        /// The name as the transcript spells it (`Marku`), or the known list's spelling (`Marek`).
        var name: String
        /// The index of the segment in the extractor's input.
        var segment: Int
        /// The phrase that found it, or `nil` for a bare capitalised word (or a known name): the model says
        /// what it is.
        var kind: NameEvidenceKind?
    }

    /// The segments around a candidate that the model reads: the candidate's own segment, and its neighbour
    /// before and after when they exist. Overlapping excerpts are merged into one.
    struct Excerpt: Equatable, Sendable {
        /// The indices of the excerpt's segments in the extractor's input.
        var range: ClosedRange<Int>
        var segments: [NameSegment]
        /// The candidates that stand in `segments`.
        var candidates: [Candidate]
        /// The excerpt was made around a phrase, a vocative or a known name (the first tier), not only around
        /// bare capitalised words.
        var isPrimary = false
    }

    struct Outcome: Equatable, Sendable {
        /// The excerpts to send, in transcript order.
        var excerpts: [Excerpt]
        /// How many excerpts the limit cut. A count for the trace; the names in them are never sent.
        var droppedExcerpts: Int

        /// Every candidate sent to the model, in transcript order.
        var candidates: [Candidate] { excerpts.flatMap(\.candidates) }
    }

    /// The excerpts for a transcript: one per run of neighbouring candidates (their windows overlap).
    ///
    /// At most `maximumExcerpts` excerpts are kept, and an excerpt that holds a phrase candidate (an
    /// introduction, an announcement or a vocative) wins over one that holds only a bare capitalised word: the
    /// budget goes to the names a phrase points at. The kept excerpts keep their transcript order.
    func excerpts(from segments: [NameSegment]) -> Outcome {
        var perSegment: [Int: [Candidate]] = [:]
        var positions: [Int: [Int]] = [:]
        var primaryHits: Set<Int> = []
        for (index, segment) in segments.enumerated() {
            let found = scan(segment, at: index)
            if !found.isEmpty {
                perSegment[index] = found.map(\.candidate)
                positions[index] = found.map(\.position)
                if found.contains(where: { $0.candidate.kind != nil || $0.known }) { primaryHits.insert(index) }
            }
        }
        guard !perSegment.isEmpty else { return Outcome(excerpts: [], droppedExcerpts: 0) }

        // Two tiers (step 1.5): the segments with a phrase, a vocative or a known name make their excerpts first;
        // the bare capitalised words make theirs only from the segments those excerpts leave. Merged into one
        // tier, the bare words of a long meeting (institutions, places) chained the phrase excerpts into runs of
        // dozens of segments, and the budget held a third of them.
        let primaryRanges = Self.ranges(around: primaryHits.sorted(), count: segments.count, avoiding: [])
        let covered = Set(primaryRanges.flatMap { Array($0) })
        let secondaryHits = perSegment.keys.filter { !covered.contains($0) }.sorted()
        let secondaryRanges = Self.ranges(around: secondaryHits, count: segments.count, avoiding: covered)
        let tiered =
            primaryRanges.map { ($0, true) } + secondaryRanges.map { ($0, false) }
        var excerpts = tiered.sorted { $0.0.lowerBound < $1.0.lowerBound }.map { range, primary in
            Excerpt(
                range: range,
                segments: range.map { index in
                    if let at = positions[index] { return Self.windowed(segments[index], around: at) }
                    // A neighbour without a candidate is context: who answers and how the line starts, or how the
                    // line before the name ends. The guard checks quotes against the whole transcript.
                    return Self.trimmed(segments[index], keepingStart: perSegment[index - 1] != nil)
                },
                candidates: range.flatMap { perSegment[$0] ?? [] }, isPrimary: primary)
        }
        guard excerpts.count > Self.maximumExcerpts else {
            return Outcome(excerpts: excerpts, droppedExcerpts: 0)
        }
        let kept = Set(Self.ranked(excerpts).prefix(Self.maximumExcerpts))
        let dropped = excerpts.count - kept.count
        excerpts = excerpts.indices.filter { kept.contains($0) }.map { excerpts[$0] }
        return Outcome(excerpts: excerpts, droppedExcerpts: dropped)
    }

    /// The most words a neighbour without a candidate keeps in an excerpt (step 1.5: a long meeting's segments run
    /// up to the 15 s window, and whole neighbours filled the built-in model's context with three excerpts in four).
    static let neighbourWords = 12

    /// `segment` with at most `neighbourWords` words: its first ones when it follows a candidate's segment (the
    /// answer to a vocative or an announcement), else its last ones (the lead-up to the name).
    static func trimmed(_ segment: NameSegment, keepingStart: Bool) -> NameSegment {
        let words = segment.text.split(whereSeparator: \.isWhitespace)
        guard words.count > neighbourWords else { return segment }
        var trimmed = segment
        let kept = keepingStart ? words.prefix(neighbourWords) : words.suffix(neighbourWords)
        trimmed.text = kept.joined(separator: " ")
        return trimmed
    }

    /// `segment` cut to the words within `neighbourWords` of a candidate token (`positions` index
    /// `NotesText.tokens(segment.text)`), the original spelling kept. Windows that do not touch are joined with
    /// " … ". A segment that is short enough comes back whole.
    static func windowed(_ segment: NameSegment, around positions: [Int]) -> NameSegment {
        let tokens = NotesText.tokens(segment.text)
        guard tokens.count > 2 * neighbourWords + 1, !positions.isEmpty else { return segment }
        var windows: [ClosedRange<Int>] = []
        for position in positions.sorted() {
            let window = max(0, position - neighbourWords)...min(tokens.count - 1, position + neighbourWords)
            if let last = windows.last, window.lowerBound <= last.upperBound + 1 {
                windows[windows.count - 1] = last.lowerBound...max(last.upperBound, window.upperBound)
            } else {
                windows.append(window)
            }
        }
        let characters = Array(segment.text)
        let parts = windows.map { window -> String in
            // The window runs to the start of the next token, so the punctuation after its last word stays.
            let end = window.upperBound + 1 < tokens.count ? tokens[window.upperBound + 1].start : characters.count
            let start = min(tokens[window.lowerBound].start, characters.count)
            return String(characters[start..<max(start, min(end, characters.count))])
                .trimmingCharacters(in: .whitespaces)
        }
        var result = segment
        result.text =
            (windows.first?.lowerBound ?? 0 > 0 ? "… " : "") + parts.joined(separator: " … ")
            + ((windows.last?.upperBound ?? 0) < tokens.count - 1 ? " …" : "")
        return result
    }

    /// The excerpts of `outcome` that fit `budget` estimated tokens (`NotesText.estimateTokens` of their lines),
    /// taken in the same order of preference as the excerpt limit: an excerpt with a phrase first, then the bare
    /// words, each group in transcript order. An excerpt that does not fit is skipped and a later, shorter one may
    /// still be taken. The kept excerpts keep their transcript order; the skipped ones are added to
    /// `droppedExcerpts`. The built-in model's context (8192 tokens) holds far fewer than 40 excerpts of a long
    /// meeting, whose segments run up to the 15 s window (step 1.5: 28 excerpts of a 43-minute meeting were
    /// about 11 700 tokens).
    static func fitting(_ outcome: Outcome, budget: Int) -> Outcome {
        let excerpts = outcome.excerpts
        var left = budget
        var kept: Set<Int> = []
        for index in ranked(excerpts) {
            let cost = estimatedTokens(of: excerpts[index])
            guard cost <= left else { continue }
            left -= cost
            kept.insert(index)
        }
        return Outcome(
            excerpts: excerpts.indices.filter { kept.contains($0) }.map { excerpts[$0] },
            droppedExcerpts: outcome.droppedExcerpts + excerpts.count - kept.count)
    }

    /// The estimated tokens of one excerpt as the prompt writes it (its lines plus the block tags).
    static func estimatedTokens(of excerpt: Excerpt) -> Int {
        excerpt.segments.reduce(4) { total, segment in total + NotesText.estimateTokens(segment.line) + 2 }
    }

    /// The indexes of `excerpts` by preference: phrases first, then the bare words; the index breaks the tie, so
    /// each group stays in transcript order.
    private static func ranked(_ excerpts: [Excerpt]) -> [Int] {
        excerpts.indices.sorted { lhs, rhs in
            (hasPhrase(excerpts[lhs]), lhs) < (hasPhrase(excerpts[rhs]), rhs)
        }
    }

    private static func hasPhrase(_ excerpt: Excerpt) -> Int {
        excerpt.isPrimary || excerpt.candidates.contains { $0.kind != nil } ? 0 : 1
    }

    /// The windows of one segment before and one after each hit, merged where they touch, never reaching into
    /// `avoiding` (the indexes another tier's excerpts already hold).
    private static func ranges(around hits: [Int], count: Int, avoiding: Set<Int>) -> [ClosedRange<Int>] {
        var ranges: [ClosedRange<Int>] = []
        for hit in hits {
            var lower = max(0, hit - 1)
            var upper = min(count - 1, hit + 1)
            if avoiding.contains(lower) { lower = hit }
            if avoiding.contains(upper) { upper = hit }
            if let last = ranges.last, lower <= last.upperBound {
                ranges[ranges.count - 1] = last.lowerBound...max(last.upperBound, upper)
            } else {
                ranges.append(lower...upper)
            }
        }
        return ranges
    }

    // MARK: One segment

    /// The candidates of one segment: its known names and its capitalised words, with the kind a phrase gives
    /// them (a phrase beats a comma, a comma beats a bare capital).
    func candidates(in segment: NameSegment, at index: Int) -> [Candidate] {
        scan(segment, at: index).map(\.candidate)
    }

    /// `candidates(in:at:)` with the position of each candidate's token in `NotesText.tokens(segment.text)`.
    private func scan(_ segment: NameSegment, at index: Int) -> [(candidate: Candidate, position: Int, known: Bool)] {
        let tokens = NotesText.tokens(segment.text)
        guard !tokens.isEmpty else { return [] }
        let characters = Array(segment.text)
        let phrases = Self.phraseKinds(in: tokens)
        var found: [(candidate: Candidate, position: Int, known: Bool)] = []
        var seen = Set<String>()
        for (position, token) in tokens.enumerated() {
            let word = token.word
            guard word.count >= 3, !Self.isPlaceholder(word) else { continue }
            let known = knownForm(of: word)
            guard token.capitalised || known != nil else { continue }
            if known == nil, Temporal.isCalendarWord(word) || Self.isIgnored(word) { continue }
            let kind: NameEvidenceKind?
            if let phrase = phrases[position] {
                kind = phrase
            } else if token.capitalised, Self.followedByComma(token, characters: characters),
                !token.startsSentence || Self.endsWithQuestion(token, characters)
            {
                kind = .addressed
            } else if token.startsSentence {
                continue
            } else {
                kind = nil
            }
            let name = known ?? String(characters[token.start..<min(token.end, characters.count)])
            guard seen.insert(name.lowercased()).inserted else { continue }
            found.append((Candidate(name: name, segment: index, kind: kind), position, known != nil))
        }
        return found
    }

    /// The known name a transcript word is a form of (`Marku` → `Marek`), or nil.
    private func knownForm(of word: String) -> String? {
        for name in knownNames {
            guard let first = NotesText.words(name).first, first.count >= 3 else { continue }
            if NotesText.namesMatch(first, word) { return name }
        }
        return nil
    }

    // MARK: Phrases

    /// The self introductions: the speaker says who they are.
    private static let introductionPhrases: [[String]] = [
        ["nazywam", "sie"], ["nazywamy", "sie"], ["mam", "na", "imie"], ["jestem"], ["tu"],
        ["i", "m"], ["i", "am"], ["my", "name", "is"], ["this", "is"],
    ]

    /// The announcements: the chair or the host gives the floor to somebody.
    private static let announcementPhrases: [[String]] = [
        ["glos", "ma"], ["glos", "zabiera"], ["oddaje", "glos"], ["oddaje", "glosu"], ["udzielam", "glosu"],
        ["the", "floor", "goes", "to"], ["i", "give", "the", "floor", "to"], ["please", "welcome"],
        ["over", "to"], ["let", "s", "hear", "from"],
    ]

    /// The words between a trigger and the name: "głos ma pan poseł Kowalski", "proszę, pani minister Nowak".
    private static let honorifics: Set<String> = [
        "pan", "pani", "pana", "panu", "panie", "pania", "posel", "posla", "poslanka", "poslanki", "marszalek",
        "marszalka", "minister", "ministra", "senator", "senatora", "doktor", "profesor", "prezes", "prezesa",
        "dyrektor", "dyrektora", "mister", "mrs", "mr", "ms", "doctor", "professor", "chair",
    ]

    /// The token a phrase points at: the first capitalised word within `lookahead` words, past honorifics.
    /// `requiresHonorific` is the "proszę, pan X" shape: a "proszę" without "pan"/"pani" asks for quiet, not for
    /// a name.
    private static func nameIndex(from start: Int, in tokens: [NotesText.WordToken], requiresHonorific: Bool) -> Int? {
        var index = start
        var honorifics = 0
        while index < tokens.count, index - start < lookahead {
            let token = tokens[index]
            if honorifics < lookahead, Self.honorifics.contains(token.word) {
                honorifics += 1
                index += 1
                continue
            }
            if requiresHonorific, honorifics == 0 { return nil }
            return token.capitalised ? index : nil
        }
        return nil
    }

    /// The kind each token gets from a phrase ("nazywam się Marek" → the index of `Marek`).
    private static func phraseKinds(in tokens: [NotesText.WordToken]) -> [Int: NameEvidenceKind] {
        let words = tokens.map(\.word)
        var kinds: [Int: NameEvidenceKind] = [:]
        func mark(_ phrase: [String], _ kind: NameEvidenceKind, requiresHonorific: Bool = false) {
            guard phrase.count <= words.count else { return }
            for start in 0...(words.count - phrase.count)
            where Array(words[start..<(start + phrase.count)]) == phrase {
                guard
                    let target = nameIndex(
                        from: start + phrase.count, in: tokens, requiresHonorific: requiresHonorific)
                else { continue }
                if kinds[target] == nil { kinds[target] = kind }
            }
        }
        for phrase in introductionPhrases { mark(phrase, .introduction) }
        for phrase in announcementPhrases { mark(phrase, .announced) }
        mark(["prosze"], .announced, requiresHonorific: true)
        return kinds
    }

    // MARK: Heuristics

    /// The word after the token is a comma ("Marku, zrobisz to?").
    private static func followedByComma(_ token: NotesText.WordToken, characters: [Character]) -> Bool {
        var index = token.end
        while index < characters.count, characters[index] == " " { index += 1 }
        return index < characters.count && characters[index] == ","
    }

    /// The sentence that starts with the token ends with a question mark ("Marku, zrobisz to?"): the shape of a
    /// vocative that opens a sentence. Without it every sentence that opens with a capital and a comma ("Widzę,
    /// że…") would look like one.
    private static func endsWithQuestion(_ token: NotesText.WordToken, _ characters: [Character]) -> Bool {
        var index = token.end
        while index < characters.count {
            let character = characters[index]
            if character == "?" { return true }
            if character == "." || character == "!",
                index + 1 == characters.count || characters[index + 1].isWhitespace
            {
                return false
            }
            index += 1
        }
        return false
    }

    /// A label, not a name: "Speaker", "Mówca", "Rozmówca", "Ja", "Ty" (`NotesGuard.isGenericLabel`).
    private static func isPlaceholder(_ word: String) -> Bool { NotesGuard.isGenericLabel(word) }

    /// Tools, companies, systems, cities and greetings that a transcript capitalises but that name nobody.
    /// Deliberately short (see the type's comment): the model decides, this only keeps the budget for names.
    private static let ignored: Set<String> = [
        // The tools a meeting talks about.
        "jira", "slack", "teams", "zoom", "meet", "webex", "skype", "github", "gitlab", "bitbucket", "confluence",
        "notion", "trello", "asana", "monday", "linear", "clickup", "figma", "miro", "loom", "drive", "docs",
        "sheets", "slides", "gmail", "calendar", "outlook", "excel", "word", "powerpoint", "onedrive", "dropbox",
        "sharepoint", "jamboard", "whiteboard", "backlog", "sprint", "epic", "story",
        // Systems and languages.
        "google", "chrome", "chromium", "safari", "firefox", "microsoft", "windows", "linux", "ubuntu", "android",
        "iphone", "ipad", "ios", "macos", "apple", "swift", "python", "java", "javascript", "typescript", "react",
        "angular", "docker", "kubernetes", "aws", "azure", "gcp", "api", "sql", "http", "https", "git", "ai",
        "llm", "gpt", "openai", "anthropic", "claude", "chatgpt", "copilot", "lintel",
        // A few cities and countries a Polish or English meeting names.
        "warszawa", "warszawy", "warszawie", "krakow", "krakowa", "krakowie", "wroclaw", "wroclawia", "poznan",
        "gdansk", "lodz", "london", "berlin", "paris", "warsaw", "polska", "poland", "polski", "polish", "english",
        "angielski", "europe", "europa",
        // Greetings and courtesies that open a sentence with a capital and a comma.
        "dzien", "dobry", "dobrego", "czesc", "witam", "witaj", "witajcie", "hello", "hi", "hey", "good", "morning",
        "afternoon", "evening", "dziekuje", "dziekujemy", "thanks", "thank", "przepraszam", "sorry", "prosze",
        "dzieki", "ok", "okej", "okay", "tak", "nie", "yes", "no", "dobra", "dobrze", "wszystko", "wszyscy",
    ]

    private static func isIgnored(_ word: String) -> Bool {
        ignored.contains { NotesText.namesMatch($0, word) }
    }
}

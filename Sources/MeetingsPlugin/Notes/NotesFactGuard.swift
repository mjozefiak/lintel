import Foundation
import LintelCore

/// Checks the facts of notes the model wrote itself (the whole-transcript track), against the WHOLE cleaned
/// transcript and the speaker labels. It checks facts, not words: a rewritten sentence passes, a number, date,
/// weekday, hour, name or owner that nobody said does not.
///
/// What the guard promises:
/// - a line that fails is removed, never replaced by transcript text: every line of the result is a line of the
///   answer, at most without its owner or due date, or cut to a limit;
/// - the summary is never composed from the items; if no sentence of it passes there is no summary;
/// - links, images, HTML, control and bidi characters never reach the notes;
/// - only counters and codes leave this type; it never logs text.
///
/// What it cannot see (named limits): a false sentence without a number, date or proper noun passes. A capitalised
/// word at the START of a sentence is not checked as a name: an ordinary word the meeting did not say as such
/// ("Skipping…", "Zdecydowano…") opens many good lines, so dropping every such line would cost more than the rare
/// invented person it removes; an invented person who opens a line passes, and the quality gate counts such
/// sentences by hand. A capitalised word after a colon or a semicolon is checked as a name, and so is the owner
/// field. A clock time is checked by its hour against the spoken numbers and hours, and by its minutes: every
/// field after the hour must be said too or be zero, so an invented "22:45" goes while "22:00" stands. A time the
/// meeting said as "half past ten" or "wpół do jedenastej" is written down as 10:30 only when 30 was said as a
/// number too, which is a known false removal (the guard has no clock-phrase reading). A decimal is compared in
/// tenths (Polish "półtora" is "1.5"), and a numeric date ("15.03") stands when its day and month were said.
struct NotesFactGuard: Sendable {
    enum Rule: String, Sendable, CaseIterable { case numbers, dates, names, shape }

    struct Report: Equatable, Sendable {
        /// Lines (and summary sentences) removed because the recording does not back them
        /// (`notes_dropped_count`).
        var dropped = 0
        var droppedByRule: [Rule: Int] = [:]
        var personReset = 0
        var dueRemoved = 0
        var timesOmitted = 0
        /// Lines in which a link, image, tag or control character was removed but the line stayed.
        var shapeStripped = 0
        /// Lines and items cut because of a limit (not counted as dropped).
        var cutToLimit = 0
        /// Topics whose name the guard refused; their points moved to "Other". Not counted in `dropped`.
        var topicNameRefused = 0
    }

    static let maxDecisions = 10
    static let maxTasks = 15
    static let maxOpen = NotesLayout.maxOpenQuestions
    static let maxPointsPerTopic = NotesLayout.maxPointsPerTopic
    static let maxLineWords = 25
    static let maxSummarySentences = NotesLayout.maxIntroSentences
    static let maxSummaryWords = NotesLayout.maxIntroWords

    private let material: Material
    private let durationMs: Int

    /// The most topics the notes of this meeting show (`NotesLayout.maxTopics`); the closing "Other" is extra.
    var maxTopics: Int { NotesLayout.maxTopics(durationMs: durationMs) }

    /// `durationMs` is the length of the meeting; without it the last utterance plus one minute.
    init(utterances: [NotesUtterance], durationMs: Int? = nil) {
        material = Material(utterances: utterances)
        self.durationMs = durationMs ?? ((utterances.map(\.startMs).max() ?? 0) + 60_000)
    }

    func check(_ draft: NotesDraft) -> (draft: NotesDraft, report: Report) {
        var report = Report()
        var result = NotesDraft()

        if let title = draft.title, let kept = vet(title, lenientNames: true, cap: false, &report) {
            result.title = NotesText.truncated(kept, limit: 120)
        }
        if let summary = draft.summary { result.summary = vetSummary(summary, &report) }

        for item in draft.decisions {
            guard let text = vet(item.text, &report) else { continue }
            result.decisions.append(.init(timeMs: time(item.timeMs, &report), text: text))
        }
        for task in draft.tasks {
            guard let text = vet(task.text, &report) else { continue }
            var person = task.person.map { clean($0).text }.flatMap { $0.isEmpty ? nil : $0 }
            if let name = person, !material.knowsPerson(name) {
                person = nil
                report.personReset += 1
            }
            var due = task.due.map { clean($0).text }.flatMap { $0.isEmpty ? nil : $0 }
            if let words = due, !material.saidDue(words) {
                due = nil
                report.dueRemoved += 1
            }
            result.tasks.append(.init(timeMs: time(task.timeMs, &report), person: person, due: due, text: text))
        }
        var refusedPoints: [String] = []
        for topic in draft.topics {
            var name = topic.name
            var refused = false
            if let given = name {
                // A refused name is not a dropped line: its points are kept under "Other".
                var scratch = Report()
                name = vet(given, cap: false, &scratch)
                if name == nil {
                    refused = true
                    report.topicNameRefused += 1
                } else {
                    report.shapeStripped += scratch.shapeStripped
                }
            }
            var points: [String] = []
            for point in topic.points {
                if let kept = vet(point, &report) { points.append(kept) }
            }
            guard !points.isEmpty else { continue }
            if refused {
                refusedPoints.append(contentsOf: points)
            } else {
                result.topics.append(.init(name: name, points: points, isOther: topic.isOther))
            }
        }
        for text in draft.open {
            if let kept = vet(text, &report) { result.open.append(kept) }
        }

        // The limits, in the order of the answer; nothing is put back.
        func limited<T>(_ items: [T], _ limit: Int) -> [T] {
            if items.count > limit { report.cutToLimit += items.count - limit }
            return Array(items.prefix(limit))
        }
        result.decisions = limited(result.decisions, Self.maxDecisions)
        result.tasks = limited(result.tasks, Self.maxTasks)
        result.open = limited(result.open, Self.maxOpen)
        result.topics = limited(result.topics, maxTopics).map { topic in
            var topic = topic
            topic.points = limited(topic.points, Self.maxPointsPerTopic)
            return topic
        }
        if !refusedPoints.isEmpty {
            result.topics.append(
                .init(name: nil, points: limited(refusedPoints, Self.maxPointsPerTopic), isOther: true))
        }
        return (result, report)
    }

    // MARK: Lines

    /// The text of one line when it passes: shape cleaned, facts checked, cut to the word limit.
    private func vet(_ raw: String, lenientNames: Bool = false, cap: Bool = true, _ report: inout Report) -> String? {
        let cleaned = clean(raw)
        guard !cleaned.text.isEmpty else {
            drop(.shape, &report)
            return nil
        }
        if let rule = problem(in: cleaned.text, lenientNames: lenientNames) {
            drop(rule, &report)
            return nil
        }
        if cleaned.changed { report.shapeStripped += 1 }
        guard cap else { return cleaned.text }
        let words = cleaned.text.split(whereSeparator: \.isWhitespace)
        guard words.count > Self.maxLineWords else { return cleaned.text }
        report.cutToLimit += 1
        return words.prefix(Self.maxLineWords).joined(separator: " ")
    }

    private func drop(_ rule: Rule, _ report: inout Report) {
        report.dropped += 1
        report.droppedByRule[rule, default: 0] += 1
    }

    private func time(_ ms: Int?, _ report: inout Report) -> Int? {
        guard let ms else { return nil }
        if ms > durationMs {
            report.timesOmitted += 1
            return nil
        }
        return ms
    }

    private func vetSummary(_ raw: String, _ report: inout Report) -> String? {
        let flat = clean(raw)
        var kept: [String] = []
        for sentence in Self.sentences(of: flat.text) {
            if let rule = problem(in: sentence, lenientNames: false) {
                drop(rule, &report)
            } else {
                kept.append(sentence)
            }
        }
        if flat.changed, !kept.isEmpty { report.shapeStripped += 1 }
        // At most three sentences and 70 words: a prefix of whole sentences that fits the limits.
        var shown: [String] = []
        var words = 0
        for sentence in kept {
            let count = sentence.split(whereSeparator: \.isWhitespace).count
            // The intro is a prefix of whole sentences: the first one that does not fit ends it, so a later sentence
            // never follows a skipped one without the sentence it refers to (and nothing is cut in the middle).
            if shown.count >= Self.maxSummarySentences || count > Self.maxSummaryWords
                || words + count > Self.maxSummaryWords
            {
                report.cutToLimit += 1
                break
            }
            shown.append(sentence)
            words += count
        }
        let text = shown.joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    static func sentences(of text: String) -> [String] {
        let characters = Array(text)
        var cuts = [0]
        for token in NotesText.tokens(text) where token.sentenceEnd != nil && token.start > 0 {
            cuts.append(token.start)
        }
        cuts.append(characters.count)
        var result: [String] = []
        for index in 0..<(cuts.count - 1) where cuts[index] < cuts[index + 1] {
            let piece = String(characters[cuts[index]..<cuts[index + 1]]).trimmingCharacters(in: .whitespaces)
            if !piece.isEmpty { result.append(piece) }
        }
        return result
    }

    // MARK: Shape

    private func clean(_ raw: String) -> (text: String, changed: Bool) {
        var text = MarkdownText.cleaned(raw, keepNewlines: false)
        text = text.replacing(/!\[[^\]]*\]\([^)]*\)/, with: "")
        text = text.replacing(/\[([^\]]*)\]\([^)]*\)/) { String($0.output.1) }
        text = text.replacing(/<[^<>]*>/, with: "")
        text = text.replacing(/(?i)\b(?:https?|ftp|file|mailto):\S*/, with: "")
        text = text.replacing(/(?i)\bwww\.\S+/, with: "")
        for unit in NotesText.linkUnits(text) where !material.links.contains(unit) {
            text = text.replacing(unit, with: "", maxReplacements: 20)
        }
        text = text.replacing(/\ {2,}/, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let original = MarkdownText.cleaned(raw, keepNewlines: false).trimmingCharacters(in: .whitespacesAndNewlines)
        return (text, text != original)
    }

    // MARK: Facts

    private func problem(in text: String, lenientNames: Bool) -> Rule? {
        if !material.numbersAreSaid(in: text) { return .numbers }
        if !material.datesAreSaid(in: text) { return .dates }
        if !(lenientNames && Self.looksTitleCased(text)), !material.namesAreSaid(in: text) { return .names }
        return nil
    }

    private static func looksTitleCased(_ text: String) -> Bool {
        let tokens = NotesText.tokens(text).filter { $0.word.count > 2 }
        return tokens.count >= 3 && Double(tokens.filter(\.capitalised).count) / Double(tokens.count) >= 0.7
    }
}

// MARK: Material

extension NotesFactGuard {
    /// What was said: every word of the cleaned transcript and the speaker labels, in the forms the rules compare.
    fileprivate struct Material: Sendable {
        let words: Set<String>
        let byInitial: [Character: [String]]
        let values: Set<Int>
        let units: Set<String>
        let hours: Set<Int>
        let temporal: Set<String>
        let relative: Set<Int>
        let links: Set<String>
        /// The words a line may use for a number that are mostly a pronoun in the meeting's language: "ten" and
        /// "one" are the numbers 10 and 1 only in an English meeting.
        let ambiguous: Set<String>

        init(utterances: [NotesUtterance]) {
            var all: [String] = []
            var units: Set<String> = []
            var links: Set<String> = []
            for utterance in utterances {
                let text = utterance.text
                let spoken = NotesText.words(text)
                all.append(contentsOf: spoken)
                all.append(contentsOf: NotesText.words(utterance.speaker))
                units.formUnion(NotesText.numberUnits(text))
                links.formUnion(NotesText.linkUnits(text))
            }
            var set = Set(all)
            // A name the recognition split in two ("szybko pak") is still said as one.
            for index in all.indices.dropLast() { set.insert(all[index] + all[index + 1]) }
            words = set
            byInitial = Dictionary(grouping: set, by: { $0.first ?? " " })
            let language = NotesLanguage.dominant(in: utterances.map(\.text).joined(separator: " "))
            // Outside an English meeting "ten" is the Polish pronoun (this) and "one" the Polish "they", never
            // the numbers 10 and 1: both are left out of the spoken numbers.
            let numbers = language == .english ? all : all.map { ["ten", "one"].contains($0) ? "_" : $0 }
            values = NotesNumberForms.spokenValues(numbers)
            ambiguous = language == .english ? ["second", "sto", "stu"] : ["second", "sto", "stu", "ten", "one"]
            self.units = units
            hours = NotesNumberForms.spokenHours(all)
            temporal = Set(all.compactMap { Temporal.group(of: $0) })
            relative = Set(all.compactMap { Self.relativeGroup(of: $0) })
            self.links = links
        }

        func numbersAreSaid(in text: String) -> Bool {
            for unit in NotesText.numberUnits(text) {
                if units.contains(unit) { continue }
                if unit.contains(":") {
                    let fields = unit.split(separator: ":").compactMap { Int($0.prefix { $0.isNumber }) }
                    guard let hour = fields.first else { return false }
                    if !(values.contains(hour) || hours.contains(hour) || hours.contains(hour % 12)) { return false }
                    // The minutes (and seconds) too: "22:45" says nothing about 45 if only 22 was spoken.
                    for field in fields.dropFirst()
                    where field != 0 && !values.contains(field) && !hours.contains(field) {
                        return false
                    }
                    continue
                }
                // "4,200": a thousands separator, not a decimal.
                let pieces = unit.split(separator: ".", omittingEmptySubsequences: false)
                if pieces.count == 2, pieces[1].count == 3, pieces[1].allSatisfy(\.isNumber),
                    let head = Int(pieces[0]), pieces[0].count <= 3, let tail = Int(pieces[1]),
                    values.contains(head * 1000 + tail)
                {
                    continue
                }
                if unit.contains(where: { ".,/-".contains($0) }) {
                    let parts = unit.split { ".,/-".contains($0) }.compactMap { Int($0.prefix { $0.isNumber }) }
                    if unit.contains("."), parts.count > 1, !unit.contains("/") {
                        // "1.5": a decimal, compared in tenths ("półtora" is 15); "15.03": a date.
                        if parts.count == 2, parts.allSatisfy({ values.contains($0) }) { continue }
                        if parts.count == 2, pieces.count == 2, pieces[1].count == 1, parts[0] <= 1_000_000,
                            values.contains(parts[0] * 10 + parts[1])
                        {
                            continue
                        }
                        if Self.isSaidDate(parts, values: values, temporal: temporal) { continue }
                        return false
                    }
                    if !parts.isEmpty, parts.allSatisfy({ values.contains($0) }) { continue }
                    if Self.isSaidDate(parts, values: values, temporal: temporal) { continue }
                    return false
                }
                if let value = Int(unit.prefix { $0.isNumber }), values.contains(value) { continue }
                return false
            }
            // Digits were checked above; a magnitude word right after one ("28 tysięcy") belongs to it.
            var masked: [String] = []
            for word in NotesText.words(text) {
                if Int(word) != nil {
                    masked.append("#")
                } else if masked.last == "#", NotesNumberForms.isMagnitude(word) {
                    continue
                } else if ambiguous.contains(word) {
                    masked.append("_")
                } else {
                    masked.append(word)
                }
            }
            return NotesNumberForms.spokenValues(masked, skipOne: true).isSubset(of: values)
        }

        /// A numeric date (`15.03`, `15/03/2026`) whose day was said as a number and whose month was said as a
        /// month name; with a year, the year must be said too.
        private static func isSaidDate(_ parts: [Int], values: Set<Int>, temporal: Set<String>) -> Bool {
            guard (2...3).contains(parts.count), (1...31).contains(parts[0]),
                let group = Temporal.monthGroup(parts[1]), values.contains(parts[0]), temporal.contains(group)
            else { return false }
            return parts.count == 2 || values.contains(parts[2])
        }

        func datesAreSaid(in text: String) -> Bool {
            NotesText.words(text).allSatisfy { word in
                guard let group = Temporal.group(of: word) else { return true }
                return temporal.contains(group)
            }
        }

        func namesAreSaid(in text: String) -> Bool {
            for token in NotesText.tokens(text) where token.capitalised {
                let word = token.word
                guard word.count >= 2, !word.contains(where: \.isNumber) else { continue }
                if Self.isCapitalisedForPlace(token) { continue }
                if !isKnown(word) { return false }
            }
            return true
        }

        /// A capital that only marks the start of the line is not a name: it passes unchecked, because an
        /// ordinary word the meeting did not say as such ("Skipping…", "Zdecydowano…") opens many lines. A capital
        /// after a colon or a semicolon (`Ustalenia: Zenon …`) is a name in both languages, so that one is checked.
        static func isCapitalisedForPlace(_ token: NotesText.WordToken) -> Bool {
            guard token.startsSentence else { return false }
            // The first word of the line, or the first after a full stop, exclamation or question mark.
            return token.start == 0 || token.sentenceEnd != nil
        }

        private func isKnown(_ word: String) -> Bool {
            if words.contains(word) { return true }
            guard let initial = word.first else { return true }
            for other in byInitial[initial] ?? [] where Self.isClose(word, other) { return true }
            // A garbled first letter ("prelzie" for "Brelsie") is close by edit distance only.
            for other in words where abs(other.count - word.count) <= 2 && Self.isNear(word, other) { return true }
            return false
        }

        static func isNear(_ first: String, _ second: String) -> Bool {
            guard min(first.count, second.count) >= 5 else { return false }
            return editDistance(Array(first), Array(second), limit: 2) <= 2
        }

        static func isClose(_ first: String, _ second: String) -> Bool {
            if NotesText.wordsMatch(first, second) || NotesText.namesMatch(first, second) { return true }
            let shortest = min(first.count, second.count)
            if shortest >= 4 {
                // Spec: an edit distance up to 2, so a name the recognition garbled and the model corrected
                // ("brelzo" → "Brelsa") still stands. Two edits are allowed from five letters up.
                let limit = max(first.count, second.count) >= 5 ? 2 : 1
                if editDistance(Array(first), Array(second), limit: limit) <= limit { return true }
                let a = Array(first)
                let b = Array(second)
                var shared = 0
                while shared < shortest, a[shared] == b[shared] { shared += 1 }
                if shared >= 4, Double(shared) >= 0.7 * Double(shortest) { return true }
            }
            return false
        }

        /// The edit distance, or `limit + 1` as soon as it is certain to exceed `limit`.
        static func editDistance(_ a: [Character], _ b: [Character], limit: Int) -> Int {
            if abs(a.count - b.count) > limit { return limit + 1 }
            var previous = Array(0...b.count)
            for i in 1...max(a.count, 1) where i <= a.count {
                var row = [i] + Array(repeating: 0, count: b.count)
                var best = row[0]
                for j in 1...max(b.count, 1) where j <= b.count {
                    row[j] = min(previous[j] + 1, row[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                    best = min(best, row[j])
                }
                if best > limit { return limit + 1 }
                previous = row
            }
            return previous[b.count]
        }

        /// An owner: a real name that was said, in an utterance or as a label. A generic label names nobody.
        func knowsPerson(_ person: String) -> Bool {
            if NotesGuard.isGenericLabel(person) { return false }
            let tokens = NotesText.words(person).filter { $0.count >= 2 }
            guard !tokens.isEmpty else { return false }
            return tokens.allSatisfy { token in
                if words.contains(token) { return true }
                return (byInitial[token.first ?? " "] ?? []).contains { NotesText.namesMatch(token, $0) }
            }
        }

        /// A due date: every word of three letters or more was said (allowing for the case ending), every number
        /// and weekday too.
        func saidDue(_ due: String) -> Bool {
            guard numbersAreSaid(in: due), datesAreSaid(in: due) else { return false }
            return NotesText.words(due).filter { $0.count >= 3 && Int($0) == nil }.allSatisfy { word in
                if words.contains(word) { return true }
                if let group = Self.relativeGroup(of: word), relative.contains(group) { return true }
                return (byInitial[word.first ?? " "] ?? []).contains { NotesText.wordsMatch(word, $0) }
            }
        }

        private static let relativeGroups: [[String]] = [
            ["jutr", "tomorrow"], ["dzis", "today", "tonight"], ["pojutrz"], ["wczoraj", "yesterday"],
            ["tydzien", "tygodn", "week"], ["miesiac", "miesie", "month"], ["kwartal", "quarter"],
            ["konc", "koni", "end"], ["przyszl", "nastepn", "next"],
        ]

        static func relativeGroup(of word: String) -> Int? {
            relativeGroups.firstIndex { $0.contains { word.hasPrefix($0) } }
        }
    }
}

import Foundation

/// Reads the answer of `SpeakerNamePrompt` (spec `2026-11-25-meeting-speaker-names`, step 1.3). Tolerant of the
/// envelope a model wraps its answer in (a ```` ```json ```` fence, a sentence before or after the array), strict
/// about the fields: an entry with a missing field, an unknown `kind` or an unknown `confidence` is skipped, and an
/// answer that is no JSON array at all gives no proposals. A bad answer is never an error of the pass: the notes go
/// on without names.
enum SpeakerNameParser {
    /// The proposals of the answer, in the order the model wrote them. The names are cleaned with the same rule as
    /// the labels (bars, prompt tags, bidi and control characters go) and a name longer than the limit of
    /// `NameEvidence` (60) is skipped, so the guard only ever sees a usable name.
    ///
    /// `cut`: the answer ended at the token limit (a small model may repeat one entry until it does, step 1.5).
    /// Its complete entries are read, up to the last closed object; the open one at the end is dropped. Each
    /// entry still goes through `NameEvidenceGuard`. A repeated entry (every field the same) is read once.
    static func proposals(from answer: String, cut: Bool = false) -> [NameProposal] {
        guard let entries = entries(in: answer, cut: cut) else { return [] }
        var proposals: [NameProposal] = []
        for entry in entries {
            guard let object = entry as? [String: Any],
                let rawSpeaker = string(object["speaker"]),
                let rawName = string(object["name"]),
                let rawKind = string(object["kind"]),
                let kind = NameEvidenceKind(rawValue: rawKind.lowercased()),
                let rawQuote = string(object["quote"]),
                let rawConfidence = string(object["confidence"]),
                let confidence = NameEvidenceConfidence(rawValue: rawConfidence.lowercased())
            else { continue }
            let speaker = SpeakerNamePrompt.sanitized(rawSpeaker)
            let name = SpeakerNamePrompt.sanitized(rawName)
            let quote = SpeakerNamePrompt.sanitized(rawQuote)
            guard !speaker.isEmpty, !name.isEmpty, name.count <= NameEvidence.maximumNameLength, !quote.isEmpty
            else { continue }
            let proposal = NameProposal(speaker: speaker, name: name, kind: kind, quote: quote, confidence: confidence)
            if !proposals.contains(proposal) { proposals.append(proposal) }
        }
        return proposals
    }

    /// The decoded entries: the whole array, or for a cut answer the array closed after its last complete object
    /// (trying a few earlier `}` when a brace stood inside a string).
    private static func entries(in answer: String, cut: Bool) -> [Any]? {
        if let body = arrayBody(in: answer), let entries = decode(body) { return entries }
        guard cut, let first = answer.firstIndex(of: "[") else { return nil }
        var end = answer.endIndex
        for _ in 0..<5 {
            guard let brace = answer[first..<end].lastIndex(of: "}") else { return nil }
            if let entries = decode(String(answer[first...brace]) + "]") { return entries }
            end = brace
        }
        return nil
    }

    private static func decode(_ body: String) -> [Any]? {
        guard let data = body.data(using: .utf8), let decoded = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return decoded as? [Any]
    }

    /// The array of the answer: from its first `[` to its last `]`, so a fence or a sentence around it does not
    /// matter. Nil when there is no such pair.
    private static func arrayBody(in answer: String) -> String? {
        guard let first = answer.firstIndex(of: "["), let last = answer.lastIndex(of: "]"), first < last else {
            return nil
        }
        return String(answer[first...last])
    }

    private static func string(_ value: Any?) -> String? { value as? String }
}

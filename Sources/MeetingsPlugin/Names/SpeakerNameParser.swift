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
    static func proposals(from answer: String) -> [NameProposal] {
        guard let body = arrayBody(in: answer), let data = body.data(using: .utf8),
            let decoded = try? JSONSerialization.jsonObject(with: data), let entries = decoded as? [Any]
        else { return [] }
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
            proposals.append(
                NameProposal(speaker: speaker, name: name, kind: kind, quote: quote, confidence: confidence))
        }
        return proposals
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

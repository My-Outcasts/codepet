// codepet/Models/TextRelevance.swift
import Foundation

/// Token-overlap relevance primitives, shared by chat grounding and department routing.
///
/// Extracted verbatim from `ChatContext`, which was its only user until `DepartmentRouter`
/// needed the same three things. The extraction is the point: two copies of a stopword list
/// is a trap where fixing one leaves the other wrong, silently, inside a grounding path
/// nobody looks at. `ChatContextTests` stands over this move — if the tokenizer changed
/// behaviour, prior-work selection changes with it and those tests go red.
enum TextRelevance {
    /// Words too common to carry signal for relevance matching (mirrors web STOPWORDS).
    static let stopwords: Set<String> = [
        "the", "and", "for", "our", "your", "their", "this", "that", "with", "from",
        "into", "about", "are", "was", "were", "will", "has", "have", "not", "you",
        "each", "per", "its", "via", "onto",
    ]

    /// Split text into lowercased, de-duped content tokens (≥3 chars, no stopwords).
    ///
    /// Splitting on `CharacterSet.alphanumerics.inverted` is what makes every match a WHOLE
    /// word: "designed" is the token `designed` and can never match `design`. That is the
    /// Aug 7 substring defect, closed by construction rather than by a guard.
    static func tokenize(_ s: String) -> Set<String> {
        var out: Set<String> = []
        for raw in s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted) {
            if raw.count >= 3 && !stopwords.contains(raw) { out.insert(raw) }
        }
        return out
    }

    static func overlap(_ a: Set<String>, _ b: Set<String>) -> Int {
        a.filter { b.contains($0) }.count
    }
}

// codepet/Models/Decisions.swift
import Foundation

/// One durable decision the company has locked in (pricing, positioning, naming…),
/// keyed by `topic` so a newer decision supersedes the old. Ported from the web
/// lib/ai/projectModel.ts (DecisionEntry) + lib/ai/decisions.ts (merge). JSON-safe
/// (`updatedAt` = epoch millis) so it round-trips in companies/{uid}.decisions.
struct DecisionEntry: Codable, Hashable {
    var topic: String
    var statement: String
    var source: String?
    var updatedAt: Double?   // epoch milliseconds
}

/// A decision as returned by the extractDecisions CF (no timestamp yet).
struct ExtractedDecision: Codable, Hashable {
    var topic: String
    var statement: String
    var source: String?
}

enum Decisions {
    static let MAX_DECISIONS = 30

    private static func t(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
    private static func key(_ topic: String) -> String { t(topic).lowercased() }
    private static func cleanSource(_ s: String?) -> String? {
        let v = t(s ?? "")
        return v.isEmpty ? nil : v
    }

    /// Sanitize + cap (keep most-recently-updated; nil updatedAt sorts oldest).
    static func normalizeDecisions(_ raw: [DecisionEntry], max: Int = MAX_DECISIONS) -> [DecisionEntry] {
        var entries: [DecisionEntry] = []
        for r in raw {
            let topic = t(r.topic), statement = t(r.statement)
            if topic.isEmpty || statement.isEmpty { continue }
            entries.append(DecisionEntry(topic: topic, statement: statement, source: cleanSource(r.source), updatedAt: r.updatedAt))
        }
        if entries.count <= max { return entries }
        return Array(entries.sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }.prefix(max))
    }

    /// Merge extracted into existing, keyed by lowercased topic: an extraction on the same
    /// topic supersedes the old one and stamps updatedAt=now; untouched topics preserved
    /// (in original order, updates in place, new topics appended). Over cap → keep most-recent.
    static func mergeDecisions(existing: [DecisionEntry], extracted: [ExtractedDecision],
                               now: Double, max: Int = MAX_DECISIONS) -> [DecisionEntry] {
        var order: [String] = []
        var byTopic: [String: DecisionEntry] = [:]
        for d in existing {
            let topic = t(d.topic), statement = t(d.statement)
            if topic.isEmpty || statement.isEmpty { continue }
            let k = key(topic)
            if byTopic[k] == nil { order.append(k) }
            byTopic[k] = d
        }
        for e in extracted {
            let topic = t(e.topic), statement = t(e.statement)
            if topic.isEmpty || statement.isEmpty { continue }
            let k = key(topic)
            if byTopic[k] == nil { order.append(k) }
            byTopic[k] = DecisionEntry(topic: topic, statement: statement, source: cleanSource(e.source), updatedAt: now)
        }
        let merged = order.compactMap { byTopic[$0] }
        if merged.count <= max { return merged }
        return Array(merged.sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }.prefix(max))
    }

    /// Render locked-in decisions as a grounding block. "" when none. Verbatim from web composeDecisions.
    static func composeDecisions(_ decisions: [DecisionEntry]) -> String {
        if decisions.isEmpty { return "" }
        let lines = decisions.map { "- \($0.topic): \($0.statement)" }.joined(separator: "\n")
        return "Decisions the founder has locked in — honor these; never contradict or silently re-open them:\n"
            + lines
            + "\nIf the current work genuinely conflicts with one, do NOT quietly override it and do NOT ignore the conflict: stay consistent with the decision, and add one short, clearly-marked note flagging the tension so the founder can decide (e.g. \"Note: this holds to your decision that <…>; tell me if you want to revisit it\")."
    }
}

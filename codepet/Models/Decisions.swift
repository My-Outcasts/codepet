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
    /// Which project the decision belongs to (2026-09-25): a project id (`activeProjectId`),
    /// `Decisions.everywhere`, or nil — unassigned, which is every decision made before this
    /// field and every one made with no folder linked. See `Decisions.applicable`.
    ///
    /// Why: a Team Build for Codepet was handed the $35-pants experiment's brand ("quiet paper",
    /// Lyon/Söhne, "one small collection a season") because decisions had no project at all.
    /// Optional and omitted when nil, so every stored decision decodes and re-encodes unchanged.
    var scope: String? = nil
}

/// A decision as returned by the extractDecisions CF (no timestamp yet).
struct ExtractedDecision: Codable, Hashable {
    var topic: String
    var statement: String
    var source: String?
}

enum Decisions {
    static let MAX_DECISIONS = 30
    /// A decision the founder applied to every project.
    static let everywhere = "*"

    /// The decisions a context may use. With a project open: that project's and the
    /// everywhere ones — NOT the unassigned ones, which is the point: they were made without a
    /// project and may belong to another. With no project open: the unassigned and everywhere
    /// ones, never another project's. Unassigned decisions are not lost — the Memory panel lists
    /// them and assigns them in one tap.
    static func applicable(_ all: [DecisionEntry], project: String?) -> [DecisionEntry] {
        all.filter { d in
            if d.scope == everywhere { return true }
            return project == nil ? d.scope == nil : d.scope == project
        }
    }

    /// Unassigned decisions left out while `project` is open — what the Memory panel offers to assign.
    static func unassigned(_ all: [DecisionEntry], whileIn project: String?) -> [DecisionEntry] {
        project == nil ? [] : all.filter { $0.scope == nil }
    }

    /// Identity including scope: "pricing" for Codepet and "pricing" for the pants test are two facts.
    static func identity(_ d: DecisionEntry) -> String { (d.scope ?? "") + "|" + identityKey(d.topic) }

    private static func t(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// A decision's IDENTITY: its trimmed, lowercased `topic`. `mergeDecisions` keys on this,
    /// so a newer statement on the same topic *is* the same fact — which makes this the only
    /// correct thing for a delete to match on (`CompanyStore.forgetDecision`). Matching the
    /// statement too would make a fact that has since been rewritten undeletable.
    static func identityKey(_ topic: String) -> String { t(topic).lowercased() }
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
            entries.append(DecisionEntry(topic: topic, statement: statement, source: cleanSource(r.source),
                                         updatedAt: r.updatedAt, scope: r.scope))
        }
        if entries.count <= max { return entries }
        return Array(entries.sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }.prefix(max))
    }

    /// Merge extracted into existing, keyed by lowercased topic: an extraction on the same
    /// topic supersedes the old one and stamps updatedAt=now; untouched topics preserved
    /// (in original order, updates in place, new topics appended). Over cap → keep most-recent.
    /// `scope` is stamped on every extracted decision, and identity includes it — the same topic
    /// in another project is a different fact and is never superseded from here.
    static func mergeDecisions(existing: [DecisionEntry], extracted: [ExtractedDecision],
                               now: Double, scope: String? = nil, max: Int = MAX_DECISIONS) -> [DecisionEntry] {
        var order: [String] = []
        var byTopic: [String: DecisionEntry] = [:]
        for d in existing {
            let topic = t(d.topic), statement = t(d.statement)
            if topic.isEmpty || statement.isEmpty { continue }
            let k = identity(d)
            if byTopic[k] == nil { order.append(k) }
            byTopic[k] = d
        }
        for e in extracted {
            let topic = t(e.topic), statement = t(e.statement)
            if topic.isEmpty || statement.isEmpty { continue }
            let fresh = DecisionEntry(topic: topic, statement: statement, source: cleanSource(e.source),
                                      updatedAt: now, scope: scope)
            let k = identity(fresh)
            if byTopic[k] == nil { order.append(k) }
            byTopic[k] = fresh
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

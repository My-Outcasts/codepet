// codepet/Models/ChatContext.swift
import Foundation

/// Pure grounding-string builder for the Copilot chat — the company brief plus a
/// short roadmap summary, sent to the companyChat CF as `context`. Always returns
/// a non-empty string.
///
/// Ported from web's richer chat grounding (`lib/ai/departments.ts` deptSummary +
/// `lib/ai/priorWork.ts` selectPriorWork/composePriorWorkContext): beyond the brief
/// and roadmap, byte is also grounded on (1) a compact per-department status snapshot
/// and (2) excerpts of the founder's already-shipped work most relevant to what they
/// just asked, so new output stays consistent with naming/pricing/positioning already
/// locked in instead of re-inventing it from a one-line brief.
enum ChatContext {
    // Words too common to carry signal for relevance matching (mirrors web STOPWORDS).
    private static let stopwords: Set<String> = [
        "the", "and", "for", "our", "your", "their", "this", "that", "with", "from",
        "into", "about", "are", "was", "were", "will", "has", "have", "not", "you",
        "each", "per", "its", "via", "onto",
    ]

    // Only the head of each deliverable body is scanned for relevance — enough to
    // capture the subject without letting a long body dominate the token overlap.
    private static let scoreScanChars = 600
    // A title-token match is worth more than a body-token match: titles are dense signal.
    private static let titleWeight = 3
    private static let bodyWeight = 1
    // Per-excerpt body clip in the rendered prior-work block.
    private static let excerptCap = 240

    /// Split text into lowercased, de-duped content tokens (≥3 chars, no stopwords).
    private static func tokenize(_ s: String) -> Set<String> {
        var out: Set<String> = []
        for raw in s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted) {
            if raw.count >= 3 && !stopwords.contains(raw) { out.insert(raw) }
        }
        return out
    }

    private static func overlap(_ a: Set<String>, _ b: Set<String>) -> Int {
        a.filter { b.contains($0) }.count
    }

    /// Choose which shipped deliverables to ground the current chat turn on. Ranks by
    /// token-overlap relevance between `query` (the founder's latest message) and each
    /// deliverable's title + body — a title match counts for more than a body match.
    /// `query` nil/empty (or with no scorable tokens) falls back to most-recent by
    /// `createdAt` desc. Ties keep newest-first order (stable). Pure and deterministic.
    static func selectPriorWork(_ library: [Deliverable], query: String? = nil, max: Int = 3) -> [Deliverable] {
        let usable = library.filter {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let newestFirst = usable.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }

        let q = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return Array(newestFirst.prefix(max)) }

        let queryTokens = tokenize(q)
        guard !queryTokens.isEmpty else { return Array(newestFirst.prefix(max)) }

        let scored = newestFirst.enumerated().map { (i, item) -> (index: Int, item: Deliverable, score: Int) in
            let titleScore = titleWeight * overlap(queryTokens, tokenize(item.title))
            let bodyScore = bodyWeight * overlap(queryTokens, tokenize(String(item.body.prefix(scoreScanChars))))
            return (i, item, titleScore + bodyScore)
        }
        let ranked = scored.sorted { a, b in
            a.score != b.score ? a.score > b.score : a.index < b.index
        }
        return Array(ranked.prefix(max).map { $0.item })
    }

    /// Render selected prior work as a grounding block. "" when there's nothing to
    /// ground on (caller omits the block entirely) — mirrors web's composePriorWorkContext.
    private static func composePriorWork(_ items: [Deliverable]) -> String {
        guard !items.isEmpty else { return "" }
        let lines = items.map { d -> String in
            let flattened = d.body.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            let excerpt = flattened.count > excerptCap ? String(flattened.prefix(excerptCap)) + "…" : flattened
            return "- \(d.title) (\(d.kind.rawValue)): \(excerpt)"
        }
        return "Already-shipped work in this company — stay consistent with it. "
            + "Do not contradict the naming, pricing, positioning, or decisions already delivered:\n"
            + lines.joined(separator: "\n")
    }

    /// Render a compact per-department status snapshot — one line per department that
    /// has at least one task assigned (fully-untouched departments are skipped), mirroring
    /// web's deptSummary (`- name (status, N to do): focus`).
    private static func composeDepartments(_ summaries: [DepartmentSummary]) -> String {
        let active = summaries.filter { $0.status != .later }
        guard !active.isEmpty else { return "" }
        let lines = active.map { s -> String in
            let focus = s.currentTaskTitle ?? s.department.focus
            return "- \(s.department.name) (\(s.status.label(.en)), \(s.pending) to do): \(focus)"
        }
        return "Departments:\n" + lines.joined(separator: "\n")
    }

    static func compose(brief: CompanyBrief, tasks: [RoadmapTask], decisions: [DecisionEntry] = [],
                         library: [Deliverable] = [], query: String? = nil,
                         focusDepartment: Department? = nil) -> String {
        var parts: [String] = []
        parts.append(BriefContext.compose(brief) ?? "No brief yet.")
        if let dep = focusDepartment {
            parts.append("The founder is focused on the \(dep.name) department right now — "
                + "prioritize \(dep.name) in your answer: \(dep.focus)")
        }
        let d = Decisions.composeDecisions(decisions)
        if !d.isEmpty { parts.append(d) }
        parts.append("Roadmap progress: \(RoadmapEngine.progressPercent(tasks))%.")
        if let next = RoadmapEngine.nextStep(tasks) {
            parts.append("Next step: \(next.title).")
        }
        let openTitles = tasks.filter { !$0.done }.prefix(6).map { $0.title }
        if !openTitles.isEmpty {
            parts.append("Open tasks: " + openTitles.joined(separator: "; ") + ".")
        }
        let deptBlock = composeDepartments(DepartmentCatalog.summaries(tasks: tasks))
        if !deptBlock.isEmpty { parts.append(deptBlock) }
        let priorBlock = composePriorWork(selectPriorWork(library, query: query))
        if !priorBlock.isEmpty { parts.append(priorBlock) }
        return parts.joined(separator: "\n")
    }
}

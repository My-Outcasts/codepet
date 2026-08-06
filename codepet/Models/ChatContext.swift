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

    /// Says out loud that nothing on the roadmap is runnable this turn, and names the step
    /// holding it shut — the companion's own words are the only place the founder can learn
    /// this, and without it they don't.
    ///
    /// The CF is only given the `run_task` tool when the client sends a non-empty runnable
    /// list (`companyChat.ts`: `...(runnable.length ? [RUN_TASK_TOOL] : [])`), and that list
    /// is exactly the `codepetCanDo` tasks. So on a roadmap whose window is held shut by the
    /// founder's own step, "do this task here" cannot be answered with a run no matter how
    /// plainly it is asked — and what the founder got instead was "On it — putting that
    /// together now." plus a chip to go somewhere else. Observed in the app, Aug 5.
    ///
    /// `runRefusalCopy` already holds the honest sentence for every un-runnable status, but
    /// it only fires on a returned `run_task_id`, which this is precisely the case that can
    /// never produce. So the refusal has to come from the reply itself, which means the model
    /// has to know. Empty when at least one task IS runnable: then the tool is on the table
    /// and nothing needs saying.
    private static func composeRunnableGate(_ tasks: [RoadmapTask]) -> String {
        guard !tasks.isEmpty,
              !tasks.contains(where: { RoadmapEngine.status(for: $0, in: tasks) == .codepetCanDo })
        else { return "" }
        var lines: [String] = [
            "You cannot run any roadmap task in this conversation right now — not one of them is runnable.",
        ]
        // WHY nothing is runnable, and therefore what to offer. These are two different situations
        // with two different remedies, and the gate used to have one branch for both — the wrong one.
        //
        // Observed Aug 6: two drafts Codepet had produced sat waiting for approval, holding the
        // Build phase shut. The gate reached for `founderStep` (now `blockingDraft`), which returns
        // an unapproved DRAFT, and told the model it was "the founder's own step" that the roadmap
        // was waiting on her to FINISH — then instructed it to offer a walkthrough. The model
        // obeyed: it said "I can't produce these tasks for you outright — building the company is
        // your work" about a task the roadmap itself marks Codepet-can-do, and hand-wrote the cold
        // outreach email in prose. The one thing that would have unblocked her — approving two
        // drafts, one click each — was never mentioned.
        if let draft = RoadmapGating.blockingDraft(in: tasks) {
            let unlocks = tasks.filter { !$0.done && $0.dependsOn.contains(draft.id) }.count
            var line = "\"\(draft.title)\" is work YOU already drafted and it is waiting for the founder's"
                + " approval — that approval is what unlocks the rest of the roadmap."
            if unlocks > 0 {
                line += " Approving it unblocks \(unlocks) later task\(unlocks == 1 ? "" : "s")."
            }
            lines.append(line)
            lines.append("If they ask you to run, do, make or finish a task — including \"do it in here\" — do"
                + " NOT say you are on it, and do not imply anything is being produced. Do NOT offer to walk"
                + " them through it and do NOT write the deliverable out in the chat: the work is already done"
                + " and waiting. Ask them to review and approve the draft, and say what that unlocks.")
        } else if let mine = RoadmapGating.openFounderTask(in: tasks) {
            lines.append("\"\(mine.title)\" is the founder's own step — it is not something you can do for them.")
            lines.append("If they ask you to run, do, make or finish a task — including \"do it in here\" — do"
                + " NOT say you are on it, and do not imply anything is being produced. Say which step is"
                + " theirs, then offer to walk them through it.")
        } else {
            lines.append("There is genuinely nothing left for you to pick up — say so plainly rather than"
                + " inventing work, and do not imply anything is being produced.")
        }
        return lines.joined(separator: " ")
    }

    /// `memoryEnabled` mirrors `FounderPrefs.memoryEnabled` and gates ONE of the two memory
    /// stores: the facts the founder's team was told (`decisions`). Off means the block is
    /// never composed, so nothing the founder asked to be forgotten leaks back in through
    /// grounding. The other store — derived coding activity — is gated in
    /// `MemoryDigest.codingMemoryPrompt`. Defaults to `true` so callers with no founder in
    /// hand keep their current grounding.
    static func compose(brief: CompanyBrief, tasks: [RoadmapTask], decisions: [DecisionEntry] = [],
                         library: [Deliverable] = [], query: String? = nil,
                         focusDepartment: Department? = nil, memoryEnabled: Bool = true) -> String {
        var parts: [String] = []
        parts.append(BriefContext.compose(brief) ?? "No brief yet.")
        if let dep = focusDepartment {
            parts.append("The founder is focused on the \(dep.name) department right now — "
                + "prioritize \(dep.name) in your answer: \(dep.focus)")
        }
        let d = memoryEnabled ? Decisions.composeDecisions(decisions) : ""
        if !d.isEmpty { parts.append(d) }
        parts.append("Roadmap progress: \(RoadmapEngine.progressPercent(tasks))%.")
        if let next = RoadmapEngine.nextStep(tasks) {
            parts.append("Next step: \(next.title).")
        }
        let openTitles = tasks.filter { !$0.done }.prefix(6).map { $0.title }
        if !openTitles.isEmpty {
            parts.append("Open tasks: " + openTitles.joined(separator: "; ") + ".")
        }
        // Directly after the task list it qualifies: the titles above are the ones the
        // founder can see, and this is what the companion may and may not promise about them.
        let gate = composeRunnableGate(tasks)
        if !gate.isEmpty { parts.append(gate) }
        let deptBlock = composeDepartments(DepartmentCatalog.summaries(tasks: tasks))
        if !deptBlock.isEmpty { parts.append(deptBlock) }
        let priorBlock = composePriorWork(selectPriorWork(library, query: query))
        if !priorBlock.isEmpty { parts.append(priorBlock) }
        return parts.joined(separator: "\n")
    }
}

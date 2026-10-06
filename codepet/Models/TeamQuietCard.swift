// codepet/Models/TeamQuietCard.swift
import Foundation

/// The plan as stages (6 Oct design pass): every step sits one stage after its deepest
/// dependency, so "Then" lists the steps that run side by side. It replaces a "waits for X" line
/// under every row — the build-8 plan said "waits for Engineering" four times and the reader still
/// had to work out that those four ran together.
enum TeamPlanStages {
    static func group(_ plan: WorkPlan) -> [[WorkStep]] {
        let byId = Dictionary(plan.steps.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var level: [String: Int] = [:]
        // Iterative depth with a visiting set, so a malformed plan with a cycle cannot recurse
        // forever: a back edge counts as no dependency.
        func depth(_ id: String, _ visiting: inout Set<String>) -> Int {
            if let l = level[id] { return l }
            guard let step = byId[id], visiting.insert(id).inserted else { return 0 }
            let d = step.dependsOn.filter { byId[$0] != nil && !visiting.contains($0) }
                .map { depth($0, &visiting) + 1 }.max() ?? 0
            visiting.remove(id)
            level[id] = d
            return d
        }
        var stages: [Int: [WorkStep]] = [:]
        for step in plan.steps {
            var visiting = Set<String>()
            stages[depth(step.id, &visiting), default: []].append(step)
        }
        return stages.keys.sorted().compactMap { stages[$0] }
    }

    /// "First", "Then"…, "Last" — nil for a single stage, where a label would only add a word.
    static func label(_ index: Int, of count: Int, lang: AppLanguage) -> String? {
        guard count > 1 else { return nil }
        let vi = lang == .vi
        if index == 0 { return vi ? "Trước" : "First" }
        if index == count - 1 { return vi ? "Cuối" : "Last" }
        return vi ? "Sau đó" : "Then"
    }
}

extension TeamBuildCopy {
    /// The finished card's one line, in place of the plan text nobody rereads at that point: how
    /// long from the first step starting to the last finishing, and how many departments did it.
    static func readySummary(_ run: TeamRun, lang: AppLanguage) -> String {
        let vi = lang == .vi
        var seen = Set<String>()
        let depts = run.plan.steps.map(\.dept).filter { seen.insert($0).inserted }.count
        let who = vi ? "\(depts) phòng ban cùng làm" : "\(depts) department\(depts == 1 ? "" : "s")"
        let starts = run.steps.compactMap(\.startedAt)
        let ends = run.steps.compactMap(\.finishedAt)
        // Every step must carry both stamps; a partly restored run would understate the time.
        guard starts.count == run.steps.count, ends.count == run.steps.count,
              let first = starts.min(), let last = ends.max(), last >= first else {
            return vi ? "Xong, \(who)." : "Built by \(who)."
        }
        let minutes = Int((last.timeIntervalSince(first) / 60).rounded(.down))
        if minutes < 1 { return vi ? "Xong trong chưa đầy một phút, \(who)." : "Built in under a minute by \(who)." }
        return vi ? "Xong trong \(minutes) phút, \(who)." : "Built in \(minutes) min by \(who)."
    }
}

/// Which button leads a finished run. Founder decision (6 Oct): see the page first, with Approve
/// beside it. With nothing to open, Approve leads — a card is never left without a primary.
enum TeamReadyAction: Equatable {
    case runDev, openIndex, approve

    static func primary(isNodeProject: Bool, hasIndexHTML: Bool) -> TeamReadyAction {
        if isNodeProject { return .runDev }
        if hasIndexHTML { return .openIndex }
        return .approve
    }
}

/// The transcript while a Team Build is gathering its room or planning.
enum TeamWaiting {
    /// The gathering/planning line IS the progress signal; the generic typing row ("Cooking…")
    /// under it was a second signal saying less, and the build-8 screenshots showed both at once.
    static func showsTypingRow(typing: Bool, convening: Bool, planning: Bool) -> Bool {
        typing && !convening && !planning
    }

    /// The departments a room seated, each once, in seat order. Chief of staff and the devil's
    /// advocate have no department key and are not pets on the line.
    static func departments(seated keys: [String?]) -> [String] {
        var seen = Set<String>()
        return keys.compactMap { $0 }.filter { seen.insert($0).inserted }
    }
}

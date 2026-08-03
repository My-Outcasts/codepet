// codepet/Models/RoadmapGating.swift
import Foundation

/// Where a phase stands in the founder's rolling window.
///
/// `open` phases are the ones the founder may act in; they form a PREFIX of the phase order,
/// not a single column, because Codepet-owned leftovers don't hold the window shut. `preview`
/// is the next planned phase — visible and locked, so the journey ahead is legible.
enum PhaseState: Equatable { case complete, open, preview, later }

/// The rolling-window rule: which phases are open, why a locked task is locked, and who has
/// to move for the window to advance. Pure — no network, no mutation, no view types.
enum RoadmapGating {
    /// Work only the FOUNDER can clear: their own step, or a draft awaiting their approval.
    ///
    /// Deliberately STRUCTURAL rather than asking `RoadmapEngine.status` — `status` consults
    /// this gating, so calling it here would recurse forever.
    static func needsFounder(_ task: RoadmapTask) -> Bool {
        !task.done && (task.drafted || task.who == .you)
    }

    /// A phase blocks nothing once no task in it still needs the founder. A `codepetCanDo`
    /// leftover does NOT keep the next phase shut — that's exactly what makes the open set a
    /// prefix, and it's what stops the founder being stuck behind work Codepet owes them.
    /// A phase with no tasks is trivially settled: an unplanned phase can't gate anything.
    static func settled(_ phase: RoadmapPhase, in tasks: [RoadmapTask]) -> Bool {
        !tasks.contains { $0.phase == phase && needsFounder($0) }
    }

    /// Every phase whose predecessors are all settled. The first phase has no predecessors, so
    /// the result is never empty — the founder always has somewhere to act.
    static func openPhases(_ tasks: [RoadmapTask]) -> Set<RoadmapPhase> {
        var out: Set<RoadmapPhase> = []
        for phase in RoadmapPhase.allCases {
            out.insert(phase)                      // this phase's predecessors are all settled
            if !settled(phase, in: tasks) { break } // …and it holds founder work, so stop here
        }
        return out
    }

    /// Per-phase state for the board's headers and rails. Precedence:
    /// `complete → open → preview → later`.
    static func states(_ tasks: [RoadmapTask]) -> [RoadmapPhase: PhaseState] {
        let open = openPhases(tasks)
        let populated = Set(tasks.map(\.phase))
        // The preview skips PAST empty phases: a gap in the plan must not swallow the one
        // look-ahead the founder gets.
        let preview = RoadmapPhase.allCases.first { !open.contains($0) && populated.contains($0) }
        var out: [RoadmapPhase: PhaseState] = [:]
        for phase in RoadmapPhase.allCases {
            let mine = tasks.filter { $0.phase == phase }
            if !mine.isEmpty && mine.allSatisfy(\.done) { out[phase] = .complete }
            else if open.contains(phase)                { out[phase] = .open }
            else if phase == preview                    { out[phase] = .preview }
            else                                        { out[phase] = .later }
        }
        return out
    }

    /// The one task standing between the founder and `task`, so a locked card can explain
    /// itself and hand the founder something to actually do.
    ///
    /// Phase-gated → the earliest founder-owned step in the earliest unsettled phase, which is
    /// the same task the beacon points at (the two surfaces can't disagree). Dependency-gated →
    /// the first unfinished dependency. nil when nothing resolves (a dangling dep, a cycle).
    static func blocker(for task: RoadmapTask, in tasks: [RoadmapTask]) -> RoadmapTask? {
        if !openPhases(tasks).contains(task.phase) {
            for phase in RoadmapPhase.allCases where !settled(phase, in: tasks) {
                if let found = tasks.first(where: { $0.phase == phase && needsFounder($0) }) {
                    return found
                }
            }
        }
        return task.dependsOn.compactMap { id in tasks.first { $0.id == id && !$0.done } }.first
    }
}

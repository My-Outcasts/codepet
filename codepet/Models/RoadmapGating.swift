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

    /// The earliest founder-owned task in the earliest unsettled phase — the step holding the
    /// rolling window shut. nil once every phase is settled (nothing blocks).
    static func founderStep(in tasks: [RoadmapTask]) -> RoadmapTask? {
        for phase in RoadmapPhase.allCases where !settled(phase, in: tasks) {
            return tasks.first { $0.phase == phase && needsFounder($0) }
        }
        return nil
    }

    /// The one task standing between the founder and `task`, so a locked card can explain
    /// itself and hand the founder something to actually do.
    ///
    /// Phase-gated → `founderStep`. This is NOT always the beacon: `nextStep` minimises over
    /// the whole open window, so once the prefix spans more than one populated phase the beacon
    /// can sit in an EARLIER phase than this blocker (the earliest unsettled one). Dependency-
    /// gated → the first unfinished dependency.
    ///
    /// Either way, the candidate is then walked forward to something the founder can actually
    /// act on today (see `actionable`) — a founder-owned step can itself be blocked on its own
    /// unmet dependency, and handing the founder a second dead end defeats the point of the
    /// escape hatch. A genuine dependency cycle can't walk forever (each hop must be an
    /// unvisited task) and falls back to `RoadmapEngine.nextStep`, which is nil only when
    /// nothing in the whole roadmap is currently actionable.
    static func blocker(for task: RoadmapTask, in tasks: [RoadmapTask]) -> RoadmapTask? {
        let candidate = openPhases(tasks).contains(task.phase)
            ? task.dependsOn.compactMap { id in tasks.first { $0.id == id && !$0.done } }.first
            : founderStep(in: tasks)
        guard let candidate else { return nil }
        return actionable(candidate, in: tasks, avoiding: [task.id])
    }

    /// Walk from `start` toward a task whose status isn't `.blocked`, following unmet
    /// dependencies one hop at a time. `avoiding` guards a dependency cycle: each hop must land
    /// on a task not already visited, so the walk always terminates — either on an actionable
    /// task or by falling through to the beacon.
    private static func actionable(_ start: RoadmapTask, in tasks: [RoadmapTask],
                                    avoiding visited: Set<String>) -> RoadmapTask? {
        var current = start
        var seen = visited
        while !seen.contains(current.id) {
            seen.insert(current.id)
            if RoadmapEngine.status(for: current, in: tasks) != .blocked { return current }
            guard let next = current.dependsOn.compactMap({ id in tasks.first { $0.id == id && !$0.done } }).first
            else { break }
            current = next
        }
        return RoadmapEngine.nextStep(tasks)
    }
}

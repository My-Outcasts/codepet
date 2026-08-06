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
    /// Still the right question for "what is waiting on you" (`blockingDraft`, the blocker copy,
    /// the needs-you counts). It is NO LONGER what holds the phase window shut — see `settled`.
    ///
    /// Deliberately STRUCTURAL rather than asking `RoadmapEngine.status` — `status` consults
    /// this gating, so calling it here would recurse forever.
    static func needsFounder(_ task: RoadmapTask) -> Bool {
        !task.done && (task.drafted || task.who == .you)
    }

    /// Output the founder has not looked at yet. The one thing that still holds the window.
    static func awaitsApproval(_ task: RoadmapTask) -> Bool {
        !task.done && task.drafted
    }

    /// A phase stops holding the next one once nothing in it is waiting to be REVIEWED.
    ///
    /// CHANGED Aug 5 2026, founder call. It used to be "nothing in it still needs the founder",
    /// which counted their own tasks too — so one parked founder-owned step switched the entire
    /// AI team off. Measured in the app that day: four separate times the founder asked for work
    /// and nothing at all was runnable, because "Talk to 5 potential users" sat open in `.find`
    /// while eight Codepet-owned tasks behind it read `.blocked`. The team is meant to work
    /// alongside her, not queue behind her.
    ///
    /// So a founder-owned task no longer gates. An unapproved DRAFT still does, and that
    /// asymmetry is the point: a draft is one tap away from resolved, while "talk to five users"
    /// is a week of her life — and leaving drafts as a gate keeps the pipeline self-limiting.
    /// Codepet can run ahead, but never further ahead than the founder has reviewed, so it
    /// cannot generate ten unread deliverables while she is out doing interviews.
    ///
    /// What did NOT change, and must not: a task that genuinely DEPENDS on her step stays
    /// blocked. `RoadmapEngine.status` checks `depsSatisfied` separately, so landing-page copy
    /// that depends on the interviews still waits for them — its input really does not exist
    /// yet. This only stops the PHASE from gating work whose inputs are ready.
    ///
    /// A phase with no tasks is trivially settled: an unplanned phase can't gate anything.
    static func settled(_ phase: RoadmapPhase, in tasks: [RoadmapTask]) -> Bool {
        !tasks.contains { $0.phase == phase && awaitsApproval($0) }
    }

    /// Every phase whose predecessors are all settled. The first phase has no predecessors, so
    /// the result is never empty — the founder always has somewhere to act.
    static func openPhases(_ tasks: [RoadmapTask]) -> Set<RoadmapPhase> {
        var out: Set<RoadmapPhase> = []
        for phase in RoadmapPhase.allCases {
            out.insert(phase)                      // this phase's predecessors are all settled
            if !settled(phase, in: tasks) { break } // …and it holds unreviewed output, so stop
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

    /// The step actually holding the rolling window shut — the earliest unapproved DRAFT, in the
    /// earliest unsettled phase. nil once every phase is settled, which now includes the common
    /// case of an open founder-owned task with no drafts behind it (that no longer gates).
    ///
    /// Reads `awaitsApproval`, not `needsFounder`: since Aug 5 only a draft can make a phase
    /// unsettled, and asking the broader question here could name a founder-owned task that
    /// happens to sit earlier in the array than the draft — putting a name on the card that is
    /// not the thing in the way.
    /// RENAMED from `founderStep` on Aug 7. It never returned a founder's step — it reads
    /// `awaitsApproval`, so it only ever returns an unapproved DRAFT, which is Codepet's own work
    /// waiting on a click. The misnomer is what let the chat grounding tell the founder that work
    /// Codepet had already drafted was "the founder's own step, and the roadmap stays shut until
    /// they finish it" — so Codepet refused to run anything and offered to walk her through doing
    /// its job by hand, when the real answer was "approve these two". See `ChatContext`.
    static func blockingDraft(in tasks: [RoadmapTask]) -> RoadmapTask? {
        for phase in RoadmapPhase.allCases where !settled(phase, in: tasks) {
            return tasks.first { $0.phase == phase && awaitsApproval($0) }
        }
        return nil
    }

    /// The founder's own open work, when that is what is left.
    ///
    /// Distinct from `blockingDraft` and needed alongside it: since Aug 5 a founder-owned step no
    /// longer shuts the phases behind it, so "nothing is runnable" has two different causes with
    /// two different remedies — a draft needs APPROVING (one click), a founder step needs DOING.
    /// Conflating them is the bug this pair exists to prevent.
    ///
    /// Scoped to the open window, because a founder task sitting behind an unfinished dependency
    /// is not what the founder can pick up today.
    static func openFounderTask(in tasks: [RoadmapTask]) -> RoadmapTask? {
        let open = openPhases(tasks)
        return tasks.first { task in
            !task.done && task.who == .you && open.contains(task.phase)
                && task.dependsOn.allSatisfy { id in tasks.first { $0.id == id }?.done ?? true }
        }
    }

    /// The one thing standing in front of `task`, for DISPLAY — the card face and the node
    /// panel both render this by name, so it is strict: the first unfinished dependency, or the
    /// founder step holding the rolling window shut. No walk and no fallback, because a
    /// fallback would let a cyclic graph put an unrelated task's name on the card.
    ///
    /// NOT always the beacon: `RoadmapEngine.nextStep` minimises over the whole open window, so
    /// once the prefix spans more than one populated phase the beacon can sit in an EARLIER
    /// phase than this blocker (the earliest unsettled one). Both are legitimate.
    static func blocker(for task: RoadmapTask, in tasks: [RoadmapTask]) -> RoadmapTask? {
        openPhases(tasks).contains(task.phase)
            ? task.dependsOn.compactMap { id in tasks.first { $0.id == id && !$0.done } }.first
            : blockingDraft(in: tasks)
    }

    /// Where a locked card's tap should GO — the blocker walked forward to something the founder
    /// can act on today. A founder-owned step can itself be dependency-blocked, and handing the
    /// founder a second dead end defeats the escape hatch. Terminates on cyclic and
    /// self-referencing graphs (see `actionable`) and falls back to the beacon, which is nil only
    /// when nothing in the roadmap is actionable at all.
    static func escapeHatch(for task: RoadmapTask, in tasks: [RoadmapTask]) -> RoadmapTask? {
        guard let candidate = blocker(for: task, in: tasks) else { return nil }
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

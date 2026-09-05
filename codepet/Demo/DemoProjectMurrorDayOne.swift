// codepet/Demo/DemoProjectMurrorDayOne.swift
#if DEBUG
import Foundation

/// Murror on day one — the same company before any of it had been done.
///
/// **Why a second state and not a second company.** The demo's claim is that running the nine
/// questions gets you to the board the tour then walks. That is only true while both states read
/// from one task list: `tasks` here is `murrorTasks` with nine `done` flags cleared, and nothing
/// else. Brief, deliverables, department replies and room frames are shared by reference.
///
/// **No deliverable content is written here.** `deliverable(for:)` matches keywords against the
/// title, so these nine tasks resolve to the nine artifacts mid-flight already files.
extension DemoProject {

    /// The nine questions, in the order a founder actually has them.
    ///
    /// Marketing appears at both ends of the opening — "is this real?" then "has someone built
    /// it?" — which is why nine tasks cover eight departments.
    static let dayOneChain = [
        "mur-interviews",   // Marketing · Nova   — is this a real problem, or just mine?
        "mur-landscape",    // Marketing · Nova   — has someone already built this?
        "mur-notfor",       // Sales · Nova       — so who is it not for?
        "mur-brand",        // Design · Luna      — what should it feel like?
        "mur-stack",        // Engineering · Byte — what do I build it on?
        "mur-unitcost",     // Finance · Crash    — what will this cost me a month?
        "mur-crisis",       // Support · Sage     — what if someone's struggling at 2am?
        "mur-deletion",     // Legal · Glitch     — am I in trouble for holding their words?
        "mur-rhythm",       // Operations · Glitch— how do I ship without breaking it?
    ]

    static let murrorDayOne = DemoProject(
        id: "murror-day-one",
        brief: DemoProject.murror.brief,
        tasks: DemoProject.murror.tasks.map { task in
            guard dayOneChain.contains(task.id) else { return task }
            var open = task
            open.done = false
            return open
        },
        deliverables: murrorDeliverables,
        departmentReplies: DemoProject.murrorDepartmentReplies,
        // Nothing filed. The Library fills as she approves, which is the point.
        filed: [],
        roomFrames: murrorRoomFrames(ask:)
    )
}
#endif

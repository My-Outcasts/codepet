// codepet/Demo/DemoProjectMurror.swift
#if DEBUG
import Foundation

/// Murror — the second demo company, and the one that proves the fixtures carry a PROJECT rather
/// than a coat of paint.
///
/// Codepet's fixture demos a founder tool to a founder. Murror is a consumer app about loneliness,
/// so nothing about Codepet's copy survives the move: the audience, the problem, the departments
/// that matter and the argument the room has are all different. That is the point of having two.
///
/// Content is Murror's own, taken from murror.app rather than invented — "The connection
/// practice", "AI that brings people closer", emotion recognition, relationship insights, small
/// acts of care, private by design.
extension DemoProject {

    static let murror = DemoProject(
        id: "murror",
        brief: {
            var b = CompanyBrief()
            b.founderName = "Mona"
            b.projectName = "Murror"
            b.oneLiner = "AI that brings people closer."
            b.audience = "Adults who feel lonely and want to be closer to the people they love"
            b.problem = "Most of us were never taught how to understand what we feel, "
                + "or how to show up for someone else."
            b.goal = "Get 20 people through a first week of the practice and see who comes back."
            b.stage = "building"
            return b
        }(),
        tasks: murrorTasks,
        deliverables: murrorDeliverables,
        departmentReplies: DemoProject.murrorDepartmentReplies,
        // The three prerequisites every other Murror task depends on. They are `done` in the
        // board above, and a `done` task with nothing filed behind it is a state the real
        // product cannot reach — approving is what marks a task done AND files its
        // deliverable. Filing them is what lets the demo show departments building on each
        // other at all: `UpstreamWork.assemble` reads the library.
        // Nine filed artifacts across all eight roster departments. The first three are the
        // research the open tasks build on; the six below are what the other departments have
        // already finished.
        filed: ["mur-interviews", "mur-landscape", "mur-brand",
                "mur-stack", "mur-unitcost", "mur-notfor",
                "mur-crisis", "mur-rhythm", "mur-deletion"],
        roomFrames: murrorRoomFrames(ask:)
    )

    /// **Eleven tasks: a three-task completed spine, and eight runnable — one per roster
    /// department.**
    ///
    /// The shape is a company already in motion rather than a blank slate, and the reason is
    /// mechanical. `RoadmapEngine.status` returns `.codepetCanDo` only when every id in
    /// `dependsOn` resolves to a task that is `done` (`depsSatisfied`), so **for all eight pets
    /// to be runnable at once, the eight may depend only on completed tasks.** The edges
    /// therefore hang off the spine instead of chaining the runnables together.
    ///
    /// It would have been simpler to give the eight no dependencies at all. That was rejected for
    /// the same reason `MockChat.roadmap()`'s graph exists: with `dependsOn` empty every task
    /// qualifies as an entry task, `RoadmapLayoutEngine` draws zero dependency edges and fans the
    /// root out to all of them — the board cannot exercise its own flow rendering, and it does
    /// not look like a plan. This graph covers each routing case exactly once:
    ///
    ///   - `{brand, landscape} → site` is a **fan-IN**, two sources into one target. Its
    ///     `landscape` leg is also a shared-lane straight run: both sit on the `mkt` lane.
    ///   - `brand → screens` is an **IN-COLUMN** edge — both are `.foundation`, both `design` —
    ///     so it exercises `sideElbow`'s left-gutter hook.
    ///   - `brand → launch` **SKIPS** `.build`, and `interviews → privacy` skips two phases.
    ///     Skip-level edges are the reproduction for the routing flaw where they read as a
    ///     chain; they are here on purpose and should not be "tidied" away.
    ///   - `{interviews, landscape} → outreach` is a second fan-IN, both legs from `.find`.
    ///
    /// **No task sets `drafted`.** An unapproved draft is the one thing that still closes the
    /// phase window (`RoadmapGating.awaitsApproval`, changed 2026-08-05 so a founder-owned task
    /// no longer gates), and one here would block everything behind it regardless of the graph.
    private static var murrorTasks: [RoadmapTask] {
        [
            // ── THE DAY-ONE CHAIN ───────────────────────────────────────────────────────────
            // These nine carry a linear `dependsOn`, but not for ordering — `RoadmapEngine.nextStep`
            // sorts every dependency-satisfied open task by (phase order, array position) rather
            // than walking a chain. The edges exist so `UpstreamWork.assemble` can credit each
            // link's predecessor; the script names its ids explicitly. The edges are SAFE for
            // mid-flight because all nine are `done` there, and `status` returns `.done` before
            // it consults `depsSatisfied` — no status, no beacon and no runnable count moves.
            //
            // `mur-brand` KEEPS its existing `mur-landscape` edge. Replacing rather than adding
            // would quietly rewrite mid-flight's roadmap.
            // ── FIND: complete. The research that the rest of the board depends on. ──────────
            RoadmapTask(id: "mur-interviews", title: "Talk to 12 people about being lonely",
                        detail: "Not about the app — about the last evening they wanted to reach out and didn't.",
                        phase: .find, who: .you, done: true, dept: "mkt"),
            RoadmapTask(id: "mur-landscape", title: "Scan the journaling and companion apps",
                        detail: "What they promise, what they actually do on day three, and where the gap is.",
                        phase: .find, who: .draft,
                        dependsOn: ["mur-interviews"], done: true, dept: "mkt"),

            // A founder-only task that is still OPEN. Murror had exactly one `who: .you`
            // (`mur-interviews`) and it is `done`, so the "needs you" landing card, the
            // `needsYou` roadmap state and the walkthrough's "Work only you can do" chapter all
            // had nothing to render — that beat silently no-opped on this project. Codepet's
            // fixture carries `mock-interviews` for exactly this reason.
            // ── FOUNDATION ──────────────────────────────────────────────────────────────────
            // Done, and the ancestor three runnables hang off.
            RoadmapTask(id: "mur-brand", title: "Shape the Murror visual direction",
                        detail: "Night sky, warm light. It has to feel safe enough to be honest in.",
                        phase: .foundation, who: .draft,
                        dependsOn: ["mur-landscape", "mur-notfor"], done: true, dept: "design"),
            // THE WEBSITE. Fan-IN: the page needs both the visual direction and the positioning.
            RoadmapTask(id: "mur-site", title: "Build the Murror landing page",
                        detail: "One page that says what the practice is, for someone who has never heard of it.",
                        phase: .foundation, who: .draft,
                        dependsOn: ["mur-brand", "mur-landscape"], dept: "mkt"),
            // In-column with `mur-brand` → sideElbow.
            RoadmapTask(id: "mur-screens", title: "Design the first-run flow",
                        detail: "Four screens from install to the first message actually sent.",
                        phase: .foundation, who: .draft,
                        dependsOn: ["mur-brand"], dept: "design"),
            RoadmapTask(id: "mur-pricing", title: "Decide what free and paid mean",
                        detail: "Where the line sits when the thing being sold is somebody's own history.",
                        phase: .foundation, who: .draft,
                        dependsOn: ["mur-landscape"], dept: "fin"),

            // ── BUILD ───────────────────────────────────────────────────────────────────────
            RoadmapTask(id: "mur-signup", title: "Ship an email capture",
                        detail: "One field, no backend, so the interest from the interviews isn't lost.",
                        phase: .build, who: .does,
                        dependsOn: ["mur-brand"], dept: "eng"),

            // A founder-only task that is still OPEN, and the ONLY one on this board.
            // `mur-interviews` is `who: .you` but `done`, so before this the "needs you"
            // landing card, the `needsYou` roadmap state and the walkthrough's "Work only you
            // can do" chapter all had nothing to render — that beat silently no-opped on
            // Murror. Codepet's fixture carries `mock-interviews` for exactly this reason.
            //
            // In FOUNDATION, not `.find`: `.find` must stay complete or the board stops being
            // the mid-flight state the whole fixture is built to show.
            RoadmapTask(id: "mur-clinician", title: "Get a clinician to read the crisis path",
                        detail: "Codepet cannot do this one. It needs a name, an email, and "
                            + "someone qualified saying the wording is safe.",
                        phase: .foundation, who: .you, dept: "support"),

            // ── WORK ALREADY BEHIND THE FOUNDER ─────────────────────────────────────────────
            //
            // One `done` task per department the board did not already cover, each with a real
            // deliverable filed in `filed` below. This is what makes the Library show EIGHT
            // groups: it already groups by department, and had only two departments' work.
            //
            // In FOUNDATION rather than `.find`: `.find` must stay complete (a test asserts it)
            // or the board stops being the mid-flight state the fixture exists to show, and
            // foundation already has open work so the phase window does not move.
            //
            // These are `done`, so they do not join the eight `codepetCanDo` tasks — the demo's
            // headline claim survives, and the board reads like a real mid-flight company: work
            // behind you and work in front of you.
            RoadmapTask(id: "mur-stack", title: "Choose what the app is built on",
                        detail: "On-device or server, and what that decision closes off.",
                        phase: .foundation, who: .draft,
                        dependsOn: ["mur-brand"], done: true, dept: "eng"),
            RoadmapTask(id: "mur-unitcost", title: "Work out what a month of inference costs",
                        detail: "Per active user, at today's model. The floor pricing argues from.",
                        phase: .foundation, who: .draft,
                        dependsOn: ["mur-stack"], done: true, dept: "fin"),
            RoadmapTask(id: "mur-notfor", title: "Write down who this is not for",
                        detail: "The disqualifiers, so outreach stops spending its best hours wrong.",
                        phase: .foundation, who: .draft,
                        dependsOn: ["mur-landscape"], done: true, dept: "sales"),
            RoadmapTask(id: "mur-crisis", title: "Decide what happens on a bad night",
                        detail: "The crisis path as policy. Wording can change; behaviour cannot.",
                        phase: .foundation, who: .draft,
                        dependsOn: ["mur-unitcost"], done: true, dept: "support"),
            RoadmapTask(id: "mur-rhythm", title: "Set up the weekly release rhythm",
                        detail: "Thursday, not Friday, and the one thing that stops a release.",
                        phase: .foundation, who: .draft,
                        dependsOn: ["mur-deletion"], done: true, dept: "ops"),
            RoadmapTask(id: "mur-deletion", title: "Write the data-deletion promise",
                        detail: "One tap, permanent, no email. The policy formalises it later.",
                        phase: .foundation, who: .draft,
                        dependsOn: ["mur-crisis"], done: true, dept: "legal"),
            // Second fan-IN, both legs from `.find`.
            RoadmapTask(id: "mur-outreach", title: "Find the first 20 users",
                        detail: "Three places where people already talk about this, and what to say in each.",
                        phase: .build, who: .draft,
                        dependsOn: ["mur-interviews", "mur-landscape"], dept: "sales"),
            RoadmapTask(id: "mur-faq", title: "Answer the first questions",
                        detail: "Starting with the one everybody asks first, and answering it honestly.",
                        phase: .build, who: .draft,
                        dependsOn: ["mur-interviews"], dept: "support"),

            // ── SHIP ────────────────────────────────────────────────────────────────────────
            // SKIPS .build on purpose — the skip-level routing case.
            RoadmapTask(id: "mur-launch", title: "Write the launch checklist",
                        detail: "Including the one item that can block a launch outright.",
                        phase: .ship, who: .does,
                        dependsOn: ["mur-brand"], dept: "ops"),
            // Skips two phases — the second skip-level case.
            RoadmapTask(id: "mur-privacy", title: "Draft the privacy policy",
                        detail: "Plain language, because the data here is the most personal kind there is.",
                        phase: .ship, who: .draft,
                        dependsOn: ["mur-interviews"], dept: "legal"),
        ]
    }
}
#endif

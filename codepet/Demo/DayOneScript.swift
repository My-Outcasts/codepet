// codepet/Demo/DayOneScript.swift
#if DEBUG
import Foundation

/// Day one: the nine questions a solo founder actually has, in the order she has them.
///
/// **Why this exists.** The 24-beat tour opens on a company that already has twelve interviews,
/// a competitive scan and a brand. A founder who does not know where to start has none of those,
/// and that is who this product is for. Measured on the tour: one `.runBeacon` and one
/// `.approveNewestDraft`, so one department of eight produced anything on camera.
///
/// **Why the beats name their task ids.** Each link is a question, a run and an approval. The
/// run is `.runTask(id)`, NOT `.runBeacon`: `RoadmapEngine.nextStep` sorts every
/// dependency-satisfied open task by (phase order, array position) rather than following a
/// chain, and simulated against this fixture a beacon-driven version drifts to `mur-pricing` at
/// step 3 and never returns. `DayOneScriptTests` pins this order to `DemoProject.dayOneChain`.
///
/// The chain's `dependsOn` edges are still load-bearing — they are what `UpstreamWork.assemble`
/// reads to credit each card. They carry the HAND-OFF, not the ordering.
///
/// **The ending is a hand-back, not a finale.** After link 9 the board is mid-flight and the
/// beacon lands on the landing page — where the tour's own `.runBeacon` starts. Her tenth
/// question is the one this simulation refuses to answer for her.
enum DayOneScript {

    static let beats: [MockFlowScript.Beat] = build([
        ("Day one", 4.0, .hold,
         "Mona has a feeling and nothing else — people are lonely and don't know how to reach "
         + "each other. No plan, no brand, no idea where to start. This is the board a founder "
         + "actually begins with: empty."),

        // Link 1 — Marketing · Nova. The founder's own work, and it stays that way.
        ("Is this real?", 4.2, .walkthroughFounderTask,
         "Her first question is whether the problem is real or just hers. Codepet will not "
         + "pretend to run this one — twelve conversations are hers to have — so it prepares "
         + "the guide and says so plainly."),

        ("Is this real?", 3.4, .recordFounderTask(
            taskId: "mur-interviews",
            body: "Nine of twelve described the same evening: they thought of someone, drafted "
            + "something, and never sent it. Two wanted tracking, not company. One found the "
            + "whole idea insulting."),
         "She has the conversations and records what she heard. That is what files it — and "
         + "everything after this reads it."),

        // Link 2 — Marketing · Nova.
        ("Has someone built it?", 3.0, .runTask("mur-landscape"),
         "Second question, and the first one Codepet can take: has someone already built this? "
         + "Nova reads the interviews before answering — the credit line on the card names them."),
        ("Has someone built it?", 2.8, .approveNewestDraft,
         "Approving files it. Nothing was written anywhere until that tap, and the next "
         + "department will read what she just approved."),

        // Link 3 — Sales · Nova.
        ("Who is it not for?", 3.0, .runTask("mur-notfor"),
         "The scan turns up crowded ground, which sharpens the real question: who is this NOT "
         + "for? The one person who found it insulting is worth more here than the nine who "
         + "liked it."),
        ("Who is it not for?", 2.8, .approveNewestDraft,
         "A disqualifier list is a strange thing to be pleased about, and it is the first "
         + "artifact that makes the next four decisions easy."),

        // Link 4 — Design · Luna.
        ("What should it feel like?", 3.0, .runTask("mur-brand"),
         "Now that she knows who it is for and who it is not, Luna can shape how it feels. "
         + "A different department, a different pet, reading the two artifacts before it."),
        ("What should it feel like?", 2.8, .approveNewestDraft,
         "Four questions in, and each answer has been built on the last rather than started "
         + "from the brief again."),

        // Link 5 — Engineering · Byte.
        ("What do I build it on?", 3.0, .runTask("mur-stack"),
         "The first question with a bill attached. Byte reads the direction and decides what "
         + "the app runs on — and whether anything a person writes ever leaves their device."),
        ("What do I build it on?", 2.8, .approveNewestDraft,
         "That decision sets the running cost, which is why Finance is next and not first."),

        // Link 6 — Finance · Crash.
        ("What does it cost me?", 3.0, .runTask("mur-unitcost"),
         "Crash cannot price anything without knowing what it runs on, so this question could "
         + "not have been asked earlier. Cost per active user, from the stack just chosen."),
        ("What does it cost me?", 2.8, .approveNewestDraft,
         "A number she can hold against a price — the first artifact that constrains rather "
         + "than describes."),

        // Link 7 — Support · Sage.
        ("A bad night", 3.2, .runTask("mur-crisis"),
         "The question a consumer app about loneliness cannot avoid: what happens when someone "
         + "is genuinely struggling at 2am. Sage writes what the app says, when, and what it "
         + "refuses to handle."),
        ("A bad night", 2.8, .approveNewestDraft,
         "Written down as policy, not left to a prompt. This is the artifact the board's one "
         + "founder-only task later asks a clinician to read."),

        // Link 8 — Legal · Glitch.
        ("Am I in trouble?", 3.0, .runTask("mur-deletion"),
         "She is now holding people's private words. Glitch reads the crisis policy and the "
         + "stack decision, and turns them into a promise: one tap, permanent, no email."),
        ("Am I in trouble?", 2.8, .approveNewestDraft,
         "The promise comes before the privacy policy that formalises it — which is still "
         + "sitting on her board, unwritten."),

        // Link 9 — Operations · Glitch.
        ("How do I ship it?", 3.0, .runTask("mur-rhythm"),
         "The last question of the first week: how does any of this reach anyone without "
         + "breaking. A weekly rhythm the launch checklist will later assume."),
        ("How do I ship it?", 2.8, .approveNewestDraft,
         "Nine questions, eight departments, nine artifacts — and every one of them traces "
         + "back to a task on her roadmap."),

        ("What's next is yours", 3.6, .go(.library),
         "This is what a week looks like when every answer builds on the last. She started "
         + "with a feeling and no plan."),

        ("What's next is yours", 4.0, .go(.roadmap),
         "And the beacon has already moved on to her tenth question — how do people hear about "
         + "it? Codepet does not answer that one here. It points at the landing page and waits."),
    ])

    /// Numbers the beats so `id` cannot drift from position — the same shape `MockFlowScript`
    /// uses, and for the same reason.
    private static func build(_ raw: [(String, Double, MockFlowScript.Intent, String)])
        -> [MockFlowScript.Beat] {
        raw.enumerated().map { i, r in
            MockFlowScript.Beat(id: i, chapter: r.0, seconds: r.1, intent: r.2, caption: r.3)
        }
    }
}
#endif

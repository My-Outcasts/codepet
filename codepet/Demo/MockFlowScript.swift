// codepet/Demo/MockFlowScript.swift
#if DEBUG
import Foundation

/// The self-driving walkthrough, as data.
///
/// `-CODEPET_MOCK_FLOW YES` already gives the whole product on fixtures with zero
/// spend — but it still has to be clicked. The prototype does not: its `STORY` is
/// an array of `[chapter, ms, action, caption]` and `stepStory()` runs the action,
/// shows the caption, and schedules the next beat. This is that, in Swift.
///
/// **The beats are INTENTS, not closures.** A closure over `CompanyStore` would
/// make the script untestable and let a beat do anything; an enum means the same
/// script drives the on-screen player and a headless XCTest that asserts each beat
/// landed — which is the prototype's other half (it self-tests on load, 48/48).
///
/// **What this is not.** The prototype moves a fake cursor and taps real DOM
/// nodes, so its story also proves the buttons are wired. These intents drive
/// `CompanyStore` directly, which proves the STATES render and not that any
/// control reaches them. It is a state tour, not an input test. Worth knowing
/// before it is trusted as verification of a button.
enum MockFlowScript {

    /// One thing the walkthrough does. Everything here is performable against the
    /// real store with the mock fixtures behind it — nothing is mimed.
    enum Intent: Equatable {
        /// Ask or Developer. The shell owns `mode` as `@State`, so the player
        /// publishes this and `TwoModeShellView` adopts it.
        case mode(WorkspaceMode)
        /// One of the five company surfaces, or `.chat`.
        case go(AppView)
        /// Type something and send it. Goes through `MockChat`'s keyword router,
        /// so "run …", "roadmap …" and "long …" each exercise a different reply
        /// shape with no network.
        case say(String)
        /// Run the beacon — `RoadmapEngine.nextStep`, the same task the hero card
        /// offers. Produces a real draft through the fixture.
        case runBeacon
        /// Approve the newest draft, which is what files it in Library and closes
        /// the task. The one beat that proves "nothing is written before approval".
        case approveNewestDraft
        /// Ask for a walkthrough of the first `who == .you` task on the board — work
        /// Codepet cannot do for the founder. The prototype's "Work only you can do".
        /// No-ops when the board has no founder-only task, rather than narrating one.
        case walkthroughFounderTask
        /// Run ONE named task.
        ///
        /// **Not `.runBeacon`.** `RoadmapEngine.nextStep` sorts every dependency-satisfied open
        /// task by (phase order, array position), so it does not follow a dependency chain.
        /// Measured against the Murror fixture, a beacon-driven day-one script drifts to
        /// `mur-pricing` at step 3 and never comes back. A scripted sequence has to say what it
        /// is running.
        case runTask(String)
        /// Record what came back from the founder's own work, which files it.
        ///
        /// `walkthroughFounderTask` ASKS about a `.you` task; this one completes it. Both are
        /// needed: the demo has to show Codepet declining to do the interviews AND has to end
        /// up with the interviews filed, because everything downstream reads them.
        ///
        /// **Carries only the task id, not a body.** An earlier version carried its own prose
        /// summary, which drifted from the fixture's own filed body for the same task — the
        /// beat and mid-flight told two different stories about what got recorded. The body is
        /// resolved from the demo fixture instead, the same way every other deliverable body in
        /// the demo is resolved, so the two cannot diverge again.
        case recordFounderTask(taskId: String)
        /// Convene the Virtual Company on a decision. Safe under the demo flags only
        /// because `MockVirtualCompany` now backs `vcRunner` — before that fixture
        /// existed this beat would have spent ~$0.20 on the live endpoint, unattended,
        /// which is why the chapter was left out of the first version of this script.
        case convene(String)
        /// A new conversation.
        case newChat
        /// Link a scratch folder so Developer wakes up.
        ///
        /// `ProjectLinker.pickAndLink` opens an `NSOpenPanel`, which no script can
        /// drive — and I wrongly concluded from that the whole Developer flow was
        /// undemoable. The picker is one CALLER; `CompanyStore.linkProject(path:)`
        /// takes a path. The folder is real and created on the spot, because
        /// `ProjectProbe` reads what is actually on disk.
        case linkDemoFolder
        /// Describe a code change. Goes through `startCodeRun`, so it proposes, gates,
        /// and then runs on `MockCodeRunner` — no `claude`, no cost, real exec steps
        /// and a real diff object.
        case codeRun(String)
        /// Confirm the plan preview, which is what actually starts the work.
        ///
        /// Not ceremony in the script: a multi-file change lands in `.previewing` and
        /// waits, and until the work pane grew a Run button NOTHING in Developer could
        /// leave that phase — the chapter played over a header reading `PREPARING` and
        /// a blank pane. A separate beat rather than folding it into `codeRun`, because
        /// the gate is a state the founder should watch the walkthrough stop at.
        case confirmCodeRun
        /// Approve the diff, which commits to a branch and stops there.
        case approveCodeRun
        /// Nothing — a beat that only narrates. The prototype has these too; some
        /// captions are about what is already on screen.
        case hold
    }

    /// A beat: which chapter it belongs to, how long it sits, what it does, and
    /// what the caption says while it does it.
    struct Beat: Identifiable {
        let id: Int
        let chapter: String
        /// Seconds. Scaled by the player's pace, and floored under Reduce Motion.
        let seconds: Double
        let intent: Intent
        let caption: String
    }

    /// The chapters, in order, deduplicated from `beats` — the jump buttons.
    static var chapters: [String] {
        var seen = Set<String>()
        return beats.compactMap { seen.insert($0.chapter).inserted ? $0.chapter : nil }
    }

    /// The index of the first beat of a chapter, for the jump buttons.
    static func firstBeat(of chapter: String) -> Int? {
        beats.firstIndex { $0.chapter == chapter }
    }

    /// The first hour, in the prototype's own order and — where the copy still
    /// holds — its own words.
    ///
    /// Deliberately short. A tour that walks every surface is one nobody watches
    /// to the end, and the two things this product has to prove are that the work
    /// is real and that the founder's approval is what commits it.
    static let beats: [Beat] = build([
        // This caption used to say "a brand-new account — onboarding already read the
        // brief", over a shell that never shows onboarding. The cold open IS reachable
        // (`CODEPET_MOCK_FLOW` boots it), but the player is owned by `TwoModeShellView`,
        // which `ContentView` does not mount until `isOnboarding` is false — so it
        // cannot narrate the screen it was claiming credit for. Say what is on screen.
        ("Signing in", 2.6, .go(.chat),
         "Signed in, with a roadmap already built from the brief — so the first screen "
         + "has real work on it and nothing has been charged yet."),

        ("The first minute", 2.7, .hold,
         "The hero asks for work and names the company. Under it, the cast: eight "
         + "departments, each speaking with its own pet."),

        ("The first minute", 4.6, .runBeacon,
         "The beacon names one real task from the founder's own brief. The owning "
         + "department's specialist takes it — with its own name — and works in steps "
         + "it names out loud."),

        ("A real deliverable", 3.0, .hold,
         "The draft arrives in the conversation, attributed to the pet that wrote it. "
         + "Nothing has been filed yet."),

        ("A real deliverable", 3.0, .approveNewestDraft,
         "Approving is what files it. Library goes up by one, the roadmap task closes, "
         + "and the beacon moves on. Until that click, nothing had been written anywhere."),

        ("Work only you can do", 3.2, .newChat,
         "A fresh conversation puts the hero back, and the beacon has moved on — the "
         + "approved task is closed, so it names the next one."),

        ("Work only you can do", 4.2, .walkthroughFounderTask,
         "Not every task can be handed over. Talking to users is the founder's own "
         + "work, so this one is never offered as \"Run it\" — Codepet prepares it and "
         + "records what comes back, and says plainly that it cannot do it for you."),

        ("A real decision", 3.4, .convene("Should we ship the paywall before launch?"),
         "Some questions are decisions, not tasks. Convening puts one to four "
         + "departments — a priced act, ~10 credits, and the founder taps it."),

        ("A real decision", 3.2, .hold,
         "They do not agree, and the room is not allowed to pretend they do. Finance "
         + "hard-blocks on having no basis for a price; Marketing will not give up the "
         + "one day attention is free."),

        ("A real decision", 3.0, .hold,
         "It ends on the trade-off rather than a verdict — either launch with a number "
         + "you may have to change, or launch without one. Unresolved is an answer."),

        ("It remembers", 3.4, .say("Remember: we ship the trial at launch and the paywall when billing lands."),
         "Anything the founder learns can be recorded. This is the cheapest thing in the "
         + "product and the one that compounds — it is free, and every department reads it."),

        ("It remembers", 4.0, .say("What did we settle on?"),
         "And minutes later the answer quotes it back — the words that were recorded, not "
         + "a promise that they were. That is the difference between a chatbot you re-explain "
         + "your company to every morning and one that gets more useful each week."),

        ("Where the state lives", 2.8, .go(.roadmap),
         "The five surfaces are state you browse — the work itself only ever happens "
         + "in chat. The roadmap is where the beacon came from."),

        // 4.4s, not 2.6: this screen now carries nine artifacts across all eight departments,
        // and the old duration was sized for reading about one deliverable. Measured against
        // both budgets `MockFlowScriptTests` enforces — 236 characters needs 3.50s to be
        // readable even on Slow, and the tour goes 82.3s -> 84.1s against a 100s ceiling that
        // its own comment says was twice refused a raise.
        //
        // RE-CAPTIONED, not added. The walkthrough already visited the Library; a second beat
        // would be the duplication this change exists to avoid, and a test pins the count at one.
        ("Where the state lives", 4.4, .go(.library),
         "The deliverable just approved is here — and so is finished work from all eight "
         + "departments, grouped by whose it is. Every one of them traces back to a task on "
         + "the roadmap. Library is the record of what the company has actually produced."),

        ("Your company touches your code", 3.4, .mode(.developer),
         "Developer is the second door. The five surfaces do not move — they collapse "
         + "to one row so a session gets the vertical space."),

        ("Your company touches your code", 3.6, .hold,
         "With nothing linked it says so, and offers both doors: a folder on this Mac "
         + "at zero credits, or a repo in the cloud. The ceiling holds from the first run "
         + "either way — no merge, no deploy, no delete, no force-push."),

        ("Into the code", 3.2, .linkDemoFolder,
         "Developer was dormant because nothing was linked. Point it at a folder and it "
         + "wakes — the same one click the two doors offer, and from here it is bounded to "
         + "that folder at every tier."),

        ("Into the code", 3.8, .codeRun("Fix the signup validation — it rejects valid emails"),
         "Describe the change and it does not start. A change that touches more than one "
         + "file shows the plan first — that it works on your machine, that it may run "
         + "commands — and waits."),

        ("Into the code", 4.4, .confirmCodeRun,
         "That tap is the founder's. Now it names its steps out loud as it works, so what "
         + "is on screen is a process rather than a spinner — which is the only thing that "
         + "earns enough trust to let it act at all."),

        ("Into the code", 3.6, .hold,
         "The pane keeps the summary — which files, how many lines — and the diff itself "
         + "opens beside it, never over it. Review comes forward by itself: a gate behind "
         + "a click nobody makes is not a gate."),

        ("Ship it", 4.0, .approveCodeRun,
         "The diff comes to a human. Approving <b>commits to a branch and stops there</b> — "
         + "no merge, no deploy, no force-push, at any tier, ever. The worst case this "
         + "product can produce is a branch you delete."),

        ("Ship it", 3.4, .hold,
         "It landed on a branch of its own and stopped. Codepet does not open the pull "
         + "request and will not merge it — that step stays yours, which is what makes "
         + "the ceiling a ceiling and not a setting."),

        ("When it goes wrong", 4.2, .say("Are we offline right now?"),
         "The path a demo usually hides. The departments are unreachable — and the refusal "
         + "says what did NOT happen: no task started, nothing written to decisions or the "
         + "roadmap, nothing charged. Your question stays in the composer."),

        ("Where it ends", 3.0, .mode(.ask),
         "Back to Ask. Every success needed the founder's approval, and nothing was "
         + "written before it."),
    ])

    /// Numbers the beats so `id` cannot drift from position.
    private static func build(_ raw: [(String, Double, Intent, String)]) -> [Beat] {
        raw.enumerated().map { i, r in
            Beat(id: i, chapter: r.0, seconds: r.1, intent: r.2, caption: r.3)
        }
    }
}
#endif

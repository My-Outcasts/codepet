// codepet/Services/MockChat.swift
#if DEBUG
import Foundation

/// Dev-only chat stub. When the `CODEPET_MOCK_CHAT` flag is set (launch arg
/// `-CODEPET_MOCK_CHAT YES` or the UserDefaults key), `CompanyChatClient` and
/// `RunTaskClient` short-circuit to canned local responses — so the whole
/// redesigned chat experience (streaming orb, un-bubbled messages, thumbs,
/// run→produce→approve cards, nav/setup/remember chips) can be exercised with
/// ZERO Anthropic spend.
///
/// Compiled ONLY under `#if DEBUG`; the flag defaults off, so a normal build
/// still hits the real Cloud Functions. It is a KEYWORD ROUTER — the word you
/// type decides which affordance fires (see `route`), giving a deterministic
/// full-coverage test conversation:
///   "run …"       → run a real open task → inline draft card (Approve/Open/Redo)
///   "remember …"  → auto-merge a decision → "Noted" chip
///   "connect …"   → suggest enabling an off toolkit item → enable card
///   "roadmap …"   → a tappable "go to Roadmap" nav chip
///   "long …"      → a long multi-paragraph reply (rendering / scroll)
///   anything else → a normal streamed reply
///
/// Toggle from the CLI (or just relaunch with the launch arg):
///   defaults write app.murror.codepet CODEPET_MOCK_CHAT -bool YES   # on
///   defaults write app.murror.codepet CODEPET_MOCK_CHAT -bool NO    # off
enum MockChat {
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "CODEPET_MOCK_CHAT") }

    /// Decide the reply text + which `.done` action fires, from the message text
    /// and the request's own `runnable`/`envSetup` lists (so echoed ids are valid).
    private static func route(_ req: CompanyChatRequest) -> (text: String, action: ChatDoneAction) {
        let msg = req.userMessage.lowercased()

        // run → produce → approve (the core loop). Needs a runnable task.
        if msg.contains("run") || msg.contains("draft") || msg.contains("produce") {
            if let task = req.runnable.first {
                return ("On it — drafting \u{201C}\(task.title)\u{201D} for you now\u{2026}",
                        ChatDoneAction(runTaskId: task.id))
            }
            return ("You don\u{2019}t have a task I can run right now — everything\u{2019}s either done or waiting on you.",
                    ChatDoneAction())
        }

        // remember → auto-merged decision + "Noted" chip.
        if msg.contains("remember") || msg.contains("note that") {
            let fact = RememberedFact(topic: "Founder note",
                                      statement: req.userMessage.trimmingCharacters(in: .whitespacesAndNewlines))
            return ("Got it — I\u{2019}ll remember that.", ChatDoneAction(remember: [fact]))
        }

        // setup → suggest enabling an off toolkit item.
        if msg.contains("connect") || msg.contains("enable") || msg.contains("setup") || msg.contains("turn on") {
            if let tool = req.envSetup.first {
                return ("Want me to turn on \(tool.name)? Tap to enable it.",
                        ChatDoneAction(setup: SetupAction(category: tool.category, name: tool.name)))
            }
            return ("Everything in your toolkit is already on — nothing to connect.", ChatDoneAction())
        }

        // nav → a tappable "go here" chip.
        if msg.contains("roadmap") || msg.contains("go to") || msg.contains("open ") {
            return ("Here\u{2019}s your roadmap — tap to jump over.",
                    ChatDoneAction(nav: NavAction(destination: "roadmap", target: nil)))
        }

        // long → multi-paragraph rendering / scroll.
        if msg.contains("long") {
            return ("""
            Here's the fuller version. The trap at your stage isn't a lack of ideas — it's \
            spending another week refining instead of getting one real signal. So the whole \
            game right now is compressing the loop between 'I think this is true' and 'a real \
            user just showed me it's true (or not).'

            Concretely, that's three moves. First, put your value into one sentence a stranger \
            gets in five seconds and stick it somewhere public — a landing hero is fine. Second, \
            book five 20-minute calls with people who actually have the problem; you're there to \
            learn, not pitch. Third, ship the smallest thing they can touch — a rough version \
            teaches you more than a polished mock ever will.

            The reason this order matters: positioning tells you what to build, the calls tell \
            you if anyone cares, and shipping tells you the truth. Skip the middle and you'll \
            build something beautiful that no one asked for.

            Want me to draft the positioning sentence, or the outreach message for those calls?
            """, ChatDoneAction())
        }

        // default reply.
        return ("""
        Here's how I'd think about it. Your leverage right now is momentum, not polish — the \
        goal this week is one real signal from one real user, not a perfect plan.

        So: (1) write your positioning in a single sentence and put it where a stranger can \
        see it, (2) book five short calls with people who have the problem, and (3) ship the \
        smallest thing they can actually touch. Do those three and you'll know more by Friday \
        than another month of planning would tell you.

        Want me to draft the positioning line or the outreach message to get those calls booked?
        """, ChatDoneAction())
    }

    /// Non-streaming counterpart of `stream`.
    static func reply(_ req: CompanyChatRequest) async -> CompanyChatReply? {
        try? await Task.sleep(nanoseconds: 300_000_000)
        let (text, action) = route(req)
        return CompanyChatReply(text: text, runTaskId: action.runTaskId, nav: action.nav,
                                setup: action.setup, remember: action.remember)
    }

    /// Streams the routed reply word-by-word (with small delays) then a `.done`
    /// frame carrying the routed action — mirroring the real CF's SSE shape so
    /// the store's streaming path is exercised end-to-end.
    static func stream(_ req: CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> {
        let (full, action) = route(req)
        return AsyncThrowingStream { continuation in
            let task = Task.detached {
                try? await Task.sleep(nanoseconds: 500_000_000)  // "Working on it…" beat
                var chunk = ""
                for ch in full {
                    chunk.append(ch)
                    if ch == " " {
                        continuation.yield(.delta(chunk))
                        chunk = ""
                        try? await Task.sleep(nanoseconds: 45_000_000)
                    }
                }
                if !chunk.isEmpty { continuation.yield(.delta(chunk)) }
                continuation.yield(.done(model: "mock", cacheHit: false, action: action))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Canned deliverable for `RunTaskClient.run` — a `run_task_id` produces a
    /// realistic inline draft card (Approve / Open / Redo) offline, tailored to
    /// the task so demo screenshots read like genuine Codepet output.
    static func runResult(_ req: RunTaskRequest) async -> RunTaskResponse? {
        try? await Task.sleep(nanoseconds: 700_000_000)  // "producing…" beat
        let (kind, body) = deliverable(for: req.taskTitle)
        let note = req.reviseNote.map { "\n\n_Revised per your note: \($0)_" } ?? ""
        return RunTaskResponse(kind: kind, title: req.taskTitle, body: body + note, payload: nil)
    }

    /// A realistic deliverable (kind + markdown body) tailored to the task title.
    private static func deliverable(for title: String) -> (kind: String, body: String) {
        let t = title.lowercased()
        if t.contains("positioning") || t.contains("value prop") {
            return ("doc", """
            For solo founders drowning in scattered docs and stalled momentum, **Codepet** is the \
            AI cofounder that turns your company into one living workspace — it plans your next \
            move, does the work with you, and remembers every decision. Unlike a generic AI chat \
            or a stack of disconnected tools, Codepet is grounded in *your* company and acts, not \
            just answers.

            **One-liner** — Codepet is the AI cofounder that runs your company's busywork so you \
            can build.

            **Why it works**
            - Names a sharp, real pain (scattered context, no momentum).
            - Says exactly who it's for (early solo founders), not 'everyone'.
            - Draws the contrast (grounded + acts vs. generic chat).

            **Use it in**: your landing hero, the first line of your pitch, the App Store subtitle.
            """)
        }
        if t.contains("landing") || t.contains("copy") || t.contains("website") {
            return ("post", """
            **Headline** — Your AI cofounder, not another chatbot.

            **Subhead** — Codepet plans your next move, does the work with you, and remembers \
            every decision — grounded in your actual company.

            **Benefit bullets**
            - **Always knows your context.** No re-explaining — it reads your brief, roadmap, and decisions.
            - **Does the work, not just talk.** Drafts, plans, and deliverables you approve in one tap.
            - **A team of specialists.** Marketing, Engineering, and Design pets step in for their domain.

            **Primary CTA** — Start free   ·   **Secondary** — See how it works
            """)
        }
        if t.contains("waitlist") || t.contains("signup") || t.contains("sign up") {
            return ("checklist", """
            A no-backend email capture you can ship today.

            1. **Pick the tool** — a hosted form (Tally / Typeform) or a one-field section on your landing page.
            2. **Ask for one thing** — email only. Every extra field drops conversion.
            3. **Set the confirmation** — a short 'you're on the list' message + what to expect next.
            4. **Wire the storage** — form → a sheet or your Firestore `waitlist` collection.
            5. **Add a share nudge** — 'Want in sooner? Share your link.'

            **Done when**: a stranger can land, drop an email, and you can see it come through.
            """)
        }
        if t.contains("brand") || t.contains("logo") || t.contains("look") || t.contains("visual") {
            return ("doc", """
            A calm, confident visual direction you can apply everywhere.

            **Palette** — one ink (`#1f1b15`), one paper (`#f4f1ea`), one accent (a violet, `#7c3aed`). \
            Restraint reads as premium; add a second accent only when you truly need it.

            **Type** — a friendly grotesk for headers, a readable sans for body. One family, two weights beats five fonts.

            **Logo mark** — a simple, single-color glyph that survives at 16px (favicon) and in one color \
            (stamps, watermarks). Wordmark = the name set in your header weight, tightened.

            **Rule of thumb** — pick the boring, consistent option; recognizability comes from repetition, not novelty.
            """)
        }
        if t.contains("pricing") || t.contains("price") {
            return ("doc", """
            **Model** — credits, not a seat/day cap: chat feels unlimited, deliverables spend.

            - **Trial** — 7 days, ~150 credits, then it stops (no permanent free tier).
            - **Pro — $20/mo** — 800 credits included; overage auto-billed at $0.05/credit.

            **Why this shape**
            - Chat is cheap (~0.25 credit/msg) so exploring feels free; the real cost is generation.
            - One price, no BYOK — simpler to reason about and simpler to sell.

            You can change any number later — ship a price, then let real usage tell you.
            """)
        }
        if t.contains("user") || t.contains("interview") || t.contains("talk to") || t.contains("discovery") {
            return ("doc", """
            **Goal** — understand the problem, not pitch. 20 minutes each.

            **Opening** — 'I'm trying to learn, not sell. Walk me through the last time you ran into this.'

            **Core questions**
            1. When did you last hit this? What did you actually do?
            2. What's the most frustrating part — and why that part?
            3. What have you tried? What did it cost you (time or money)?
            4. If you had a magic fix, what would it do for you?

            **Close** — 'Who else should I talk to?' and ask to follow up.

            **Watch for**: stories about real behavior over opinions ('I would probably…').
            """)
        }
        // default: a crisp weekly plan.
        return ("plan", """
        A first cut to get you moving — treat it as a starting point, not the final word.

        **The move** — take '\(title)' from idea to a concrete first step this week.

        **This week**
        1. Define what 'done' looks like in a single sentence.
        2. Ship the smallest version today — rough is fine.
        3. Get one piece of real feedback before you polish anything.

        **Watch out for** — scope creep and polishing before you've validated the core.
        """)
    }

    /// A fully canned, onboarded company for `CompanyData.load` — so mock mode is
    /// self-contained (no Firestore, no real account needed) and the fan-out has a
    /// deterministic roadmap with THREE distinct runnable departments (mkt / eng /
    /// design) → "Run my next moves" fans out to 3 parallel agents, all offline.
    static func company() -> CompanyState {
        var brief = CompanyBrief()
        brief.founderName = "Mona"
        brief.projectName = "Codepet"
        brief.oneLiner = "Your AI cofounder that runs the whole company with you."
        brief.stage = "building"
        return CompanyState(brief: brief, departments: [], library: [], stage: .building,
                            companionId: "byte", onboardedAt: Date(), tasks: roadmap())
    }

    /// Canned roadmap for `CompanyData.fetchRoadmap` — a realistic mix so the
    /// board, the chat's `runnable` list (Codepet-can-do tasks), and the
    /// "needs you" landing card all have something to show offline. The three
    /// `.draft`/`.does` tasks with no deps resolve to `codepetCanDo` → runnable.
    static func roadmap() -> [RoadmapTask] {
        [
            RoadmapTask(id: "mock-positioning", title: "Draft your positioning statement",
                        detail: "One clear sentence: who it's for, what it does, why it's different.",
                        phase: .foundation, who: .draft, dept: "mkt"),
            RoadmapTask(id: "mock-landing", title: "Write your landing page copy",
                        detail: "Headline, subhead, and three benefit bullets for the waitlist page.",
                        phase: .build, who: .draft, dept: "mkt"),
            RoadmapTask(id: "mock-waitlist", title: "Set up a waitlist signup",
                        detail: "A simple email capture so early interest isn't lost.",
                        phase: .build, who: .does, dept: "eng"),
            RoadmapTask(id: "mock-brand", title: "Design your brand look",
                        detail: "A simple visual direction — colors, type, and a logo mark.",
                        phase: .foundation, who: .draft, dept: "design"),
            RoadmapTask(id: "mock-interviews", title: "Talk to 5 potential users",
                        detail: "Book and run five short discovery calls this week.",
                        phase: .find, who: .you, dept: "mkt"),
            RoadmapTask(id: "mock-pricing", title: "Decide your pricing",
                        detail: "Pick a starting price and model — you can change it later.",
                        phase: .foundation, who: .you, dept: "fin"),
        ]
    }
}
#endif

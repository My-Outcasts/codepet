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
/// NOTE: `main`'s `ChatDoneAction`/`CompanyChatReply` don't (yet) carry
/// `rePlan`/`walkthrough`/`editCode` fields (those are PR#39-only affordances
/// not present here) — the re-plan/walkthrough/edit-code keyword branches
/// below are kept for router coverage but resolve to a plain `ChatDoneAction()`
/// (text-only reply, no special action) so they compile against main's shapes.
///
/// Toggle by RELAUNCHING WITH THE LAUNCH ARG. This is not a style preference:
///
///   open <path>/codepet.app --args -CODEPET_MOCK_CHAT YES
///
/// **`defaults write app.murror.codepet CODEPET_MOCK_CHAT -bool YES` does not
/// work, and fails silently.** This file said it did until Aug 13, and it cost
/// an hour of debugging a feature that was fine.
///
/// A sandboxed container was left behind at
/// `~/Library/Containers/app.murror.codepet` from when this app WAS sandboxed
/// (`codepet.entitlements` now sets `app-sandbox` to false). `defaults`
/// resolves a bundle id THROUGH its container when one exists, so the write
/// lands in the container's plist — measured: a probe key written by
/// `defaults` appears in the container copy and not in the other one. The app,
/// unsandboxed at runtime, reads `~/Library/Preferences/app.murror.codepet.plist`
/// instead, which is also where it writes its own window frames.
///
/// So the two ends read different files, and BOTH look right in isolation:
/// `defaults read` returns 1 (it follows the same redirect it wrote through)
/// while the app sees nothing at all. Deleting the stale container would fix
/// it — it still holds an old Firestore cache and two `.codepet` jsonl files,
/// so that is a decision to make deliberately, not a cleanup to slip in.
///
/// `-CODEPET_MOCK_CHAT YES` sidesteps all of it: `NSArgumentDomain` outranks
/// every preference file and touches no disk.
enum MockChat {
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "CODEPET_MOCK_CHAT") }

    /// Decide the reply text + which `.done` action fires, from the message text
    /// and the request's own `runnable`/`envSetup` lists (so echoed ids are valid).
    private static func route(_ req: CompanyChatRequest) -> (text: String, action: ChatDoneAction) {
        let msg = req.userMessage.lowercased()

        // summarize → a grounded read of where the project stands (guided flow start).
        if msg.contains("summar") {
            return ("""
            Here\u{2019}s where Codepet stands. You\u{2019}re **building** \u{2014} the product exists, and the job \
            now is getting it in front of real users. Your foundation is mostly in place; what\u{2019}s \
            missing is the launch surface (landing, waitlist) and the go-to-market basics (pricing, \
            outreach).

            **The one thing that matters this week:** one real signal from one real user \u{2014} \
            everything on your roadmap should serve that.

            Ask me **\u{201C}What should I focus on now?\u{201D}** and I\u{2019}ll point you at the single next move.
            """, ChatDoneAction())
        }

        // replan/regenerate → keyword coverage kept for the router, but `main`
        // has no `rePlan` action field, so this resolves to a plain reply.
        if msg.contains("replan") || msg.contains("re-plan") || msg.contains("re plan")
            || msg.contains("regenerate") {
            return ("On it — re-planning your roadmap for where you are now.", ChatDoneAction())
        }

        // shares a 4+ char word with the message (so "run privacy"/"run faq" hit that
        // department's task); a bare "run it" falls back to the first (the next move).
        // The reply previews the NEXT step so the guided flow keeps moving.
        if msg.contains("run") || msg.contains("draft") || msg.contains("produce") {
            let picked = req.runnable.first { r in
                r.title.lowercased().split(whereSeparator: { !$0.isLetter }).contains { w in
                    w.count >= 4 && msg.contains(String(w))
                }
            } ?? req.runnable.first
            if let task = picked {
                let after = req.runnable.first { $0.id != task.id }
                let nextLine = after.map {
                    "\n\nOnce you approve this, your next move is **\($0.title)** (\(deptName(forRunnableId: $0.id))) \u{2014} ask \u{201C}what\u{2019}s next?\u{201D}"
                } ?? "\n\nThat\u{2019}s your last open move \u{2014} nice work."
                return ("On it \u{2014} drafting \u{201C}\(task.title)\u{201D} for you now\u{2026}\(nextLine)",
                        ChatDoneAction(runTaskId: task.id))
            }
            return ("You don\u{2019}t have a task I can run right now — everything\u{2019}s either done or waiting on you.",
                    ChatDoneAction())
        }

        // focus / what's next → suggest ONE specific next task in its department, with
        // a why + an offer to run it. The core of the guided, one-at-a-time flow.
        if msg.contains("focus") || msg.contains("what should i") || msg.contains("next")
            || msg.contains("guide me") || msg.contains("where do i start") {
            if let next = req.runnable.first {
                let dept = deptName(forRunnableId: next.id)
                let after = req.runnable.dropFirst().first
                let afterLine = after.map { "\n\nAfter that, the next step will be **\($0.title)**." } ?? ""
                return ("""
                Focus on one thing: **\(next.title)** \u{2014} that\u{2019}s a **\(dept)** move, and it\u{2019}s the \
                highest-leverage next step on your roadmap right now.

                Say **\u{201C}run it\u{201D}** and I\u{2019}ll draft it with you.\(afterLine)
                """, ChatDoneAction())
            }
            return ("You\u{2019}re all caught up \u{2014} nothing I can run right now. Everything\u{2019}s either done or waiting on you.",
                    ChatDoneAction())
        }

        // walkthrough → keyword coverage kept for the router, but `main` has no
        // `walkthrough` action field, so this resolves to a plain reply.
        if msg.contains("walkthrough") {
            return ("Happy to guide you through it step by step.", ChatDoneAction())
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

        // edit code → keyword coverage kept for the router, but `main` has no
        // `editCode` action field (no local coding-agent run wired here), so
        // this resolves to a plain reply.
        if msg.contains("edit code") || msg.contains("change the code") || msg.contains("code:") {
            return ("On it — I'll make that change on your machine and show you the diff.", ChatDoneAction())
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

    /// Department display name for a runnable task id (mock roadmap lookup) — used
    /// by the guided flow to name the department a suggested task belongs to.
    private static func deptName(forRunnableId id: String) -> String {
        guard let key = roadmap().first(where: { $0.id == id })?.dept,
              let name = DepartmentCatalog.find(key)?.name else { return "your team" }
        return name
    }

    /// Non-streaming counterpart of `stream`.
    static func reply(_ req: CompanyChatRequest) async -> CompanyChatReply? {
        try? await Task.sleep(nanoseconds: 300_000_000)
        let (raw, action) = route(req)
        // Chat bubbles render plain text (not markdown), so drop bold markers.
        let text = raw.replacingOccurrences(of: "**", with: "")
        return CompanyChatReply(text: text, runTaskId: action.runTaskId, nav: action.nav,
                                setup: action.setup, remember: action.remember)
    }

    /// Streams the routed reply word-by-word (with small delays) then a `.done`
    /// frame carrying the routed action — mirroring the real CF's SSE shape so
    /// the store's streaming path is exercised end-to-end.
    static func stream(_ req: CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> {
        let (rawFull, action) = route(req)
        // Chat bubbles render plain text (not markdown), so drop bold markers.
        let full = rawFull.replacingOccurrences(of: "**", with: "")
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
        if t.contains("outreach") || t.contains("cold") || t.contains("sales") || t.contains("email") {
            return ("email", """
            **Subject** — a quick idea for {{company}}

            Hi {{name}} — I'll keep this short. I'm building Codepet, an AI cofounder that runs a \
            solo founder's whole company — it plans the next move, does the work with you, and \
            remembers every decision.

            I noticed {{company}} is {{specific observation}} — that's exactly the kind of momentum \
            problem it's built for. Worth a 15-minute look?

            No pitch deck, just a live demo. Reply "yes" and I'll send a time.

            — Mona

            _Tip: keep the ask tiny (a 15-min look), personalize line 2, and cut everything else._
            """)
        }
        if t.contains("faq") || t.contains("support") || t.contains("help center") {
            return ("doc", """
            The first questions new users ask — answer them before they have to write in.

            **What is Codepet?** An AI cofounder that runs your company's busywork — it plans, does \
            the work with you, and remembers your decisions.

            **Do I need to know how to code?** No. Codepet drafts and produces; you approve.

            **Is my data private?** Your company context is yours; we don't train on it.

            **How is it priced?** A credit model — chat feels free, deliverables spend. Trial, then Pro.

            **Can I cancel anytime?** Yes, one tap in Settings — no email required.

            _Add each real question you get to this list; it doubles as your objection-handling script._
            """)
        }
        if t.contains("deploy") || t.contains("release") || t.contains("ops") {
            return ("checklist", """
            Ship a release the same safe way every time.

            1. **Green build** — tests pass locally and in CI.
            2. **Version bump** — tag the release; write a one-line changelog.
            3. **Backup / migration** — run pending DB migrations; confirm a rollback path.
            4. **Deploy to staging** — smoke-test the critical flow end to end.
            5. **Promote to prod** — deploy, then re-run the smoke test live.
            6. **Watch** — check errors/latency for 15 minutes; keep the rollback command ready.

            **Done when**: the critical flow works in prod and dashboards are clean.
            """)
        }
        if t.contains("privacy") || t.contains("policy") || t.contains("legal") || t.contains("terms") {
            return ("legal", """
            _Plain-language draft — have a lawyer review before you publish._

            **Privacy Policy — Codepet**

            **What we collect** — your account email, the company context you enter, and basic usage \
            analytics. We do **not** sell your data or train public models on your company content.

            **Why** — to run the product for you (generate work, remember decisions) and to keep it reliable.

            **Your choices** — export or delete your data anytime from Settings; deleting your account \
            removes your company content.

            **Sharing** — only with the infrastructure providers needed to run the service (hosting, \
            auth, payments), under their own terms.

            **Contact** — privacy@codepet.app for any request.
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
    /// "needs you" landing card all have something to show offline.
    ///
    /// The `dependsOn` graph is deliberate, not decorative: with it empty, EVERY task
    /// qualified as an entry task, so `RoadmapLayoutEngine` drew zero dependency edges and
    /// fanned the root out to all nine — the board could not exercise its own flow rendering
    /// at all. This graph is shaped to cover each routing case exactly once:
    ///
    ///   - The depless tasks are the FIND four (`interviews` + the three runnable ones), so
    ///     the root draws FOUR edges, not nine. It drew one until Aug 5, when `.find` gained
    ///     runnable work; four is still a fan-out the board must route rather than the
    ///     degenerate nine-way spray this graph exists to avoid, and it is what a real
    ///     scaffolded roadmap looks like — an opening phase of parallel research. If you are
    ///     testing single-entry routing specifically, drop the three and expect the fan-out
    ///     and in-chat runs to stop working (`MockFixtureRunnableTests` will say so).
    ///   - `interviews → {brand, landing, pricing}` touches the beacon, so these are the
    ///     `critical` edges (halo + solid) — previously unreachable in the mock.
    ///   - `brand → landing` is an IN-COLUMN edge → `sideElbow`'s left-gutter hook.
    ///   - `landing → outreach`, `pricing → faq`, `waitlist → deploy` share a dept lane →
    ///     2-point straight runs.
    ///   - `{landing, pricing} → outreach` is a fan-IN: two sources, one target.
    ///   - `landing → privacy` SKIPS the BUILD column, and both sit on the mkt/legal lane
    ///     (row 1) — so its horizontal leg passes behind `outreach`. Kept on purpose: it is
    ///     the reproduction for the routing flaw where a skip-level edge reads as a chain.
    ///
    /// NOTE the phase window, not these deps, is what locks the downstream cards:
    /// `interviews` is `who: .you`, so `RoadmapGating.openPhases` stops at `.find` and
    /// `RoadmapEngine.status` blocks all eight later tasks regardless of `dependsOn`.
    ///
    /// That silently broke the fixture's whole purpose, and the note this replaces recorded it
    /// as a known dead end rather than a bug: with every task either founder-owned or behind
    /// the window, NOTHING was `codepetCanDo`, so the client sent an empty `runnable` list and
    /// the mock router answered "you don't have a task I can run right now" to every "run the
    /// landing page". No execute log, no draft, and no 3-agent fan-out — the three surfaces
    /// this fixture exists to demonstrate. Reported from the app on Aug 5 as "the UI for
    /// showing which agents are running still isn't working": it was the roadmap, not the UI.
    ///
    /// The fix is what that note called a separate call — three Codepet-owned tasks INSIDE
    /// `.find`, in three distinct departments. Inside the open window they are `codepetCanDo`
    /// while `interviews` keeps holding the later phases shut, so the fixture demonstrates
    /// both halves at once: runnable work in the open phase, and the gating that the founder's
    /// own step imposes on everything after it. Three distinct departments because
    /// `RoadmapEngine.nextMoves` takes the first runnable task per DEPARTMENT, so a fan-out
    /// of three needs three of them.
    static func roadmap() -> [RoadmapTask] {
        [
            // ── FIND: runnable now (the open phase) ────────────────────────────────
            // Each title carries the keyword the mock router matches on ("run competitors").
            RoadmapTask(id: "mock-competitors", title: "Scan five competitors' positioning",
                        detail: "What they claim, who they target, and where the gap is.",
                        phase: .find, who: .draft, dept: "mkt"),             // run competitors
            RoadmapTask(id: "mock-personas", title: "Sketch two early user personas",
                        detail: "Who feels this pain most, and what they do today instead.",
                        phase: .find, who: .draft, dept: "design"),          // run personas
            RoadmapTask(id: "mock-market", title: "Size the market you're entering",
                        detail: "A rough top-down number you can sanity-check later.",
                        phase: .find, who: .draft, dept: "fin"),             // run market
            // ── Later phases: one task per department (all 8) so every department's card
            // is testable, and all of them BLOCKED behind `interviews` — which is the
            // gating the founder should be able to see and feel, not a fixture defect.
            // Each title carries a keyword ("run <keyword>") the mock router matches.
            RoadmapTask(id: "mock-brand", title: "Design your brand look",
                        detail: "A simple visual direction — colors, type, and a logo mark.",
                        phase: .foundation, who: .draft,
                        dependsOn: ["mock-interviews"], dept: "design"),     // run brand
            RoadmapTask(id: "mock-landing", title: "Write your landing page copy",
                        detail: "Headline, subhead, and three benefit bullets.",
                        phase: .foundation, who: .draft,
                        // + brand: the copy follows the visual direction. Same column → sideElbow.
                        dependsOn: ["mock-interviews", "mock-brand"], dept: "mkt"),  // run landing
            RoadmapTask(id: "mock-pricing", title: "Draft a simple pricing plan",
                        detail: "A starting price + model you can change later.",
                        phase: .foundation, who: .draft,
                        dependsOn: ["mock-interviews"], dept: "fin"),        // run pricing
            RoadmapTask(id: "mock-waitlist", title: "Set up a waitlist signup",
                        detail: "A simple email capture so early interest isn't lost.",
                        phase: .build, who: .does,
                        // There has to be a page before there's a signup on it.
                        dependsOn: ["mock-landing"], dept: "eng"),           // run waitlist
            RoadmapTask(id: "mock-outreach", title: "Write a cold outreach email",
                        detail: "A short first-touch email to a potential customer.",
                        phase: .build, who: .draft,
                        // Fan-IN: you can't pitch without both a page and a price.
                        dependsOn: ["mock-landing", "mock-pricing"], dept: "sales"),  // run outreach
            RoadmapTask(id: "mock-faq", title: "Draft a support FAQ",
                        detail: "Answers to the first questions new users will ask.",
                        phase: .build, who: .draft,
                        dependsOn: ["mock-pricing"], dept: "support"),       // run faq
            RoadmapTask(id: "mock-deploy", title: "Set up a deploy checklist",
                        detail: "The steps to ship a release safely, every time.",
                        phase: .ship, who: .does,
                        dependsOn: ["mock-waitlist"], dept: "ops"),          // run deploy
            RoadmapTask(id: "mock-privacy", title: "Draft a privacy policy",
                        detail: "A plain-language policy covering what you collect and why.",
                        phase: .ship, who: .draft,
                        // SKIPS BUILD on purpose — the reproduction for the skip-level
                        // routing flaw (see the graph note above). Do not "tidy" this away.
                        dependsOn: ["mock-landing"], dept: "legal"),         // run privacy
            // A "needs you" task so the landing card + roadmap show that state too.
            RoadmapTask(id: "mock-interviews", title: "Talk to 5 potential users",
                        detail: "Book and run five short discovery calls this week.",
                        phase: .find, who: .you, dept: "mkt"),
        ]
    }
}
#endif

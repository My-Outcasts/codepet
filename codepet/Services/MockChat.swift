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
/// The failure `forcesFailure` injects. Its own type so a reader of a log can tell
/// a deliberately mocked outage from a real decoding error.
enum MockChatFailure: Error { case unreachable }

enum MockChat {
    /// The master switch. `CODEPET_MOCK_FLOW` implies it, so the full-flow demo
    /// is ONE launch argument rather than two that must agree — two flags where
    /// one is meaningless without the other is a state you can get half-right.
    static var enabled: Bool { PrototypeMode.isOn }

    /// `-CODEPET_MOCK_FLOW YES` — start at the cold open and walk the whole
    /// product, with a fake company built from whatever gets typed in.
    ///
    /// Plain mock mode boots an ALREADY-ONBOARDED company, which is what makes
    /// chat and engineering reachable with no spend — and it means onboarding
    /// is the one stretch of the product a mock has never been able to show.
    /// This flag closes that: `CompanyData.load` reports "not onboarded yet"
    /// until the founder finishes, `enrichBrief` and `fetchRoadmap` answer from
    /// fixtures instead of the network, and the shell that follows is the same
    /// populated company plain mock mode has always given.
    /// `CODEPET_MOCK_AUTOPLAY` implies this, for the same reason this implies
    /// `enabled`: the autoplaying walkthrough sends chat turns and runs a task on
    /// its own, unattended. Without the fixtures behind it, it would drive the REAL
    /// Cloud Functions and spend real credits with nobody watching the ledger — and
    /// two flags where one is meaningless alone is a state you can get half-right.
    static var flowEnabled: Bool { PrototypeMode.startsAtColdOpen }

    /// Flipped once onboarding completes, so the next `load` in this process
    /// returns the finished company rather than sending the founder back
    /// through the cold open.
    ///
    /// Process-lifetime, not persisted, and deliberately so: relaunching with
    /// the flag is how you get the first-run flow again. A persisted "seen"
    /// flag would make the demo a one-shot, and the whole point is walking it
    /// repeatedly while judging the copy.
    nonisolated(unsafe) static var flowOnboarded = false

    /// The brief the founder actually typed during the flow demo.
    ///
    /// Without it the demo forgets: `CompanyData.load` answers every hydrate
    /// after onboarding with `company()`, whose brief is hardcoded — so an
    /// account switch or a sign-out would quietly replace the founder's project
    /// with Codepet's, mid-walkthrough, with nothing saying why.
    nonisolated(unsafe) static var flowBrief: CompanyBrief?

    /// What the canned copy calls the product.
    ///
    /// Every deliverable and reply below is written with a `{{product}}` token
    /// rather than a name, because a demo that talks about Codepet while the
    /// founder is onboarding something else is a demo they have to translate in
    /// their head — and the first thing they will conclude is that the fixture
    /// ignored what they typed.
    ///
    /// One substitution point, not thirteen interpolations: the token survives
    /// being copied into new canned text, an interpolation has to be remembered
    /// each time.
    static var productName: String {
        let typed = (flowBrief?.projectName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        return DemoProject.current.brief.projectName ?? "Codepet"
    }

    /// Fill `{{product}}` in any canned string.
    static func fill(_ text: String) -> String {
        text.replacingOccurrences(of: "{{product}}", with: productName)
    }

    /// `{{title}}` as well as `{{product}}`. The catch-all deliverable used to interpolate the
    /// task title directly, which is what kept the table from being plain values.
    static func fill(_ text: String, title: String) -> String {
        fill(text).replacingOccurrences(of: "{{title}}", with: title)
    }

    /// Decide the reply text + which `.done` action fires, from the message text
    /// and the request's own `runnable`/`envSetup` lists (so echoed ids are valid).
    /// The most recent decision the founder has locked in, read back out of the
    /// context the client already composes.
    ///
    /// `Decisions.composeDecisions` renders them as `- topic: statement` lines, so
    /// the mock can quote one without inventing it — which is the whole point. Use
    /// case 6 is "stay consistent over weeks", and its success signal is that a
    /// captured fact CHANGES a later answer. A canned reply saying "I read your
    /// decisions" demonstrates nothing: it reads identically whether or not one was
    /// ever recorded.
    private static func lockedDecision(in context: String) -> String? {
        guard let header = context.range(of: "Decisions the founder has locked in") else { return nil }
        for line in context[header.upperBound...].split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("- ") else { continue }
            let body = String(t.dropFirst(2))
            // `- topic: statement` — the statement is the part worth quoting back.
            if let colon = body.firstIndex(of: ":") {
                let statement = body[body.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if !statement.isEmpty { return statement }
            }
            return body
        }
        return nil
    }

    private static func route(_ req: CompanyChatRequest) -> (text: String, action: ChatDoneAction) {
        let msg = req.userMessage.lowercased()

        // A lookup, when something has actually been decided → quote it back.
        // Placed FIRST so it beats the generic fallthrough, and gated on a real
        // recorded decision so it can never claim one that does not exist.
        if msg.contains("settle") || msg.contains("decide") || msg.contains("consistent"),
           let decision = lockedDecision(in: req.context) {
            return ("""
            From your decisions — **\(decision)** — that still holds this week, and nothing on the \
            roadmap contradicts it.

            That is the whole point of recording it: every department reads the same line before it \
            answers, so you are not re-litigating it on Thursday.
            """, ChatDoneAction())
        }

        // summarize → a grounded read of where the project stands (guided flow start).
        if msg.contains("summar") {
            return ("""
            Here\u{2019}s where {{product}} stands. You\u{2019}re **building** \u{2014} the product exists, and the job \
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

        // Department-flavoured reply — the composer's department chip armed this turn, so
        // the pet that signs the bubble should also SOUND like that department. Without
        // this, routing lands nova · Marketing on the header and the generic copy in the
        // body: the right pet shows up and then says nothing only that pet would say.
        //
        // Placed LAST, immediately before the generic fallthrough, on purpose. Every
        // branch above is a scripted beat the guided flow, the autoplay script and their
        // tests depend on word-for-word, so an armed department must not change what
        // "summarize" or "run it" answers — only what an otherwise-generic turn answers.
        //
        // Gated on a department with a COMPANION rather than merely a catalog entry:
        // `product` resolves in `DepartmentCatalog` and has no pet, and `actingSpecialist`
        // already declines to hand those turns off. Falling through to byte here keeps the
        // words and the name on the bubble telling the same story.
        if let key = req.deptKey, DepartmentCompanions.companionId(for: key) != nil,
           let specialist = departmentReply(for: key) {
            return (specialist, ChatDoneAction())
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

    /// A short, in-character answer per department, for a turn the founder armed with the
    /// composer's department chip.
    ///
    /// Each one is written against THIS fixture's board (`roadmap()`) rather than against
    /// the department in the abstract — the demo's claim is that the specialist knows the
    /// company, and a reply that would read identically for any company disproves it in
    /// one sentence. Returns nil for a department with no copy, which falls the turn back
    /// to the generic reply rather than answering with a blank bubble.
    private static func departmentReply(for deptKey: String) -> String? {
        switch deptKey {
        case "eng":
            return """
            The only engineering on your board is **Set up a waitlist signup**, and it is \
            waiting on the landing page — there is nowhere to put the form yet. When it \
            unblocks, keep it a hosted form writing into one collection; collecting an email \
            does not need a backend, and building one now is a week you spend not shipping.

            Want me to sketch the smallest version that would actually capture a signup today?
            """
        case "design":
            return """
            Decide who is looking before you decide what they see. **Sketch two early user \
            personas** is open right now and it is the cheaper half of this — **Design your \
            brand look** is downstream of it, because a visual direction is an argument aimed \
            at someone specific.

            Give me the two people and I will make the colors and type argue for them.
            """
        case "mkt":
            return """
            Your bottleneck is the sentence, not the channel. **Scan five competitors' \
            positioning** is open now, and the gap it finds is exactly what **Write your \
            landing page copy** needs: one line a stranger understands in five seconds.

            Say "run competitors" and I will do the scan and hand you the sentence it points at.
            """
        case "sales":
            return """
            At your stage you land users one conversation at a time — a campaign has nothing \
            to convert yet. **Write a cold outreach email** is on the board but waits on both \
            the landing page and a price, and that order is right: a stranger needs somewhere \
            to look and something to say yes to.

            Until then your five discovery calls are the pipeline. Ask for one intro at the \
            end of every single one.
            """
        case "support":
            return """
            You have no users yet, which makes support cheap to get right and expensive to \
            retrofit. **Draft a support FAQ** sits behind pricing on your board for a reason — \
            the first questions are always what is this, what does it cost, and can I cancel.

            Write those answers once and they double as your objection-handling script on the \
            discovery calls.
            """
        case "fin":
            return """
            Numbers before vibes. **Size the market you're entering** is open right now, and it \
            is a top-down sanity check you can finish in an hour — not a fundraising slide, so \
            do not spend a week on it.

            Then **Draft a simple pricing plan**, because a price is the first thing that makes \
            interest cost something. Ship a number you are allowed to change.
            """
        case "ops":
            return """
            Operations is the plumbing that stops you from being the plumbing. **Set up a \
            deploy checklist** is on your board behind the waitlist, and the whole point of it \
            is that shipping stops needing your full attention — same steps, same order, every \
            release.

            Write it the first time you deploy by hand, while you still remember what you forgot.
            """
        case "legal":
            return """
            Legal here is cheap insurance bought before you need it. **Draft a privacy policy** \
            is on your board, and at your size it is four honest paragraphs: what you collect, \
            why, who else sees it, and how someone deletes it.

            Draft it in plain language now and have a lawyer read it before you take money. Do \
            not copy a competitor's — you will inherit claims about a company that is not yours.
            """
        default:
            return nil
        }
    }

    /// Department display name for a runnable task id (mock roadmap lookup) — used
    /// by the guided flow to name the department a suggested task belongs to.
    private static func deptName(forRunnableId id: String) -> String {
        guard let key = roadmap().first(where: { $0.id == id })?.dept,
              let name = DepartmentCatalog.find(key)?.name else { return "your team" }
        return name
    }

    /// Non-streaming counterpart of `stream`.
    /// The one word that makes a mocked turn FAIL.
    ///
    /// Deliberately a real failure rather than a canned "this is what an outage looks
    /// like" reply: returning nil here and throwing from `stream` drives the store's
    /// actual fallback, so the walkthrough shows the copy a founder would really get
    /// during an outage — and the beat regression-tests that path instead of
    /// illustrating it. A fixture that merely *depicts* a refusal can drift from the
    /// refusal the app performs, which is the whole failure mode this session kept
    /// running into.
    static func forcesFailure(_ message: String) -> Bool {
        message.lowercased().contains("offline")
    }

    static func reply(_ req: CompanyChatRequest) async -> CompanyChatReply? {
        try? await Task.sleep(nanoseconds: 300_000_000)
        if forcesFailure(req.userMessage) { return nil }
        let (raw, action) = route(req)
        // Chat bubbles render plain text (not markdown), so drop bold markers.
        let text = fill(raw).replacingOccurrences(of: "**", with: "")
        return CompanyChatReply(text: text, runTaskId: action.runTaskId, nav: action.nav,
                                setup: action.setup, remember: action.remember)
    }

    /// Streams the routed reply word-by-word (with small delays) then a `.done`
    /// frame carrying the routed action — mirroring the real CF's SSE shape so
    /// the store's streaming path is exercised end-to-end.
    static func stream(_ req: CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> {
        if forcesFailure(req.userMessage) {
            // Throw rather than finish empty: an empty stream reads as a completed
            // turn that said nothing, and the store would seal it as a blank reply
            // instead of falling back.
            return AsyncThrowingStream { $0.finish(throwing: MockChatFailure.unreachable) }
        }
        let (rawFull, action) = route(req)
        // Chat bubbles render plain text (not markdown), so drop bold markers.
        let full = fill(rawFull).replacingOccurrences(of: "**", with: "")
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
        let entry = DemoProject.current.deliverable(for: req.taskTitle)
        let note = req.reviseNote.map { "\n\n_Revised per your note: \($0)_" } ?? ""
        // DECODED, not built memberwise: `SitePayload.init(from:)` hard-decodes six anchor fields
        // and throws when any is absent, so a fixture that would render a broken page fails here
        // rather than on screen. `payload` stayed nil until 2026-09-03, which is why no run could
        // produce a website at all.
        let payload = entry.payloadJSON.flatMap {
            try? JSONDecoder().decode(DeliverablePayload.self, from: Data($0.utf8))
        }
        return RunTaskResponse(kind: entry.kind, title: req.taskTitle,
                               body: fill(entry.body + note, title: req.taskTitle),
                               payload: payload)
    }
    /// A fully canned, onboarded company for `CompanyData.load` — so mock mode is
    /// self-contained (no Firestore, no real account needed) and the fan-out has a
    /// deterministic roadmap with THREE distinct runnable departments (mkt / eng /
    /// design) → "Run my next moves" fans out to 3 parallel agents, all offline.
    static func company() -> CompanyState {
        // The founder's own brief wins whenever the flow demo captured one.
        // Falling back to Codepet's here — as this did until a founder
        // onboarded something else and watched their project get replaced on
        // the next hydrate — makes the fixture look like it ignored them.
        // The brief now comes from the SELECTED demo project rather than a literal, so the
        // fixture can be a company other than Codepet.
        var brief = flowBrief ?? DemoProject.current.brief
        if (brief.stage ?? "").isEmpty { brief.stage = "building" }
        return CompanyState(brief: brief, departments: [], library: [], stage: .building,
                            companionId: "byte", onboardedAt: Date(), tasks: roadmap())
    }

    /// An empty company, so `needsOnboarding` is true and the cold open runs.
    ///
    /// `onboardedAt` nil AND a brief with no signal — `needsOnboarding` checks
    /// both, so returning a blank brief with a stamp (or a stamped brief with
    /// no fields) would silently land in the shell instead.
    static func preOnboardingCompany() -> CompanyState {
        CompanyState(brief: CompanyBrief(), departments: [], library: [],
                     stage: .idea, companionId: "byte", onboardedAt: nil, tasks: [])
    }

    /// What `enrichBrief` would have filled in, filled in locally.
    ///
    /// Only touches fields the founder left blank, which is what the real
    /// enricher is for — a mock that overwrote what they typed would make step
    /// 7 show someone else's project back to them, and the reveal is the
    /// moment the whole onboarding is judged on.
    static func enrich(_ brief: CompanyBrief) -> CompanyBrief {
        /// Blank and absent are the same thing to the enricher: a founder who
        /// tabbed past a field and one who typed spaces into it both left it
        /// empty, and the real enricher fills both.
        func blank(_ s: String?) -> Bool {
            (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        var b = brief
        let name = (b.projectName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = name.isEmpty ? "this product" : name
        if blank(b.oneLiner) {
            b.oneLiner = "\(subject) — the thing you're building, in one line."
        }
        if blank(b.audience) {
            b.audience = "Early solo founders shipping their first product"
        }
        if blank(b.problem) {
            b.problem = "Context is scattered across tools, so momentum stalls between sessions."
        }
        if blank(b.goal) {
            b.goal = "Get one real signal from one real user this week."
        }
        return b
    }


    /// A realistic deliverable (kind + markdown body) tailored to the task title.
    /// The selected demo project decides what a run produces. This was a 130-line
    /// `if t.contains(...)` chain of Codepet copy; it is now a table per project, and the
    /// chain's order is preserved in `DemoProject.codepet` because that order is load-bearing.
    private static func deliverable(for title: String) -> (kind: String, body: String) {
        let d = DemoProject.current.deliverable(for: title)
        return (d.kind, d.body)
    }

    /// The selected demo project's board. The graph and its routing-case notes moved with it.
    static func roadmap() -> [RoadmapTask] { DemoProject.current.tasks }
}
#endif

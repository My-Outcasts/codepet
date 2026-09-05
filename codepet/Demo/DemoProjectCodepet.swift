// codepet/Demo/DemoProjectCodepet.swift
#if DEBUG
import Foundation

/// Codepet demoing Codepet — the fixture content as it stood before `DemoProject` existed.
///
/// **Moved verbatim, and that is the point.** This instance is the regression gate for the
/// extraction: `DemoProject.current` defaults to it, so every suite written against the old
/// literals (`MockFixtureRunnableTests`, `PrototypeParityTests`, `MockFlowTests`,
/// `MockVirtualCompanyTests`) passes unedited. Any behaviour change here is a bug, not a tidy-up.
///
/// The deliverable table below was an `if t.contains(...)` chain in `MockChat`. **Its order is
/// load-bearing** — the specific branches ran before the catch-all, so reordering silently
/// changes which body a title resolves to. The entries keep the chain's order and each entry's
/// `keywords` are that branch's `contains` terms.
extension DemoProject {

    static let codepet = DemoProject(
        id: "codepet",
        brief: {
            var b = CompanyBrief()
            b.founderName = "Mona"
            b.projectName = "Codepet"
            b.oneLiner = "Your AI cofounder that runs the whole company with you."
            b.stage = "building"
            return b
        }(),
        tasks: codepetTasks,
        deliverables: codepetDeliverables,
        departmentReplies: DemoProject.codepetDepartmentReplies,
        roomFrames: codepetRoomFrames(ask:)
    )

    /// Canned roadmap — a realistic mix so the board, the chat's `runnable` list and the
    /// "needs you" landing card all have something to show offline.
    ///
    /// The `dependsOn` graph is deliberate, not decorative: with it empty, EVERY task qualified
    /// as an entry task, so `RoadmapLayoutEngine` drew zero dependency edges and fanned the root
    /// out to all nine — the board could not exercise its own flow rendering at all. The graph is
    /// shaped to cover each routing case exactly once; see the notes inline.
    ///
    /// Three Codepet-owned tasks sit INSIDE `.find` so the fan-out has three distinct
    /// departments to run — `RoadmapEngine.nextMoves` takes the first runnable task per
    /// DEPARTMENT, so a fan-out of three needs three of them.
    private static var codepetTasks: [RoadmapTask] {
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

    /// The room, without the network. Frames are wire JSON decoded by the real
    /// `VirtualCompanyEvent.from(frame:)` — a fixture built from Swift values cannot catch a
    /// renamed wire key, while this one fails loudly the moment the contract and the client
    /// disagree. `docs/superpowers/specs/virtual-company-sse-contract.md` is the authority.
    ///
    /// Written against that contract's nine rendering rules. The two that bite a fixture
    /// hardest: **rule 8** (no artificial delay — every frame is yielded at once, because the
    /// thing worth watching is the disagreement, not a progress bar) and **rule 2** (never
    /// collapse the positions into one "we agree" paragraph — so this room genuinely disagrees
    /// and ends `unresolved: true`, which rule 6 calls a valid outcome rather than an error).
    private static func codepetRoomFrames(ask: String) -> [SSEFrame] {
        [
            SSEFrame(event: "run_started", data: #"{"run_id":"mock-room-1"}"#),

            SSEFrame(event: "routing", data: """
            {"decision":"multi_agent",
             "agents":["finance","marketing","engineering"],
             "real_question":\(json(ask)),
             "request_type":"decision",
             "reason_per_agent":{
               "finance":"It changes when revenue starts and what the trial costs.",
               "marketing":"A paywall at launch changes the launch story itself.",
               "engineering":"Billing is the longest pole; the date moves with it."},
             "excluded":{
               "design":"No surface changes either way at this stage.",
               "legal":"No new terms until money actually moves."},
             "missing_info":[],
             "agent_meta":[
               {"agent_id":"finance","department_key":"fin"},
               {"agent_id":"marketing","department_key":"mkt"},
               {"agent_id":"engineering","department_key":"eng"}]}
            """),

            SSEFrame(event: "agent_start", data: #"{"agent_id":"finance","department_key":"fin"}"#),
            SSEFrame(event: "agent_position", data: """
            {"agent_id":"finance","department_key":"fin","position":{
              "stance":"do_not_proceed",
              "position":"Ship the paywall after launch, not before it.",
              "reasoning":"Nobody has paid yet, so there is no price to defend — only a guess to defend. Billing before a single conversation with a paying founder means building the wrong meter and then charging for it.",
              "evidence_needed":["Five founders who say what they would pay for","One week of real usage per account"],
              "risks_i_own":["Revenue starts later","Trial abuse for a few weeks"],
              "confidence":4,
              "cost_to_my_dept":"A delayed revenue start, which is recoverable.",
              "hard_blocker":"No price can be set before anyone has used the thing."}}
            """),

            SSEFrame(event: "agent_start", data: #"{"agent_id":"marketing","department_key":"mkt"}"#),
            SSEFrame(event: "agent_position", data: """
            {"agent_id":"marketing","department_key":"mkt","position":{
              "stance":"proceed",
              "position":"Launch with the paywall visible, even if generous.",
              "reasoning":"A launch is the only day the product gets free attention. A price on the page is what makes it a product rather than a demo, and the story is far harder to tell twice.",
              "evidence_needed":["Competitor pricing pages at launch"],
              "risks_i_own":["Fewer signups on day one"],
              "confidence":4,
              "cost_to_my_dept":"A smaller top of funnel on the loudest day of the year.",
              "hard_blocker":null}}
            """),

            SSEFrame(event: "agent_start", data: #"{"agent_id":"engineering","department_key":"eng"}"#),
            SSEFrame(event: "agent_position", data: """
            {"agent_id":"engineering","department_key":"eng","position":{
              "stance":"proceed_with_conditions",
              "position":"Billing can be ready, but it is the longest pole on the board.",
              "reasoning":"Stripe plus the credit meter is the one piece with no honest shortcut. It can land by the freeze if nothing else takes its slot.",
              "evidence_needed":["A frozen credit-accounting rule"],
              "risks_i_own":["The freeze date","A meter that undercounts and has to be reissued"],
              "confidence":3,
              "cost_to_my_dept":"Everything else on the board slips behind it.",
              "hard_blocker":null}}
            """),

            SSEFrame(event: "conflicts", data: """
            {"conflicts":[
              {"a":"finance","b":"marketing","kind":"BLOCKER",
               "reason":"Finance will not set a price before anyone has used the product; Marketing will not launch without one."},
              {"a":"engineering","b":"marketing","kind":"TENSION",
               "reason":"Billing at launch consumes the slot the launch itself needs."}]}
            """),

            // Rule 4 lives on this frame: each side's `what_would_change_my_mind` is
            // what teaches that disagreement is settled by evidence, not authority.
            SSEFrame(event: "negotiation_round", data: """
            {"round":1,"turns":[
              {"agent":"finance",
               "precise_disagreement":"Marketing wants a number on the page; I have no basis for the number.",
               "what_would_change_my_mind":"Five founders telling us what they would pay, before the page goes up.",
               "proposal":"Launch with the trial and a stated price, and take no card for two weeks.",
               "resolved":false},
              {"agent":"marketing",
               "precise_disagreement":"Finance is treating the price as a promise. It is a positioning statement.",
               "what_would_change_my_mind":"Evidence that a second pricing announcement gets any attention at all.",
               "proposal":"Price on the page at launch; billing switched on when the meter is trusted.",
               "resolved":false}]}
            """),

            // `department_key` is null: the contract is explicit that the devil's
            // advocate must NOT be given a department colour — "You are not a
            // department. You have no interests to protect."
            SSEFrame(event: "devils_advocate", data: """
            {"agent_id":"devils_advocate","department_key":null,"verdict":{
              "plan_is_sound":false,
              "load_bearing_assumption":"That the launch is the only moment attention is available.",
              "how_it_could_be_false":"For a founder tool the loudest day is usually the day the first real user ships something with it — which is after launch.",
              "cheapest_test":"Ask the five founders already in the trial whether they noticed the launch at all.",
              "failure_post_mortem":"The paywall shipped on time, converted four people, and the meter had to be reissued because nobody had used it enough to know what a credit was worth.",
              "who_is_not_in_the_room":"The founder who churns in week two and never says why.",
              "objections":["Both sides are arguing about the page, not the meter","Nobody has priced the cost of getting the meter wrong"]}}
            """),

            // Rules 3 and 5: the real disagreement verbatim, and an either/or the
            // founder owns — never "it's up to you".
            SSEFrame(event: "brief", data: """
            {"recommendation":"Put the price on the page at launch and switch billing on two weeks later, once the meter has counted real usage.",
             "confidence":3,
             "confidence_reason":"The sequencing is agreed; the price itself is not.",
             "the_real_disagreement":"Whether a price is a promise you must be able to keep, or a positioning statement you are allowed to revise.",
             "tradeoff_founder_must_own":"Either you launch with a number you may have to change, or you launch without one and give up the only day the product gets free attention.",
             "kill_criteria":["Fewer than three trial accounts reach a second session","The credit meter is off by more than 20% on any run"],
             "next_action":{"action":"Ask the five trial founders what they would pay, before the page copy is frozen.","owner":"you"},
             "what_we_dont_know":"What a credit is worth to someone who has not yet shipped anything with it.",
             "unresolved":true}
            """),

            // Zeroes, because nothing was spent. A fixture reporting ~$0.20 would be
            // inventing a charge in the one place the founder checks for real ones.
            SSEFrame(event: "telemetry", data: """
            {"tokens_per_agent":{},"cost_estimate_usd":0,"stopped_reason":null}
            """),

            SSEFrame(event: "done", data: #"{"run_id":"mock-room-1","unresolved":true,"skipped":null}"#),
        ]
    }

    /// One entry per branch of the old `if`-chain, IN THE CHAIN'S ORDER. The final entry is the
    /// catch-all the chain ended with, and `deliverable(for:)` falls back to the last entry, so
    /// it must stay last.
    private static var codepetDeliverables: [DemoDeliverable] {
        [
            DemoDeliverable(keywords: ["positioning", "value prop"], kind: "doc", body: """
            For solo founders drowning in scattered docs and stalled momentum, **{{product}}** is the \
            AI cofounder that turns your company into one living workspace — it plans your next \
            move, does the work with you, and remembers every decision. Unlike a generic AI chat \
            or a stack of disconnected tools, {{product}} is grounded in *your* company and acts, not \
            just answers.

            **One-liner** — {{product}} is the AI cofounder that runs your company's busywork so you \
            can build.

            **Why it works**
            - Names a sharp, real pain (scattered context, no momentum).
            - Says exactly who it's for (early solo founders), not 'everyone'.
            - Draws the contrast (grounded + acts vs. generic chat).

            **Use it in**: your landing hero, the first line of your pitch, the App Store subtitle.
            """),

            DemoDeliverable(keywords: ["landing", "copy", "website"], kind: "post", body: """
            **Headline** — Your AI cofounder, not another chatbot.

            **Subhead** — {{product}} plans your next move, does the work with you, and remembers \
            every decision — grounded in your actual company.

            **Benefit bullets**
            - **Always knows your context.** No re-explaining — it reads your brief, roadmap, and decisions.
            - **Does the work, not just talk.** Drafts, plans, and deliverables you approve in one tap.
            - **A team of specialists.** Marketing, Engineering, and Design pets step in for their domain.

            **Primary CTA** — Start free   ·   **Secondary** — See how it works
            """),

            DemoDeliverable(keywords: ["waitlist", "signup", "sign up"], kind: "checklist", body: """
            A no-backend email capture you can ship today.

            1. **Pick the tool** — a hosted form (Tally / Typeform) or a one-field section on your landing page.
            2. **Ask for one thing** — email only. Every extra field drops conversion.
            3. **Set the confirmation** — a short 'you're on the list' message + what to expect next.
            4. **Wire the storage** — form → a sheet or your Firestore `waitlist` collection.
            5. **Add a share nudge** — 'Want in sooner? Share your link.'

            **Done when**: a stranger can land, drop an email, and you can see it come through.
            """),

            DemoDeliverable(keywords: ["brand", "logo", "look", "visual"], kind: "doc", body: """
            A calm, confident visual direction you can apply everywhere.

            **Palette** — one ink (`#1f1b15`), one paper (`#f4f1ea`), one accent (a violet, `#7c3aed`). \
            Restraint reads as premium; add a second accent only when you truly need it.

            **Type** — a friendly grotesk for headers, a readable sans for body. One family, two weights beats five fonts.

            **Logo mark** — a simple, single-color glyph that survives at 16px (favicon) and in one color \
            (stamps, watermarks). Wordmark = the name set in your header weight, tightened.

            **Rule of thumb** — pick the boring, consistent option; recognizability comes from repetition, not novelty.
            """),

            DemoDeliverable(keywords: ["outreach", "cold", "sales", "email"], kind: "email", body: """
            **Subject** — a quick idea for {{company}}

            Hi {{name}} — I'll keep this short. I'm building {{product}}, an AI cofounder that runs a \
            solo founder's whole company — it plans the next move, does the work with you, and \
            remembers every decision.

            I noticed {{company}} is {{specific observation}} — that's exactly the kind of momentum \
            problem it's built for. Worth a 15-minute look?

            No pitch deck, just a live demo. Reply "yes" and I'll send a time.

            — Mona

            _Tip: keep the ask tiny (a 15-min look), personalize line 2, and cut everything else._
            """),

            DemoDeliverable(keywords: ["faq", "support", "help center"], kind: "doc", body: """
            The first questions new users ask — answer them before they have to write in.

            **What is {{product}}?** An AI cofounder that runs your company's busywork — it plans, does \
            the work with you, and remembers your decisions.

            **Do I need to know how to code?** No. {{product}} drafts and produces; you approve.

            **Is my data private?** Your company context is yours; we don't train on it.

            **How is it priced?** A credit model — chat feels free, deliverables spend. Trial, then Pro.

            **Can I cancel anytime?** Yes, one tap in Settings — no email required.

            _Add each real question you get to this list; it doubles as your objection-handling script._
            """),

            DemoDeliverable(keywords: ["deploy", "release", "ops"], kind: "checklist", body: """
            Ship a release the same safe way every time.

            1. **Green build** — tests pass locally and in CI.
            2. **Version bump** — tag the release; write a one-line changelog.
            3. **Backup / migration** — run pending DB migrations; confirm a rollback path.
            4. **Deploy to staging** — smoke-test the critical flow end to end.
            5. **Promote to prod** — deploy, then re-run the smoke test live.
            6. **Watch** — check errors/latency for 15 minutes; keep the rollback command ready.

            **Done when**: the critical flow works in prod and dashboards are clean.
            """),

            DemoDeliverable(keywords: ["privacy", "policy", "legal", "terms"], kind: "legal", body: """
            _Plain-language draft — have a lawyer review before you publish._

            **Privacy Policy — {{product}}**

            **What we collect** — your account email, the company context you enter, and basic usage \
            analytics. We do **not** sell your data or train public models on your company content.

            **Why** — to run the product for you (generate work, remember decisions) and to keep it reliable.

            **Your choices** — export or delete your data anytime from Settings; deleting your account \
            removes your company content.

            **Sharing** — only with the infrastructure providers needed to run the service (hosting, \
            auth, payments), under their own terms.

            **Contact** — privacy@codepet.app for any request.
            """),

            DemoDeliverable(keywords: ["pricing", "price"], kind: "doc", body: """
            **Model** — credits, not a seat/day cap: chat feels unlimited, deliverables spend.

            - **Trial** — 7 days, ~150 credits, then it stops (no permanent free tier).
            - **Pro — $20/mo** — 800 credits included; overage auto-billed at $0.05/credit.

            **Why this shape**
            - Chat is cheap (~0.25 credit/msg) so exploring feels free; the real cost is generation.
            - One price, no BYOK — simpler to reason about and simpler to sell.

            You can change any number later — ship a price, then let real usage tell you.
            """),

            DemoDeliverable(keywords: ["user", "interview", "talk to", "discovery"], kind: "doc", body: """
            **Goal** — understand the problem, not pitch. 20 minutes each.

            **Opening** — 'I'm trying to learn, not sell. Walk me through the last time you ran into this.'

            **Core questions**
            1. When did you last hit this? What did you actually do?
            2. What's the most frustrating part — and why that part?
            3. What have you tried? What did it cost you (time or money)?
            4. If you had a magic fix, what would it do for you?

            **Close** — 'Who else should I talk to?' and ask to follow up.

            **Watch for**: stories about real behavior over opinions ('I would probably…').
            """),

            // The catch-all. `{{title}}` was `\(title)` when this lived in a function; the token
            // is substituted by `MockChat.runResult` so the entry can stay a plain value.
            DemoDeliverable(keywords: [], kind: "plan", body: """
            A first cut to get you moving — treat it as a starting point, not the final word.

            **The move** — take '{{title}}' from idea to a concrete first step this week.

            **This week**
            1. Define what 'done' looks like in a single sentence.
            2. Ship the smallest version today — rough is fine.
            3. Get one piece of real feedback before you polish anything.

            **Watch out for** — scope creep and polishing before you've validated the core.
            """),
        ]
    }
}
#endif

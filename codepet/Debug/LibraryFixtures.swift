// codepet/Debug/LibraryFixtures.swift
#if DEBUG
import Foundation

/// One deliverable of every kind, for auditing the Library's viewers in the real app.
///
/// WHY THIS EXISTS. There is no way to ask the product for a specific deliverable kind:
/// `runTaskCore` lets the model pick whichever kind fits what it wrote, so getting a `.screens`
/// or a `.site` in front of you is a matter of running tasks until one happens. Auditing all ten
/// viewers that way costs a run each, takes an afternoon, and in practice means checking four
/// kinds and assuming the rest.
///
/// DEBUG-ONLY, and gated behind a launch argument on top of that — `-seedLibrary YES`. The whole
/// file compiles out of a release build.
///
/// DECODED FROM JSON, not built with memberwise initialisers. Three of the payload types
/// (`CalendarWeek`, `Screen`, `SitePayload`) define `init(from:)`, which suppresses the
/// memberwise init anyway — but the better reason is that this is the exact shape the Cloud
/// Function puts on the wire: flat, discriminated by the deliverable's kind. A fixture built by
/// hand could be a shape the decoder would reject; one decoded here cannot.
enum LibraryFixtures {

    /// Every fixture id carries this prefix so seeded rows are identifiable at a glance in a
    /// debugger, in a Firestore document, or in a diff — if one ever escapes, it says where
    /// it came from.
    static let idPrefix = "seed-fixture-"

    /// Twelve of the thirteen kinds.
    ///
    /// `.other` is the deliberate omission: it routes through the SAME `default` branch of
    /// `DeliverableBodyView` as `.text`, so seeding it would add a second identical-looking row
    /// and no coverage. Every other kind reaches a viewer nothing else reaches.
    ///
    /// `.email` and `.dms` were missing from the first version of this file, which was a real
    /// hole: they are the two kinds the whole reading-standard pass was derived from, and `.dms`
    /// is the ONE viewer that overrides the no-card-in-a-sheet rule (its cards are siblings, one
    /// per recipient). The harness could not show the thing most likely to be wrong.
    static var all: [Deliverable] {
        [
            doc, plan, checklist, post, legal, calendar, sheet, site, screens, text, email, dms
        ]
    }

    // MARK: - Kinds with a structured payload

    private static var doc: Deliverable {
        make(.doc, "Ship billing before the beta", """
        {"call":"Ship the billing path before the beta, not after — everything else on the critical path can slip a week and this cannot.",
         "sections":[
           {"h":"Why this is the constraint","p":"The freeze is Aug 22 and the launch window is Aug 28–31. Billing is the only item on the path with an external dependency we do not control, and the only one where being late means taking money we cannot charge for."},
           {"h":"What we are not doing","p":"No BYOK, no metered overage, no annual plan. Each of those is a pricing decision dressed as an engineering task, and the pricing is locked."},
           {"h":"The open question","p":"The trial credit amount is still undecided, and it is the one number that changes both the funnel and the unit economics. It cannot stay open past the freeze."}],
         "next":["Wire Stripe checkout against the Pro plan only.","Decide the trial credit amount — still open, still blocking.","Draft the refund policy Stripe will ask for."]}
        """)
    }

    private static var plan: Deliverable {
        make(.plan, "Cut time-to-first-deliverable", """
        {"goal":"Cut the time from signup to first deliverable under four minutes, so a founder sees the product work before they decide whether to trust it.",
         "steps":["Instrument the onboarding funnel so the current time-to-first-deliverable is a number, not a guess.",
                  "Collapse the three-screen brief into one, keeping only the fields the scaffold actually reads.",
                  "Pre-warm the first task run while the founder is still picking a companion."],
         "changes":[{"area":"OnboardingView","edit":"Merge steps 2 and 3; drop the four fields nothing downstream consumes."},
                    {"area":"runTaskCore","edit":"Start the first run on brief submit rather than on first chat message."}],
         "verify":["A cold account reaches its first deliverable in under four minutes.",
                   "No field removed from the brief is referenced anywhere in functions/."],
         "risks":"Pre-warming spends a run the founder may never look at. At ~$0.005 per ordinary turn that is affordable, but it stops being affordable if the scaffold retries."}
        """)
    }

    private static var checklist: Deliverable {
        make(.checklist, "Launch readiness", """
        {"items":[{"t":"Register the trademark in the two markets that actually matter before the launch post goes out","done":true},
                  {"t":"Move the waitlist off the spreadsheet and into something that survives a spike","done":true},
                  {"t":"Write the refund policy — the one thing Stripe will ask for that nobody has drafted","done":false},
                  {"t":"Decide the trial credit amount","done":false},
                  {"t":"Dry-run the download-and-install path on a machine that has never seen the app","done":false}]}
        """)
    }

    private static var calendar: Deliverable {
        make(.calendar, "Two-week content plan", """
        {"weeks":[
          {"label":"Week 1 — build in public","items":[
            {"day":"Mon","kind":"thread","body":"The six-tabs problem, told as the story of one bad Tuesday."},
            {"day":"Wed","kind":"demo","body":"Screen recording: a decision going into the room and a brief coming out."},
            {"day":"Fri","kind":"post","body":"What the departments disagreed about this week, and who was right."}]},
          {"label":"Week 2 — the launch","items":[
            {"day":"Tue","kind":"post","body":"Launch announcement, cross-posted everywhere at 9am."},
            {"day":"Thu","kind":"reply","body":"Answer every comment on the launch thread by hand."}]}]}
        """)
    }

    private static var sheet: Deliverable {
        make(.sheet, "Pricing model", """
        {"price":{"val":20,"min":5,"max":60,"step":1},
         "waitlist":{"val":1200,"min":100,"max":8000,"step":50},
         "conversion":{"val":12,"min":1,"max":40,"step":1},
         "churn":{"val":6,"min":1,"max":20,"step":1},
         "summary":"At a $20 Pro plan and 12% of the waitlist converting, the seed month lands near break-even on inference cost alone — before any of the fixed costs."}
        """)
    }

    private static var site: Deliverable {
        make(.site, "Landing page", """
        {"title":"Codepet","brand":"Codepet","kicker":"For solo founders",
         "headline":"Run your company with","headlineHi":"a team that argues",
         "sub":"Describe what you are building. Codepet gives you a roadmap, runs the tasks, and convenes the departments that disagree about them.",
         "ctaPrimary":"Download for macOS","ctaSecondary":"See how it works",
         "howEyebrow":"How it works","howTitle":"Three steps, no setup",
         "steps":[{"h":"Describe it","p":"One brief. No integrations, no board to configure."},
                  {"h":"Watch them argue","p":"Four departments take a position, and the disagreement is the point."},
                  {"h":"Get the deliverable","p":"Not a plan to do it — the finished thing, ready to paste."}],
         "featEyebrow":"Why it is different","featTitle":"It does the work",
         "features":[{"h":"Real artifacts","p":"Emails, plans, checklists, financial models — not summaries of them."},
                     {"h":"Shown reasoning","p":"Every call comes with what would change its mind."}],
         "quote":"It is the first tool that told me I was asking the wrong question.","quoteBy":"a founder, probably",
         "finalTitle":"Start with one decision","finalSub":"Free while we are in beta.","finalCta":"Download",
         "accent":"#7c3aed","footNote":"Made by MURROR"}
        """)
    }

    private static var screens: Deliverable {
        make(.screens, "Onboarding flow", """
        {"screens":[
          {"name":"Codepet","time":"9:41","kick":"Step 1","title":"What are you building?","sub":"One paragraph is enough. You can change it later.","art":"connect","cta":"Continue","note":"Takes about a minute"},
          {"name":"Codepet","time":"9:42","kick":"Step 2","title":"Meet your team","sub":"Nine departments. You will not need all of them at once.","art":"session","cta":"Pick a companion","note":"You can change this any time"},
          {"name":"Codepet","time":"9:43","kick":"Step 3","title":"Your first deliverable","sub":"Codepet already started on it while you were reading.","art":"recap","cta":"Open it","note":"Nothing to configure"}]}
        """)
    }

    /// The REFERENCE card — everything else in this pass was derived from it. Blanks in the body
    /// and in the subject, so the tint and the "fill in N blanks" footer are both exercised.
    private static var email: Deliverable {
        make(.email, "Quick question about [company]'s morning bake", body: """
        Hi [name] — saw you shipped [product] last week and wanted to reach out.

        We're building the thing you complained about on [date]: a way to see what selling out actually cost you, without setting up an account.

        Worth 15 minutes this week?
        """)
    }

    /// The ONE viewer that keeps its card inside a sheet, because these are siblings rather than
    /// one frame — three messages to three people. Seeded with three deliberately, since the
    /// whole question is whether they read as separate objects; with one it would prove nothing.
    private static var dms: Deliverable {
        make(.dms, "Beta outreach — three bakers", """
        {"messages":[
          {"name":"Marta (Rye & Co)","note":"already asked","msg":"Hi Marta — you said you'd try this the moment it existed. It exists. Here's the link: [url]. It takes about two minutes and needs no account."},
          {"name":"Tom (Corner Bakehouse)","note":"cold","msg":"Hi Tom — I'm building something for bakers who sell out before noon and want to know what that cost them. Would you try it on one bake and tell me if the number looks right?"},
          {"name":"Priya (Flour & Salt)","note":"referred by [name]","msg":"Hi Priya — [name] suggested I get in touch. I've built a way to estimate the money left on the shelf when you sell out. Can I send it over?"}]}
        """)
    }

    // MARK: - Kinds with no structured payload

    private static var post: Deliverable {
        make(.post, "Launch announcement", body: """
        ## We built the thing we kept complaining about

        For a year we ran our company out of six tabs and a group chat. The roadmap lived in one place, the reasoning lived in another, and the actual work lived nowhere.

        Codepet is the fix: **an AI team that argues the decision out, then writes the deliverable.**

        Free while we're in beta. Ships [date].
        """)
    }

    private static var legal: Deliverable {
        make(.legal, "Mutual NDA", body: """
        ## 1. Confidential Information

        "Confidential Information" means any information disclosed by one party to the other, directly or indirectly, that is designated as confidential or that reasonably should be understood to be confidential given the nature of the information.

        ## 2. Obligations

        The receiving party shall not disclose Confidential Information to any third party without prior written consent, and shall use the same degree of care it uses to protect its own confidential information.

        - Term: two years from the Effective Date
        - Governing law: [jurisdiction]
        - Signed: [name], [date]
        """)
    }

    /// The FALLBACK case — no structured payload and a kind with no viewer of its own, so it
    /// lands in `DeliverableBodyView`'s `default` branch. Worth seeding precisely because it is
    /// the branch nobody thinks to check.
    private static var text: Deliverable {
        make(.text, "What nobody in the room knew", body: """
        # What nobody in the room knew

        The pricing question turned on a number none of the four departments had: how many trial users convert after the credits run out.

        - Finance assumed 8%
        - Sales assumed 20%
        - Nobody had measured it

        Until that number exists, the trial credit amount is a guess wearing a spreadsheet. Decide by [date].
        """)
    }

    // MARK: - Building

    /// A fixture WITH a structured payload, decoded from the flat wire JSON.
    ///
    /// A malformed fixture must not fail silently into a payload-less deliverable that renders
    /// through the markdown fallback — that would look like a viewer bug during an audit and
    /// send someone hunting the wrong thing. It traps instead: this is DEBUG-only code and a
    /// broken fixture is a bug in this file, not a condition to degrade around.
    private static func make(_ kind: DeliverableKind, _ title: String, _ payloadJSON: String) -> Deliverable {
        guard let payload = try? JSONDecoder().decode(DeliverablePayload.self,
                                                      from: Data(payloadJSON.utf8)) else {
            fatalError("LibraryFixtures: \(kind.rawValue) payload JSON does not decode")
        }
        return Deliverable(id: idPrefix + kind.rawValue,
                           kind: kind,
                           title: title,
                           body: "Seeded fixture — see LibraryFixtures.swift.",
                           createdAt: stamp(kind),
                           payload: payload)
    }

    /// A fixture with NO structured payload — `title` + `body` only, the way `.post`, `.legal`
    /// and the fallback kinds actually arrive.
    private static func make(_ kind: DeliverableKind, _ title: String, body: String) -> Deliverable {
        Deliverable(id: idPrefix + kind.rawValue,
                    kind: kind,
                    title: title,
                    body: body,
                    createdAt: stamp(kind))
    }

    /// A fixed, distinct timestamp per kind. The Library sorts newest-first on `createdAt`, so
    /// without one the ten rows would order arbitrarily between launches and you could not tell
    /// a re-seed from a reorder. Fixed rather than `Date()` so two launches look identical.
    private static func stamp(_ kind: DeliverableKind) -> String {
        let idx = DeliverableKind.allCases.firstIndex(of: kind) ?? 0
        return String(format: "2026-08-11T%02d:00:00Z", 23 - idx)
    }
}
#endif

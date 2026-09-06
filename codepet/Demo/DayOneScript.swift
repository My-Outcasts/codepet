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
///
/// **Each department now speaks three times, not one.** `MockChat` only ever returned a
/// department's in-character reply when `req.deptKey` was set, and this script never armed one
/// outside the single `asks` beat — so eight of nine of Murror's own replies were unreachable
/// on day one and every conversational turn fell through to the generic default. Each department
/// now gets `asks` → `frames` → its link(s) → `reports`: it asks the question, frames how it
/// will approach the work, the link(s) produce and file the artifact, and then it reports what
/// it found and hands to the next department. Design, 2026-09-06.
enum DayOneScript {

    /// Which of a department's three speaking beats this is. Shared with `MockFlowScript.Intent`
    /// (`.petSays(deptKey:line:)`) so the 24-beat tour compiles against the same type without
    /// growing a case of its own for a line it does not use.
    enum Line: Equatable {
        case asks, frames, reports
    }

    /// Which of the four opening lines this is. Shared with `MockFlowScript.Intent`
    /// (`.opening(_:)`) the same way `Line` is shared with `.petSays(deptKey:line:)`.
    ///
    /// **Amendment 2, 6 Sep — the day needs an opening.** The founder objected to the cold
    /// start: after onboarding, the transcript's first line used to be Marketing's `asks`
    /// ("Is this a real problem, or just mine?") with no context at all. These four beats give
    /// it one, before any department speaks.
    enum OpeningLine: Equatable {
        case summary, prompt, founderReply, setup
    }

    /// The opening's four lines, verbatim from the design doc. `summary`, `prompt` and `setup`
    /// are the PRODUCT talking — `MockFlowPlayer` posts them with no `companionId` and no
    /// `deptName`, which renders as bare prose with no speaker row (`CodepetBrand.header`
    /// returns nil for exactly that combination — the rule as shipped, not a new exception).
    /// `founderReply` is the founder's own words and posts `role: .me`, the same way
    /// `.petSays(line: .asks)` already does. English only, consistent with `frames`/`reports`.
    static func openingText(_ line: OpeningLine) -> String {
        switch line {
        case .summary:
            return "Here's what I have so far: Murror — an app for people who feel lonely and "
                + "don't know how to reach each other. That came from onboarding, and it's all I "
                + "know. No plan, no brand, no users."
        case .prompt:
            return "Before I bring in the departments — tell me anything else that matters. Who "
                + "is it for, what have you tried, what worries you?"
        case .founderReply:
            return "It started because I couldn't tell anyone I was lonely without it sounding "
                + "like a crisis. I want something that helps people say the small version out "
                + "loud."
        case .setup:
            return "That's the thing to protect. Eight departments, nine questions — I'll bring "
                + "each one in as it becomes answerable, and you approve everything before it's "
                + "filed."
        }
    }

    /// One department's three lines. `asks` is bilingual because it ships in the transcript as
    /// a chat message a Vietnamese founder has to read; `frames` and `reports` are English only
    /// — founder decision, 6 Sep, recorded in the design doc: writing sixteen more reviewed
    /// Vietnamese strings was rejected in favour of shipping the English lines that exist, on
    /// the record as a mixed-language demo in Vietnamese rather than a silent gap.
    ///
    /// **`asks` is the FOUNDER's own words, not the pet's.** Amendment, 6 Sep: the brief was
    /// "imagine what questions THEY would have when starting a project" — the questions belong
    /// to the founder. They shipped as pet-authored messages, so Nova asked a question and then
    /// answered it herself; `MockFlowPlayer` now posts this line as `role: .me` instead. First
    /// person, and stripped of the coaching instruction that used to ride along — that content
    /// already lives in `frames`/`reports`, so nothing is lost. The Vietnamese here is a rewrite
    /// that still needs a native read (two of three Vietnamese phrases written for this branch
    /// were wrong before a human caught them).
    static let script: [String: (asks: (en: String, vi: String), frames: String, reports: String)] = [
        "mkt": (
            asks: (en: "Is this a real problem, or just mine?",
                   vi: "Đây có phải vấn đề thật không, hay chỉ mình tôi thấy vậy?"),
            frames: "The first one is yours — twelve conversations I can't have for you. Once you've had "
                + "them, I'll scan what's already out there and tell you where those apps stop.",
            reports: "Twelve conversations and a scan, and they agree: every app in this category ends "
                + "with someone understanding themselves alone. That's the gap. Now the harder question "
                + "— and it's still me asking it."
        ),
        "sales": (
            asks: (en: "So who is this not for?",
                    vi: "Vậy sản phẩm này không dành cho ai?"),
            frames: "Same voice, different job. Marketing found who this is for; Sales has to find who "
                + "it isn't, and be specific enough that it stings.",
            reports: "One of your twelve found it insulting. That's the most useful sentence in the file "
                + "— it's what stops outreach spending its best hours in the wrong places. Luna's turn: "
                + "now we know who, she can decide how it feels."
        ),
        "design": (
            asks: (en: "What should it feel like?",
                    vi: "Nó nên mang lại cảm giác gì?"),
            frames: "I've read the interviews and the disqualifier list. Feeling comes last, not first "
                + "— I can only shape it once I know who it's for and who it isn't.",
            reports: "Soft, quiet, unhurried — and never graded. Naming a feeling must not feel like "
                + "being marked. Byte next: someone has to decide what this actually runs on."
        ),
        "eng": (
            asks: (en: "What do I build it on? And does anything people write leave their device?",
                    vi: "Tôi nên xây trên nền tảng gì? Và những gì người ta viết có rời khỏi máy của họ không?"),
            frames: "Direction's set, so I can pick a stack. The question that matters isn't the "
                + "framework — it's whether anything a person writes ever leaves their device.",
            reports: "On-device where it can be, and nothing leaves with a name attached. That decision "
                + "sets your running cost, which is why Crash goes next and not first."
        ),
        "fin": (
            asks: (en: "What is this going to cost me a month?",
                    vi: "Mỗi tháng cái này sẽ tốn của tôi bao nhiêu?"),
            frames: "I couldn't have answered this an hour ago. Pricing needs a stack — now Byte's "
                + "chosen, I can put a number on it.",
            reports: "Sixty cents a month per active user, at your numbers, on Byte's stack. Charge "
                + "four dollars and you can breathe. Sage is next, and hers is the question a product "
                + "about loneliness cannot dodge."
        ),
        "support": (
            asks: (en: "What happens if someone's really struggling at 2am?",
                    vi: "Chuyện gì xảy ra nếu ai đó thật sự khủng hoảng lúc 2 giờ sáng?"),
            frames: "I want to be careful here. Someone struggling at 2am doesn't need a chatbot being "
                + "clever, and what the app says then has to be written down, not improvised.",
            reports: "What it says, when it says it, and what it refuses to handle — written as policy "
                + "rather than left to a prompt. Glitch reads this next: holding those words is a legal "
                + "question too."
        ),
        "legal": (
            asks: (en: "Am I in trouble for holding what people write?",
                    vi: "Tôi có gặp rắc rối khi lưu giữ những gì người ta viết không?"),
            frames: "I've read Sage's policy. People are typing the most private thing they have into "
                + "this, so the deletion promise has to be plain language first and paperwork second.",
            reports: "One tap and it's gone. No confirmation email, no support ticket, no \"are you "
                + "sure\" chain designed to make you give up. Same voice for the last one: shipping "
                + "this without breaking it."
        ),
        "ops": (
            asks: (en: "How do I ship this without breaking it?",
                    vi: "Làm sao để phát hành mà không làm hỏng nó?"),
            frames: "Still me. Legal was about what you owe them; Operations is about not breaking it "
                + "while you keep your word.",
            reports: "Thursday, not Friday — a Friday release means a weekend of nobody watching. "
                + "That's nine questions answered, and the tenth is yours: who do you tell first?"
        ),
    ]

    /// **Amendment 3, 6 Sep — Byte's second and third appearances.** Environment and Code are
    /// new chapters that come AFTER Operations hands the day back, and Byte carries both —
    /// continuity, not a new cast member: it chose the stack four questions earlier, so it is
    /// the voice that knows what the environment needs and what the first code should be.
    ///
    /// `deptKey` alone ("eng") cannot disambiguate a third appearance from the first — `script`
    /// holds exactly one triple per department. Keyed by CHAPTER instead, because that is the
    /// one piece of context `MockFlowPlayer` already has at the call site and the one thing that
    /// actually distinguishes "Engineering · Byte" asking about the stack from "Environment ·
    /// Byte" asking what needs to be linked. English only, per the founder's standing decision
    /// recorded in the design doc for this amendment — unlike `script`, there is no `vi` slot to
    /// leave empty because none was ever asked for.
    static let extraAppearances: [String: (asks: String, frames: String, reports: String)] = [
        "Environment · Byte": (
            asks: "What do I need set up before any of this can run?",
            frames: "I picked the stack four questions ago. Before I can touch code, this "
                + "company needs a folder to work in — and you decide which tools it is "
                + "allowed to use.",
            reports: "Linked. Three tools on, the rest off until they earn it. Nothing here "
                + "needs a card yet."
        ),
        "Code · Byte": (
            asks: "Can you build the landing page?",
            frames: "That is the beacon's tenth question — how people hear about it. I work "
                + "on your machine, I show you every change, and nothing is saved until you "
                + "say so.",
            reports: "One page, Luna's direction, Nova's positioning line. A draft until you "
                + "approve it — same as everything else today."
        ),
    ]

    /// The text for one department's line, or nil when the department has none. Only `asks`
    /// varies by language; `frames` and `reports` return their English string regardless.
    ///
    /// `chapter` is nil by default so every existing caller (including `DayOneScriptTests`
    /// calling this directly) keeps resolving against `script` exactly as before. When a chapter
    /// IS given and it names one of Byte's extra appearances, that takes priority over the
    /// department's original ("Engineering · Byte") triple — it is a different chapter asking a
    /// different question, not the same one replayed.
    static func line(for deptKey: String, _ line: Line, language: AppLanguage,
                      chapter: String? = nil) -> String? {
        if let chapter, let extra = extraAppearances[chapter] {
            switch line {
            case .asks: return extra.asks
            case .frames: return extra.frames
            case .reports: return extra.reports
            }
        }
        guard let entry = script[deptKey] else { return nil }
        switch line {
        case .asks: return language == .vi ? entry.asks.vi : entry.asks.en
        case .frames: return entry.frames
        case .reports: return entry.reports
        }
    }

    static let beats: [MockFlowScript.Beat] = build([
        ("Day one", 3.2, .hold,
         "Mona has a feeling and nothing else — people are lonely and don't know how to reach "
         + "each other. No plan, no brand, no idea where to start. This is the board a founder "
         + "actually begins with: empty."),

        // Amendment 2, 6 Sep — the opening. Four beats, before any department speaks: the
        // founder objected to the cold start onto Marketing's `asks` with no context at all.
        // `summary`, `prompt` and `setup` are the PRODUCT talking (no speaker row); only
        // `founderReply` is right-aligned. Durations are the readability floor (chars/45 ÷ 1.5
        // at Slow) with real margin, not the bare minimum — these are long lines and the
        // budget test below is what actually enforces the floor.
        ("Day one", 4.4, .opening(.summary), DayOneScript.openingText(.summary)),

        ("Day one", 3.0, .opening(.prompt), DayOneScript.openingText(.prompt)),

        ("Day one", 3.2, .opening(.founderReply), DayOneScript.openingText(.founderReply)),

        ("Day one", 3.4, .opening(.setup), DayOneScript.openingText(.setup)),

        ("Marketing · Nova", 2.4, .petSays(deptKey: "mkt", line: .asks),
         "Mona asks her own first question — right-aligned, no speaker row, same as "
         + "anything else she types."),

        // Framing beat: caption is the department's own `frames` copy, verbatim — not a short
        // narration like the `asks` beat above. Its duration is sized off that same text via
        // the readability floor (chars/45 ÷ 1.5 at Slow), same formula every beat here uses.
        ("Marketing · Nova", 2.4, .petSays(deptKey: "mkt", line: .frames),
         "The first one is yours — twelve conversations I can't have for you. Once you've had "
         + "them, I'll scan what's already out there and tell you where those apps stop."),

        // Link 1 — Marketing · Nova. The founder's own work, and it stays that way.
        //
        // `.walkthroughFounderTask` used to sit here, asking about this task through a real
        // `MockChat` turn. Removed — amendment, 6 Sep: it was the only beat in day one that
        // triggered a conversational reply, and `murrorDayOne` borrows `murrorDepartmentReplies`,
        // which is written against the MID-FLIGHT board — so it showed Marketing offering to
        // write the landing page "against the brand direction Luna set" four segments before
        // Luna speaks. It is also redundant now: the founder's question above and Nova's
        // `frames` answer are both already scripted beats.
        ("Marketing · Nova", 2.4, .recordFounderTask(taskId: "mur-interviews"),
         "She has the conversations and records what she heard — that's what files it, and "
         + "everything after reads it."),

        // Link 2 — Marketing · Nova. Same department, same pet — it does not open twice.
        ("Marketing · Nova", 2.6, .runTask("mur-landscape"),
         "Nova reads the interviews before answering — the credit line on the card names them."),
        ("Marketing · Nova", 2.8, .approveNewestDraft,
         "Approving files it. Nothing was written anywhere until that tap, and the next "
         + "department will read what she just approved."),

        // Reporting beat: Marketing holds two links, so it reports once — AFTER BOTH — rather
        // than once per link. Framing is per department, not per link.
        ("Marketing · Nova", 3.0, .petSays(deptKey: "mkt", line: .reports),
         "Twelve conversations and a scan, and they agree: every app in this category ends "
         + "with someone understanding themselves alone. That's the gap. Now the harder question "
         + "— and it's still me asking it."),

        ("Sales · Nova", 2.2, .petSays(deptKey: "sales", line: .asks),
         "Mona asks again — same founder, a different department waiting to answer."),

        ("Sales · Nova", 2.2, .petSays(deptKey: "sales", line: .frames),
         "Same voice, different job. Marketing found who this is for; Sales has to find who "
         + "it isn't, and be specific enough that it stings."),

        // Link 3 — Sales · Nova.
        ("Sales · Nova", 2.6, .runTask("mur-notfor"),
         "The scan turns up crowded ground. The one person who found it insulting is worth "
         + "more than the nine who liked it."),
        ("Sales · Nova", 2.8, .approveNewestDraft,
         "A disqualifier list is a strange thing to be pleased about, and it is the first "
         + "artifact that makes the next four decisions easy."),

        ("Sales · Nova", 3.2, .petSays(deptKey: "sales", line: .reports),
         "One of your twelve found it insulting. That's the most useful sentence in the file "
         + "— it's what stops outreach spending its best hours in the wrong places. Luna's turn: "
         + "now we know who, she can decide how it feels."),

        ("Design · Luna", 2.2, .petSays(deptKey: "design", line: .asks),
         "Her third question. Luna has read the two artifacts and answers it next."),

        ("Design · Luna", 2.2, .petSays(deptKey: "design", line: .frames),
         "I've read the interviews and the disqualifier list. Feeling comes last, not first "
         + "— I can only shape it once I know who it's for and who it isn't."),

        // Link 4 — Design · Luna.
        ("Design · Luna", 2.6, .runTask("mur-brand"),
         "Luna reads both artifacts and shapes how it should feel."),
        ("Design · Luna", 2.8, .approveNewestDraft,
         "Four questions in, and each answer has been built on the last rather than started "
         + "from the brief again."),

        ("Design · Luna", 2.4, .petSays(deptKey: "design", line: .reports),
         "Soft, quiet, unhurried — and never graded. Naming a feeling must not feel like "
         + "being marked. Byte next: someone has to decide what this actually runs on."),

        ("Engineering · Byte", 2.2, .petSays(deptKey: "eng", line: .asks),
         "The first question with a bill attached."),

        ("Engineering · Byte", 2.4, .petSays(deptKey: "eng", line: .frames),
         "Direction's set, so I can pick a stack. The question that matters isn't the "
         + "framework — it's whether anything a person writes ever leaves their device."),

        // Link 5 — Engineering · Byte.
        ("Engineering · Byte", 2.6, .runTask("mur-stack"),
         "Byte reads the direction and decides what it runs on — and whether anything a "
         + "person writes ever leaves their device."),
        ("Engineering · Byte", 2.8, .approveNewestDraft,
         "That decision sets the running cost, which is why Finance is next and not first."),

        ("Engineering · Byte", 2.4, .petSays(deptKey: "eng", line: .reports),
         "On-device where it can be, and nothing leaves with a name attached. That decision "
         + "sets your running cost, which is why Crash goes next and not first."),

        ("Finance · Crash", 2.2, .petSays(deptKey: "fin", line: .asks),
         "Her question now — Crash explains next why it couldn't have come any sooner."),

        ("Finance · Crash", 2.2, .petSays(deptKey: "fin", line: .frames),
         "I couldn't have answered this an hour ago. Pricing needs a stack — now Byte's "
         + "chosen, I can put a number on it."),

        // Link 6 — Finance · Crash.
        ("Finance · Crash", 2.6, .runTask("mur-unitcost"),
         "Cost per active user, straight from the stack Byte just chose."),
        ("Finance · Crash", 2.8, .approveNewestDraft,
         "A number she can hold against a price — the first artifact that constrains rather "
         + "than describes."),

        ("Finance · Crash", 3.0, .petSays(deptKey: "fin", line: .reports),
         "Sixty cents a month per active user, at your numbers, on Byte's stack. Charge "
         + "four dollars and you can breathe. Sage is next, and hers is the question a product "
         + "about loneliness cannot dodge."),

        ("Support · Sage", 2.4, .petSays(deptKey: "support", line: .asks),
         "The question a consumer app about loneliness cannot avoid."),

        ("Support · Sage", 2.4, .petSays(deptKey: "support", line: .frames),
         "I want to be careful here. Someone struggling at 2am doesn't need a chatbot being "
         + "clever, and what the app says then has to be written down, not improvised."),

        // Link 7 — Support · Sage.
        ("Support · Sage", 2.6, .runTask("mur-crisis"),
         "Sage writes what the app says at 2am, when, and what it refuses to handle."),
        ("Support · Sage", 2.8, .approveNewestDraft,
         "Written down as policy, not left to a prompt. This is the artifact the board's one "
         + "founder-only task later asks a clinician to read."),

        ("Support · Sage", 2.8, .petSays(deptKey: "support", line: .reports),
         "What it says, when it says it, and what it refuses to handle — written as policy "
         + "rather than left to a prompt. Glitch reads this next: holding those words is a legal "
         + "question too."),

        ("Legal · Glitch", 2.2, .petSays(deptKey: "legal", line: .asks),
         "Glitch reads Sage's policy before answering."),

        ("Legal · Glitch", 2.6, .petSays(deptKey: "legal", line: .frames),
         "I've read Sage's policy. People are typing the most private thing they have into "
         + "this, so the deletion promise has to be plain language first and paperwork second."),

        // Link 8 — Legal · Glitch.
        ("Legal · Glitch", 2.6, .runTask("mur-deletion"),
         "Glitch turns the crisis policy and the stack decision into a promise: one tap, "
         + "permanent, no email."),
        ("Legal · Glitch", 2.8, .approveNewestDraft,
         "The promise comes before the privacy policy that formalises it — which is still "
         + "sitting on her board, unwritten."),

        ("Legal · Glitch", 2.8, .petSays(deptKey: "legal", line: .reports),
         "One tap and it's gone. No confirmation email, no support ticket, no \"are you "
         + "sure\" chain designed to make you give up. Same voice for the last one: shipping "
         + "this without breaking it."),

        ("Operations · Glitch", 2.2, .petSays(deptKey: "ops", line: .asks),
         "Mona's last question before the day hands one back — Glitch answers again."),

        ("Operations · Glitch", 2.2, .petSays(deptKey: "ops", line: .frames),
         "Still me. Legal was about what you owe them; Operations is about not breaking it "
         + "while you keep your word."),

        // Link 9 — Operations · Glitch.
        ("Operations · Glitch", 2.6, .runTask("mur-rhythm"),
         "A weekly rhythm the launch checklist will later assume."),
        ("Operations · Glitch", 2.8, .approveNewestDraft,
         "Nine questions, eight departments, nine artifacts — and every one of them traces "
         + "back to a task on her roadmap."),

        ("Operations · Glitch", 2.4, .petSays(deptKey: "ops", line: .reports),
         "Thursday, not Friday — a Friday release means a weekend of nobody watching. "
         + "That's nine questions answered, and the tenth is yours: who do you tell first?"),

        // The hand-back stays inside Operations' chapter rather than opening a tenth —
        // no beat here introduces new department content, so no new chapter should appear.
        ("Operations · Glitch", 2.6, .go(.library),
         "A week where every answer builds on the last. She started with a feeling and no "
         + "plan."),

        ("Operations · Glitch", 2.8, .go(.roadmap),
         "The beacon has moved to her tenth question — how people hear about it. Codepet "
         + "points at the landing page and waits."),

        // Amendment 3, 6 Sep — the environment, the code, and a slimmer bar. The roadmap beat
        // above already hands off into this: Environment and Code are two new chapters that
        // pick up her tenth question rather than just naming it. Byte carries both — it chose
        // the stack four questions ago, so it is the voice that knows what the environment
        // needs and what the first code should be.
        //
        // `.go(.environment)` and `.linkDemoFolder` are not decoration before `.codeRun` — per
        // the design doc, `Views/Environment/ProjectLinker.swift` is the real prerequisite for
        // a code run: without a linked folder, `startBuild` lands in `.noProject` and refuses.
        // Showing that precondition is what keeps the demo honest with the founder's own
        // constraint that whatever runs in the prototype also works in actual use.
        ("Environment · Byte", 2.2, .petSays(deptKey: "eng", line: .asks),
         "Mona's tenth question finally gets a place to land — Byte answers again, the same "
         + "pet who chose the stack."),

        ("Environment · Byte", 2.4, .petSays(deptKey: "eng", line: .frames),
         "I picked the stack four questions ago. Before I can touch code, this company needs "
         + "a folder to work in — and you decide which tools it is allowed to use."),

        ("Environment · Byte", 2.6, .go(.environment),
         "Byte opens Environment — the surface where a folder gets linked and its tools get "
         + "chosen. Nothing here has been possible until now."),

        ("Environment · Byte", 2.8, .linkDemoFolder,
         "Linking a folder is not a formality — without one, a code run refuses outright. "
         + "The same folder this chapter links is the one the next chapter builds on."),

        ("Environment · Byte", 2.4, .petSays(deptKey: "eng", line: .reports),
         "Linked. Three tools on, the rest off until they earn it. Nothing here needs a "
         + "card yet."),

        ("Code · Byte", 2.2, .petSays(deptKey: "eng", line: .asks),
         "Her tenth question, asked plainly. Byte already knows what this needs to run on."),

        ("Code · Byte", 2.4, .petSays(deptKey: "eng", line: .frames),
         "That is the beacon's tenth question — how people hear about it. I work on your "
         + "machine, I show you every change, and nothing is saved until you say so."),

        ("Code · Byte", 2.6, .mode(.developer),
         "Developer wakes already linked — the folder from the last chapter, not a fresh "
         + "ask. The board's tenth question finally has somewhere to run."),

        ("Code · Byte", 2.8, .codeRun("Build the Murror landing page — Luna's direction, Nova's positioning line"),
         "Byte describes the change and it does not start. The plan shows first — which "
         + "files, what it may run — and waits for a tap that hasn't happened yet."),

        ("Code · Byte", 2.8, .confirmCodeRun,
         "That tap is hers. Only now does the run actually start, naming its steps as it "
         + "goes — a process to watch, not a trick performed off screen."),

        ("Code · Byte", 2.6, .petSays(deptKey: "eng", line: .reports),
         "One page, Luna's direction, Nova's positioning line. A draft until you approve "
         + "it — same as everything else today."),

        // The closing beat. Stays inside Code's chapter rather than opening an eleventh —
        // same rule the Operations hand-back above already follows: no new department
        // content plays here, so no new chapter should appear.
        ("Code · Byte", 2.6, .go(.roadmap),
         "Ten questions in, and the board has moved."),
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

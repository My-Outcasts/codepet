import Foundation

/// Persona-specific copy for selected pilot content.
/// Lookup pattern: `PersonaContent.skillName[id]?.value(for: persona) ?? originalString`
/// Anything not registered here falls back to the original String.
struct PersonaContent {

    // MARK: Sessions — Skills (Tier 1: Foundations / Molten Forge)

    static let skillName: [String: PersonaText] = [
        "prompt-clarity": PersonaText(
            student:      "Talking to the Robot",
            productOwner: "Writing Clear Requests",
            developer:    "Prompt Clarity"
        ),
        "error-reading": PersonaText(
            student:      "Reading Error Messages",
            productOwner: "Triaging Failure Reports",
            developer:    "Error Reading"
        ),
        "tool-basics": PersonaText(
            student:      "Choosing the Right Tool",
            productOwner: "Picking Tools That Fit",
            developer:    "Tool Basics"
        ),
        "code-judgment": PersonaText(
            student:      "Trust or Try Again?",
            productOwner: "Reviewing AI Output",
            developer:    "Code Judgment"
        ),
    ]

    static let skillDesc: [String: PersonaText] = [
        "prompt-clarity": PersonaText(
            student:      "Learn how to tell the robot exactly what you want — like writing a really clear letter.",
            productOwner: "Write requirements clear enough that AI (or your team) builds the right thing the first time, not the third.",
            developer:    "Learn how to tell AI exactly what you want."
        ),
        "error-reading": PersonaText(
            student:      "When the computer shows an error, don't panic — learn what it's actually trying to tell you.",
            productOwner: "Read error logs well enough to tell whether something is a real blocker or just noise — before you escalate.",
            developer:    "Understand what error messages are really telling you."
        ),
        "tool-basics": PersonaText(
            student:      "There are lots of robots. Pick the right one for the job — like picking the right key for a lock.",
            productOwner: "Know which AI tool fits which stage (planning, building, reviewing) so you spend the right effort on the right thing.",
            developer:    "Know which AI tool to use for what."
        ),
        "code-judgment": PersonaText(
            student:      "Robots aren't always right. Learn to look at the answer and say 'try that again, please.'",
            productOwner: "Decide whether AI output is good enough to ship — spot the gap between a demo and real-world risk before release.",
            developer:    "Learn when to trust AI's code and when to say 'try again'."
        ),
    ]

    // MARK: Sessions — Challenges (Tier 1)

    static let challengeBrief: [String: PersonaText] = [
        "prompt-clarity-challenge": PersonaText(
            student:      "Write a really clear request to the robot, so it builds exactly what you imagined in your head.",
            productOwner: "Write a product brief clear enough that an engineer (or AI) ships the right feature on the first pass — no rework.",
            developer:    "Write a clear, structured prompt for a real feature. Show that you can communicate your vision to AI."
        ),
        "error-reading-challenge": PersonaText(
            student:      "An error popped up. Read it and explain to a friend what happened and how to fix it.",
            productOwner: "An incident report just landed. Triage the cause and give a fix-direction tight enough for engineering to close it inside one sprint.",
            developer:    "Diagnose an error message and explain the fix clearly."
        ),
    ]

    // MARK: Reflection — Prompts keyed by original English headline

    static let reflectionHeadline: [String: PersonaText] = [
        "Two scope additions before a Friday launch.": PersonaText(
            student:      "We added two extra things right before the big day.",
            productOwner: "Two scope additions before a Friday launch.",
            developer:    "Two scope additions before a Friday launch."
        ),
        "The pricing tier decision moved again.": PersonaText(
            student:      "We pushed the pricing decision back one more time.",
            productOwner: "Pricing tiers slipped to next sprint — third time.",
            developer:    "The pricing tier decision moved again."
        ),
        "A quiet Sunday — one clean decision.": PersonaText(
            student:      "A calm Sunday — and you finally picked one thing.",
            productOwner: "Quiet Sunday — one decision finally landed.",
            developer:    "A quiet Sunday — one clean decision."
        ),
        "Rewrite instinct on a 2-hour bug.": PersonaText(
            student:      "You almost rebuilt everything for a small bug.",
            productOwner: "Caught a 'rewrite' impulse on a small bug fix.",
            developer:    "Rewrite instinct on a 2-hour bug."
        ),
        "WebSocket migration — evidence check.": PersonaText(
            student:      "You changed plans because the test data said so.",
            productOwner: "Migration plan reshaped after load-test data came back.",
            developer:    "WebSocket migration — evidence check."
        ),
        "Swift 6 migration landed clean.": PersonaText(
            student:      "A big upgrade that just… worked, with no drama.",
            productOwner: "Major migration shipped on time, no scope creep.",
            developer:    "Swift 6 migration landed clean."
        ),
        "Two yeses before noon — both held the line.": PersonaText(
            student:      "Two requests came in before lunch — and you said no to both.",
            productOwner: "Two scope requests pre-noon, both deferred to next sprint.",
            developer:    "Two yeses before noon — both held the line."
        ),
        "Paused on an irreversible delete.": PersonaText(
            student:      "You stopped just before doing something you couldn't undo.",
            productOwner: "Paused before an irreversible action — bounded the failure mode.",
            developer:    "Paused on an irreversible delete."
        ),
        "Test suite flake — finally named.": PersonaText(
            student:      "You finally figured out the weird thing that kept breaking.",
            productOwner: "Named the flaky-test pattern — paid the deferred cost.",
            developer:    "Test suite flake — finally named."
        ),
        "Demo prep overscoped again.": PersonaText(
            student:      "The demo was ready, but you kept adding stuff anyway.",
            productOwner: "Demo was ready early — added more, lost margin for tomorrow.",
            developer:    "Demo prep overscoped again."
        ),
        "Sprint start — clean priorities.": PersonaText(
            student:      "Started the week by saying no to a couple of nice-to-haves.",
            productOwner: "Sprint started with two cuts — cheap nos before the work begins.",
            developer:    "Sprint start — clean priorities."
        ),
    ]

    static let reflectionBody: [String: PersonaText] = [
        "Two scope additions before a Friday launch.": PersonaText(
            student:      "You said yes to two small extras: filters and a new admin page. They sound tiny, but they pile up — and the launch you promised on Friday is the one paying the cost.",
            productOwner: "You reframed two new asks (filters + admin panel) as 'small.' They compound into a launch you haven't protected. Saying yes feels cheap when each ask looks minor.",
            developer:    "You reframed adding filters and an admin panel as small. They compound into a launch you haven't protected. The instinct to say yes is strong when the asks feel minor."
        ),
        "The pricing tier decision moved again.": PersonaText(
            student:      "You keep pushing the pricing decision to 'later.' Each time it feels okay — but three things are now stuck waiting on this one choice.",
            productOwner: "Pricing slipped to next sprint for the third time. Each deferral is cheap in the moment and expensive in aggregate — three downstream items now wait on this call.",
            developer:    "You pushed the pricing UI to next sprint for the third time. Each deferral is cheap in the moment and expensive in aggregate — the team now has three features waiting on this call."
        ),
        "A quiet Sunday — one clean decision.": PersonaText(
            student:      "You finally made the pricing call — only took 15 minutes once you sat down. Carrying it around had cost more than just deciding it.",
            productOwner: "You stopped deferring pricing. A decision pushed three times got made on paper in 15 minutes. Carrying the open question cost more than the decision itself.",
            developer:    "You stopped deferring pricing. One call you'd pushed three times got made on paper in 15 minutes. The cost of the decision was always smaller than the cost of carrying it."
        ),
        "Rewrite instinct on a 2-hour bug.": PersonaText(
            student:      "The fix only needed 3 lines. The rewrite would have taken 3 days. You caught yourself before going down the long road — twice, actually.",
            productOwner: "A 3-line fix was framed as a 3-day rewrite. You caught the second proposal before it shipped — the first one is already in flight.",
            developer:    "The fix was 3 lines. The rewrite would have been 3 days. You caught the second proposal before code, which is the win — the first one is already in flight."
        ),
        "WebSocket migration — evidence check.": PersonaText(
            student:      "You were going to switch everything over at once — then the data showed the old way was fine. You let the numbers win over the cool plan.",
            productOwner: "Reversed a full-cutover plan into a flagged rollout in 6 hours. Load-test data outvoted the cleaner-feeling architecture. Evidence beat aesthetic.",
            developer:    "You reversed a full-cutover plan into a flagged rollout in 6 hours. The load test said REST is fine — and you let the data outvote the aesthetic."
        ),
        "Swift 6 migration landed clean.": PersonaText(
            student:      "Two weeks of planning, one week of doing. Nothing extra, nothing pushed back. The boring plan worked.",
            productOwner: "Two sprints of planning, one sprint of execution. No scope additions, no deferrals. The boring version shipped.",
            developer:    "Two sprints of planning, one sprint of execution. No scope additions, no deferrals. The boring version worked."
        ),
        "Two yeses before noon — both held the line.": PersonaText(
            student:      "Two people asked for new things this morning. You said no to both and wrote down what you actually planned to do. Calm Wednesdays make Fridays work.",
            productOwner: "Two scope asks before noon — a refactor and an extra filter. You declined both and wrote the sprint scope down. Boring midweeks are how launch dates stay honest.",
            developer:    "Someone asked for a search refactor, someone asked for an extra filter. You said no to both and wrote the sprint scope down. Boring Wednesdays are how Fridays stay honest."
        ),
        "Paused on an irreversible delete.": PersonaText(
            student:      "You almost dropped the table. It probably would have been fine — but if a backup was missing, that would've been the only story of the week. You picked the safer path.",
            productOwner: "The destructive action would likely have worked — but a missing backup would have made it the only thing this week was about. You traded 10 minutes of friction for a bounded failure mode.",
            developer:    "The table drop would have worked — and then one missing backup would have been the only interesting thing about this week. You swapped 10 minutes of friction for a bounded failure mode."
        ),
        "Test suite flake — finally named.": PersonaText(
            student:      "Three weeks of 'eh, just run it again' turned into a 15-minute fix once you decided to actually look. Things you ignore always cost something — just later.",
            productOwner: "Three weeks of 'probably fine, rerun it' compounded into a 15-minute fix once you stopped deferring. Vagueness is always paid for — only the timing is variable.",
            developer:    "Three weeks of 'probably fine, rerun it' added up to a 15-minute fix once you stopped deferring. The cost of vagueness is always paid — the only question is when."
        ),
        "Demo prep overscoped again.": PersonaText(
            student:      "Demo was ready by 3. You kept adding things until 6 — and now one of them might break tomorrow. 'Almost done' keeps growing on you.",
            productOwner: "Demo was demo-ready at 3pm. Two more additions before 6pm, one with unresolved edge cases for tomorrow. The 'basically done' shape keeps costing margin.",
            developer:    "The demo was ready at 3pm. You shipped two more things before 6pm, and one of them has unresolved edge cases tomorrow. The shape of 'basically done' keeps costing you."
        ),
        "Sprint start — clean priorities.": PersonaText(
            student:      "You cut two things at the start of the week, even though people wanted them. Saying no early is way easier than saying no on Friday.",
            productOwner: "Cut two items with stakeholder support at sprint kickoff. Saying no upfront is ~10× cheaper than saying no on Friday. Strong opening shape.",
            developer:    "You cut two things that already had supporters. Saying no at the start is 10x cheaper than saying no on Friday. Good shape to open a sprint with."
        ),
    ]

    static let reflectionProbe: [String: PersonaText] = [
        "Two scope additions before a Friday launch.": PersonaText(
            student:      "What would you cut today to make Friday's launch feel honest?",
            productOwner: "What would you cut today so Friday's launch is one you can actually defend?",
            developer:    "What would you cut today to make Friday honest?"
        ),
        "The pricing tier decision moved again.": PersonaText(
            student:      "What's the smallest version of this decision you could just make today?",
            productOwner: "What's the smallest pricing call you could commit to right now to unblock the three downstream items?",
            developer:    "What's the smallest version of this decision you could make today?"
        ),
        "A quiet Sunday — one clean decision.": PersonaText(
            student:      "What other things are you carrying that would cost less to just decide?",
            productOwner: "What else are you holding that would cost less to decide than to carry?",
            developer:    "What else are you carrying that would cost less to decide?"
        ),
        "Rewrite instinct on a 2-hour bug.": PersonaText(
            student:      "Can you take the bigger rewrite out and just ship the small fix on its own?",
            productOwner: "Can you split the in-flight rewrite out and ship just the bug fix this week?",
            developer:    "Can you pull the CSS rewrite out of this PR and ship the fix alone?"
        ),
        "WebSocket migration — evidence check.": PersonaText(
            student:      "What's the next decision where the cool answer is going to feel hard to resist?",
            productOwner: "What's the next decision where the elegant answer will feel more attractive than the data?",
            developer:    "What's the next decision where the aesthetic answer is tempting?"
        ),
        "Swift 6 migration landed clean.": PersonaText(
            student:      "What made this one easier to finish on time?",
            productOwner: "What made this one easy to ship on time — and how do we recreate that?",
            developer:    "What made this one easy to ship on time?"
        ),
        "Two yeses before noon — both held the line.": PersonaText(
            student:      "What's one more 'yes' this week you'd rather turn into 'next week'?",
            productOwner: "What's one more in-sprint yes this week you'd rather convert to a next-sprint commitment?",
            developer:    "What's one more yes this week you'd rather convert to 'next sprint'?"
        ),
        "Paused on an irreversible delete.": PersonaText(
            student:      "What other can't-undo things are you walking past without stopping to think?",
            productOwner: "What other one-way decisions are you walking past without pausing for a checkpoint?",
            developer:    "What other one-way doors are you walking past without pausing?"
        ),
        "Test suite flake — finally named.": PersonaText(
            student:      "Is there another 'eh, probably fine' you're carrying around right now?",
            productOwner: "Is there another 'probably fine' on your plate that's quietly compounding cost right now?",
            developer:    "Is there another 'probably fine' you're carrying right now?"
        ),
        "Demo prep overscoped again.": PersonaText(
            student:      "What if you had a rule: at 3pm before a demo, freeze. What would change next week?",
            productOwner: "What would a 3pm demo-freeze rule change about how next week is shaped?",
            developer:    "What would a 3pm demo-freeze rule change about next week?"
        ),
        "Sprint start — clean priorities.": PersonaText(
            student:      "Which of those cuts will be hardest to keep saying no to by Thursday?",
            productOwner: "Which of those cuts will be hardest to defend by Thursday — and what's the holding move?",
            developer:    "Which of the cuts will be hardest to hold the line on by Thursday?"
        ),
    ]

    // MARK: Tips — SkillTile hints (lookup keyed by tile title)

    static let tipSkillHint: [String: PersonaText] = [
        "Plan before prompting": PersonaText(
            student:      "Before you talk to the robot, write down what you want — like a shopping list before you go to the store.",
            productOwner: "Define the outcome before writing the prompt — know the value you want to ship before letting AI drive.",
            developer:    "Outline intent before asking AI to code."
        ),
        "Write CLAUDE.md": PersonaText(
            student:      "Write a sticky note for the robot, so you don't have to re-explain everything every single time.",
            productOwner: "Create a context doc — a short product spec — so every AI session starts with the same shared background.",
            developer:    "Persistent project context for every session."
        ),
        "Reject the suggestion": PersonaText(
            student:      "If the robot's answer doesn't feel right, just say 'no, try again.' That's totally allowed.",
            productOwner: "Push back when output doesn't match intent. Don't accept something just because it 'looks fine' on the surface.",
            developer:    "Say no when AI's answer doesn't fit intent."
        ),
        "Test before shipping": PersonaText(
            student:      "When you're done, try it out — don't trust the robot's word, see if it actually works.",
            productOwner: "Verify before release. AI output is a draft, not a final — your QA gate still has to do its job.",
            developer:    "Verify AI output — don't trust, verify."
        ),
    ]

    // MARK: Tips — Today's guidance hero block (localized)

    static let tipGuidanceHeadline: PersonaTextL10n? = PersonaTextL10n(
        student: L10n(
            vi: "Lập kế hoạch trước, rồi mới code.",
            en: "Make a plan first, then start coding."
        ),
        productOwner: L10n(
            vi: "Chế độ Plan cho thấy scope trước khi bạn cam kết.",
            en: "Plan mode shows the scope before you commit."
        ),
        developer: L10n(
            vi: "Chế độ Plan đã sẵn sàng khi bạn cần.",
            en: "Plan mode is ready when you are."
        )
    )

    static let tipGuidanceBody: PersonaTextL10n? = PersonaTextL10n(
        student: L10n(
            vi: "Tuần này bạn đã thêm việc mới vào dự án 3 lần. Thử vẽ ra trước khi bắt đầu — sẽ đỡ rối hơn rất nhiều.",
            en: "You added new things to your project 3 times this week. Try drawing it out before you start — it gets way less messy."
        ),
        productOwner: L10n(
            vi: "Tuần này bạn ghi nhận 3 lần thêm scope giữa sprint. Plan mode đưa scope lên trước khi engineer chạm code — để bạn còn kịp cắt khi vẫn rẻ.",
            en: "You captured 3 mid-sprint scope additions this week. Plan mode surfaces scope before engineers touch code — so you can cut while it's still cheap."
        ),
        developer: L10n(
            vi: "Tuần này bạn ghi nhận 3 lần thêm scope. Plan mode làm scope hiện rõ trước khi bạn bắt đầu — để bạn cắt thật lòng, trước khi code được viết.",
            en: "You've captured 3 scope additions this week. Plan mode makes the scope visible before you start — so you can cut things honestly, before code is written."
        )
    )

    // MARK: Per-Pet × Persona × Language — tipGuidanceHeadline localized

    /// Each pet keeps a distinctive voice (signature opener, tone, punctuation).
    /// Persona shifts vocabulary/concept (Student=simple+playful, PO=business framing, Developer=technical default).
    /// Vietnamese variants preserve the same opener/tone where possible.
    static let tipGuidanceHeadlineByPet: [String: PersonaTextL10n] = [
        "byte": PersonaTextL10n(
            student: L10n(
                vi: "...mảnh vỡ. ghi ra điều bạn muốn trước khi bắt đầu.",
                en: "...fragments. write down what you want before you start."
            ),
            productOwner: L10n(
                vi: "...nhiễu. khoanh scope trước khi build. log đọc gọn hơn theo cách đó.",
                en: "...static. scope it before you build. logs read cleaner that way."
            ),
            developer: L10n(
                vi: "...nhiễu. plan trước. log đọc dễ hơn theo cách đó.",
                en: "...static. plan first. logs read better that way."
            )
        ),
        "nova": PersonaTextL10n(
            student: L10n(
                vi: "PLAN TRƯỚC. Rồi BUILD! 🔥 Không tắt đường.",
                en: "PLAN FIRST. Then BUILD! 🔥 No shortcuts."
            ),
            productOwner: L10n(
                vi: "PLAN MODE. KHOANH SCOPE. RỒI SHIP. 🔥",
                en: "PLAN MODE. SCOPE IT. THEN SHIP. 🔥"
            ),
            developer: L10n(
                vi: "PLAN MODE. KHÔNG THƯƠNG LƯỢNG. 🔥",
                en: "PLAN MODE. NON-NEGOTIABLE. 🔥"
            )
        ),
        "crash": PersonaTextL10n(
            student: L10n(
                vi: "YOOO DỪNG. Plan trước đã, rồi đi BUILD. Không bỏ bước!",
                en: "YOOO STOP. Make a plan first, then go BUILD it. No skipping!"
            ),
            productOwner: L10n(
                vi: "YOOO DỪNG. Chốt scope trước, RỒI ship. Không nửa vời.",
                en: "YOOO STOP. Lock the scope first, THEN ship. No half-measures."
            ),
            developer: L10n(
                vi: "YOOO DỪNG. Plan nó. RỒI nghiền nát nó.",
                en: "YOOO STOP. Plan it. THEN crush it."
            )
        ),
        "luna": PersonaTextL10n(
            student: L10n(
                vi: "Này~ không vội đâu, nhưng viết ra trước khi bắt đầu nhé? Bạn làm được mà.",
                en: "Hey~ no rush, but maybe write it down before you start? You've got this."
            ),
            productOwner: L10n(
                vi: "Này~ dành một chút để khoanh scope trước nha. Đỡ phải làm lại nhiều, hứa đó.",
                en: "Hey~ take a moment to scope it first. Saves so much rework later, promise."
            ),
            developer: L10n(
                vi: "Này~ không vội đâu, nhưng phác thảo trước một chút nhé?",
                en: "Hey~ no rush, but maybe sketch it out first?"
            )
        ),
        "sage": PersonaTextL10n(
            student: L10n(
                vi: "Hít thở. Hình dung trước. Rồi bắt đầu.",
                en: "Breathe. Picture it first. Then begin."
            ),
            productOwner: L10n(
                vi: "Hít thở. Xác định kết quả. Rồi cam kết công việc.",
                en: "Breathe. Define the outcome. Then commit the work."
            ),
            developer: L10n(
                vi: "Hít thở. Vẽ đường. Rồi đi.",
                en: "Breathe. Map the path. Then walk it."
            )
        ),
        "glitch": PersonaTextL10n(
            student: L10n(
                vi: "Plan trước. Rồi phá plan chỉ khi bạn biết tại sao.",
                en: "Plan first. Then break the plan only when you know why."
            ),
            productOwner: L10n(
                vi: "Spec nó. Rồi phá spec có chủ đích, không phải tình cờ.",
                en: "Spec it. Then break the spec on purpose, not by accident."
            ),
            developer: L10n(
                vi: "Plan trước. Rồi phá plan có chủ đích.",
                en: "Plan first. Then break the plan with intent."
            )
        ),
        "null": PersonaTextL10n(
            student: L10n(
                vi: "PLAN À?! Có lẽ! Chắc luôn! Plan để plan để plan đi!",
                en: "PLAN?! Maybe! Probably! Let's plan to plan to plan!"
            ),
            productOwner: L10n(
                vi: "SCOPE À?! ĐÚNG! Hoặc là vậy! Ghim nó xuống trước khi hỗn loạn nuốt mất!",
                en: "SCOPE?! YES! Or maybe! Pin it down before chaos eats it!"
            ),
            developer: L10n(
                vi: "PLAN À?! Có lẽ. Chắc luôn. Plan để plan đi!",
                en: "PLAN?! Maybe. Probably. Let's plan to plan!"
            )
        ),
    ]

    // MARK: Helpers

    /// Resolve a `PersonaText` lookup with fallback to a plain string.
    static func resolve(
        _ table: [String: PersonaText],
        id: String,
        persona: LanguagePersona,
        fallback: String
    ) -> String {
        table[id]?.value(for: persona) ?? fallback
    }

    /// Resolve a per-pet × per-persona variant.
    /// Fallback chain: pet entry → persona-only table → plain fallback string.
    static func resolvePerPet(
        _ petTable: [String: PersonaText],
        petId: String,
        personaFallback: PersonaText?,
        persona: LanguagePersona,
        fallback: String
    ) -> String {
        if let pet = petTable[petId] {
            return pet.value(for: persona)
        }
        if let p = personaFallback {
            return p.value(for: persona)
        }
        return fallback
    }

    /// Localized variant of `resolvePerPet` — resolves per-pet × persona × language.
    /// Fallback chain: pet entry → persona+language-only table → plain fallback string.
    static func resolvePerPetL10n(
        _ petTable: [String: PersonaTextL10n],
        petId: String,
        personaFallback: PersonaTextL10n?,
        persona: LanguagePersona,
        language: AppLanguage,
        fallback: String
    ) -> String {
        if let pet = petTable[petId] {
            return pet.value(for: persona, language: language)
        }
        if let p = personaFallback {
            return p.value(for: persona, language: language)
        }
        return fallback
    }
}

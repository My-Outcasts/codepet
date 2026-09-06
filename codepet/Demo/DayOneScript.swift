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

    /// The question each department opens its segment with, in both languages.
    ///
    /// One table rather than sixteen literals in the beat list: the beats name departments, the
    /// copy lives here, and a translator edits one place. Keyed by department key so a cast
    /// remap cannot strand a question on a retired pet.
    static let questions: [String: (en: String, vi: String)] = [
        "mkt": (en: "Is this a real problem, or just yours? Talk to twelve people before you build anything.",
                vi: "Đây là vấn đề có thật, hay chỉ của riêng bạn? Hãy nói chuyện với mười hai người trước khi xây bất cứ thứ gì."),
        "sales": (en: "So who is this NOT for? The one person who found it insulting is worth more than the nine who liked it.",
                  vi: "Vậy sản phẩm này KHÔNG dành cho ai? Một người thấy bị xúc phạm đáng giá hơn chín người khen hay."),
        "design": (en: "Now that you know who it is for, what should it feel like?",
                   vi: "Giờ bạn đã biết nó dành cho ai — vậy nó nên mang lại cảm giác gì?"),
        "eng": (en: "What do you build it on — and does anything a person writes ever leave their device?",
                vi: "Bạn sẽ xây trên nền gì — và những gì người ta viết có bao giờ rời khỏi máy của họ không?"),
        "fin": (en: "What does that cost you a month? I cannot price anything until Byte has chosen.",
                vi: "Mỗi tháng tốn bao nhiêu? Tôi không thể tính giá cho đến khi Byte chọn xong."),
        "support": (en: "What happens when someone is genuinely struggling at 2am?",
                    vi: "Chuyện gì xảy ra khi ai đó thật sự khủng hoảng lúc 2 giờ sáng?"),
        "legal": (en: "Are you in trouble for holding their words? Say what you delete, and when.",
                  vi: "Bạn có gặp rắc rối khi giữ lời của họ không? Hãy nói rõ bạn xoá gì, và khi nào."),
        "ops": (en: "How do you ship without breaking it? Thursday, not Friday.",
                vi: "Làm sao để phát hành mà không làm hỏng? Thứ Năm, đừng thứ Sáu."),
    ]

    /// The question for a department, or nil when it has none.
    static func question(for deptKey: String, language: AppLanguage) -> String? {
        guard let pair = questions[deptKey] else { return nil }
        return language == .vi ? pair.vi : pair.en
    }

    static let beats: [MockFlowScript.Beat] = build([
        ("Day one", 3.2, .hold,
         "Mona has a feeling and nothing else — people are lonely and don't know how to reach "
         + "each other. No plan, no brand, no idea where to start. This is the board a founder "
         + "actually begins with: empty."),

        ("Marketing · Nova", 2.4, .petAsks(deptKey: "mkt"),
         "Nova opens. The first question is hers to answer, not Codepet's."),

        // Link 1 — Marketing · Nova. The founder's own work, and it stays that way.
        //
        // Caption trimmed: Nova's own petAsks beat above now carries the question, so
        // restating it here was the redundancy this whole change exists to remove.
        ("Marketing · Nova", 2.4, .walkthroughFounderTask,
         "Codepet won't pretend to run this one — twelve conversations are hers to have. It "
         + "prepares the guide and says so plainly."),

        ("Marketing · Nova", 2.4, .recordFounderTask(taskId: "mur-interviews"),
         "She has the conversations and records what she heard — that's what files it, and "
         + "everything after reads it."),

        // Link 2 — Marketing · Nova. Same department, same pet — it does not open twice.
        ("Marketing · Nova", 2.6, .runTask("mur-landscape"),
         "Nova reads the interviews before answering — the credit line on the card names them."),
        ("Marketing · Nova", 2.8, .approveNewestDraft,
         "Approving files it. Nothing was written anywhere until that tap, and the next "
         + "department will read what she just approved."),

        ("Sales · Nova", 2.2, .petAsks(deptKey: "sales"),
         "The same pet, a different department — Nova speaks for both."),

        // Link 3 — Sales · Nova.
        ("Sales · Nova", 2.6, .runTask("mur-notfor"),
         "The scan turns up crowded ground. The one person who found it insulting is worth "
         + "more than the nine who liked it."),
        ("Sales · Nova", 2.8, .approveNewestDraft,
         "A disqualifier list is a strange thing to be pleased about, and it is the first "
         + "artifact that makes the next four decisions easy."),

        ("Design · Luna", 2.2, .petAsks(deptKey: "design"),
         "Luna reads the two artifacts before it."),

        // Link 4 — Design · Luna.
        ("Design · Luna", 2.6, .runTask("mur-brand"),
         "Luna reads both artifacts and shapes how it should feel."),
        ("Design · Luna", 2.8, .approveNewestDraft,
         "Four questions in, and each answer has been built on the last rather than started "
         + "from the brief again."),

        ("Engineering · Byte", 2.2, .petAsks(deptKey: "eng"),
         "The first question with a bill attached."),

        // Link 5 — Engineering · Byte.
        ("Engineering · Byte", 2.6, .runTask("mur-stack"),
         "Byte reads the direction and decides what it runs on — and whether anything a "
         + "person writes ever leaves their device."),
        ("Engineering · Byte", 2.8, .approveNewestDraft,
         "That decision sets the running cost, which is why Finance is next and not first."),

        ("Finance · Crash", 2.2, .petAsks(deptKey: "fin"),
         "Crash says why this could not have been asked earlier."),

        // Link 6 — Finance · Crash.
        ("Finance · Crash", 2.6, .runTask("mur-unitcost"),
         "Cost per active user, straight from the stack Byte just chose."),
        ("Finance · Crash", 2.8, .approveNewestDraft,
         "A number she can hold against a price — the first artifact that constrains rather "
         + "than describes."),

        ("Support · Sage", 2.4, .petAsks(deptKey: "support"),
         "The question a consumer app about loneliness cannot avoid."),

        // Link 7 — Support · Sage.
        ("Support · Sage", 2.6, .runTask("mur-crisis"),
         "Sage writes what the app says at 2am, when, and what it refuses to handle."),
        ("Support · Sage", 2.8, .approveNewestDraft,
         "Written down as policy, not left to a prompt. This is the artifact the board's one "
         + "founder-only task later asks a clinician to read."),

        ("Legal · Glitch", 2.2, .petAsks(deptKey: "legal"),
         "Glitch reads Sage's policy before answering."),

        // Link 8 — Legal · Glitch.
        ("Legal · Glitch", 2.6, .runTask("mur-deletion"),
         "Glitch turns the crisis policy and the stack decision into a promise: one tap, "
         + "permanent, no email."),
        ("Legal · Glitch", 2.8, .approveNewestDraft,
         "The promise comes before the privacy policy that formalises it — which is still "
         + "sitting on her board, unwritten."),

        ("Operations · Glitch", 2.2, .petAsks(deptKey: "ops"),
         "The same pet again, and the last question before the day hands one back."),

        // Link 9 — Operations · Glitch.
        ("Operations · Glitch", 2.6, .runTask("mur-rhythm"),
         "A weekly rhythm the launch checklist will later assume."),
        ("Operations · Glitch", 2.8, .approveNewestDraft,
         "Nine questions, eight departments, nine artifacts — and every one of them traces "
         + "back to a task on her roadmap."),

        // The hand-back stays inside Operations' chapter rather than opening a tenth —
        // no beat here introduces new department content, so no new chapter should appear.
        ("Operations · Glitch", 2.6, .go(.library),
         "A week where every answer builds on the last. She started with a feeling and no "
         + "plan."),

        ("Operations · Glitch", 2.8, .go(.roadmap),
         "The beacon has moved to her tenth question — how people hear about it. Codepet "
         + "points at the landing page and waits."),
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

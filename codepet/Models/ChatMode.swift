import Foundation

/// Client-side chat "mode". Shapes the founder's raw message with an intent,
/// then hands the plain string to the existing `CompanyStore.sendChat`. There
/// is no backend concept of modes and no build session — this is pure
/// message-shaping, which is why it is a small, unit-testable value type.
enum ChatMode: CaseIterable, Identifiable {
    case ask, plan, build

    var id: Self { self }

    /// The modes the composer actually offers.
    ///
    /// Currently every case, but kept as its own property rather than collapsed
    /// into `allCases`, because the rule it encodes outlives today's contents:
    /// **a mode belongs here only once a send in that mode goes somewhere.**
    ///
    /// There were four until 14 Aug. `.engineering` — shown as "Developer" —
    /// was folded into `.build`, because the two never differed in INTENT.
    /// Ask and Plan are a real choice: answer me, versus deliberate with the
    /// team. Build and Developer both meant "change my code" and differed only
    /// in WHERE the work executed: the local `claude` CLI against a linked
    /// folder, or the cloud agent against a branch. That is infrastructure, and
    /// asking a founder to pick it per message made them understand our
    /// deployment before they could send a sentence.
    ///
    /// Worse, it was the same word twice: the composer's department chip is
    /// also "Engineering", and it ALSO reaches the local agent
    /// (`EditCodeRouting`). Three doors to two agents. Where the work runs is
    /// now the run's own business — see `CompanyStore.startBuild`.
    static var composerCases: [ChatMode] { allCases }

    /// Short control label — matches the terse pill style used elsewhere in chat.
    func label(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.ask, .vi):   return "Hỏi"
        case (.ask, _):     return "Ask"
        case (.plan, .vi):  return "Lập kế hoạch"
        case (.plan, _):    return "Plan"
        case (.build, .vi): return "Bắt tay làm"
        case (.build, _):   return "Build"
        }
    }

    /// Whether this mode may convene the Virtual Company.
    ///
    /// Founder's call, Aug 7. Until now the room was NOT mode-gated: every typed message fanned
    /// out to `virtualCompanyRun` in all three modes and the router's escape hatch alone decided
    /// whether a room appeared. That is the design's intent — the founder should not have to know
    /// when a question deserves four departments — but it has a price the design does not carry:
    /// a convened decision is measured at ~$0.20 against ~$0.005 for an ordinary turn, so a casual
    /// Ask could cost forty times what it looked like it would.
    ///
    /// Plan is where that spend is wanted and expected: it is the mode you choose when you are
    /// deciding something rather than asking something. Ask stays cheap; Build is execution, and
    /// the room deliberates rather than executes.
    ///
    /// This gates only the OPPORTUNITY. Inside Plan the router's escape hatch still decides, so
    /// choosing Plan does not force a room — it permits one.
    var convenesRoom: Bool { self == .plan }

    /// Wrap the founder's raw text with this mode's intent. `.ask` is identity.
    /// `.build` copy is deliberately modest — the chat can already run tasks and
    /// produce draft deliverables; it must NOT imply the (not-yet-native) build agent.
    func shape(_ text: String, language lang: AppLanguage) -> String {
        switch self {
        case .ask:
            return text
        case .plan:
            return lang == .vi
                ? "Giúp mình lập kế hoạch — nêu các bước cụ thể tiếp theo: \(text)"
                : "Help me plan this — give me the concrete next steps: \(text)"
        case .build:
            // IDENTITY, deliberately, and this is a change: `.build` used to
            // wrap the text with "Let's build this together…". That copy was
            // already dead — `send()` routes `.build` straight to a runner and
            // never called `shape` for it — and now that Build IS the coding
            // mode, the text goes to `engStartRun`'s `ask`, which becomes the
            // agent's instruction and the session title. Framing copy would end
            // up inside both.
            return text
        }
    }
}

import Foundation

/// Client-side chat "mode". Shapes the founder's raw message with an intent,
/// then hands the plain string to the existing `CompanyStore.sendChat`. There
/// is no backend concept of modes and no build session — this is pure
/// message-shaping, which is why it is a small, unit-testable value type.
enum ChatMode: CaseIterable, Identifiable {
    case ask, plan, build, engineering

    var id: Self { self }

    /// The modes the composer actually offers.
    ///
    /// NOT `allCases`. `.engineering` exists in the model — the run store, the
    /// client and their tests all need it — but its workspace is not built yet,
    /// and `ChatComposer` renders whatever this returns. Adding the case to the
    /// menu before there is anywhere for a send to go would put a control in
    /// front of a founder that silently does nothing; a dead affordance was
    /// already removed from this codebase once (`6982df0`) and is not worth
    /// re-adding for the sake of one fewer property.
    ///
    /// Flip `.engineering` in here when `EngineeringWorkspaceView` lands. The
    /// test named for this will fail when you do, which is the reminder.
    static var composerCases: [ChatMode] { [.ask, .plan, .build] }

    /// Short control label — matches the terse pill style used elsewhere in chat.
    func label(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.ask, .vi):   return "Hỏi"
        case (.ask, _):     return "Ask"
        case (.plan, .vi):  return "Lập kế hoạch"
        case (.plan, _):    return "Plan"
        case (.build, .vi): return "Bắt tay làm"
        case (.build, _):   return "Build"
        // The Vietnamese label is PENDING Mona's call. Every other mode here
        // has a considered translation — "Bắt tay làm" for Build, not a literal
        // rendering — and inventing one for a fourth mode would be the one part
        // of this feature written by someone who does not speak the language.
        // The English word stands in until she picks; it is a recognisable
        // loanword rather than a wrong translation.
        case (.engineering, _): return "Engineering"
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
            return lang == .vi
                ? "Cùng bắt tay làm luôn — nếu là việc bạn làm được, hãy chạy và cho mình xem bản nháp: \(text)"
                : "Let's build this together — if it's a task you can do, run it and show me a draft: \(text)"
        case .engineering:
            // IDENTITY, deliberately. The other modes wrap the founder's text
            // for a chat model that benefits from framing; this text goes to
            // `engStartRun`'s `ask`, which becomes the coding agent's task and
            // its session title. Prepending "Let's build this together" would
            // put copy into the instruction the agent acts on, and into the
            // title the founder later scans a list of runs by.
            return text
        }
    }
}

import Foundation

/// Client-side chat "mode". Shapes the founder's raw message with an intent,
/// then hands the plain string to the existing `CompanyStore.sendChat`. There
/// is no backend concept of modes and no build session — this is pure
/// message-shaping, which is why it is a small, unit-testable value type.
enum ChatMode: CaseIterable, Identifiable {
    case ask, plan, build

    var id: Self { self }

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
        }
    }
}

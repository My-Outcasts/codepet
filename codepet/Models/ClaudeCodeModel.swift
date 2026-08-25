import Foundation

/// A specific Claude model the founder's own plan can answer with.
///
/// **Pinned versions, not aliases — a reversal, on the founder's call.** An earlier version
/// of this offered `opus`/`sonnet`/`haiku` aliases, on the reasoning that an alias tracks
/// the latest of its tier and cannot go stale. That is true and it was the wrong trade for
/// this product: a founder who wants Opus 4.6 specifically cannot ask an alias for it, and
/// "the newest Opus" silently changing under them is exactly the loss of control they were
/// asking to avoid.
///
/// The cost of pinning is real and worth naming: when a new model ships, this list does not
/// know about it until someone adds it. `.inherit` is the escape hatch — it passes no
/// `--model` flag, so a founder who has selected something newer in their own Claude Code
/// keeps it.
///
/// **Every id below was verified against the CLI on 2.1.241**, not read off a docs page.
/// Each answered a real turn and reported itself back in `modelUsage`.
enum ClaudeCodeModel: String, CaseIterable, Identifiable, Equatable {
    /// Pass no `--model` at all. The default, because a founder who chose a model in their
    /// own CLI already answered this, and overriding that would be Codepet deciding
    /// something they decided.
    case inherit

    case fable5     = "claude-fable-5"
    case opus5      = "claude-opus-5"
    case sonnet5    = "claude-sonnet-5"
    case haiku45    = "claude-haiku-4-5"
    case opus48     = "claude-opus-4-8"
    case opus47     = "claude-opus-4-7"
    case opus46     = "claude-opus-4-6"
    case sonnet46   = "claude-sonnet-4-6"

    var id: String { rawValue }

    /// The `--model` value, or nil to pass no flag.
    var flag: String? { self == .inherit ? nil : rawValue }

    /// What the founder sees. Short, because it sits in the composer next to the send
    /// button and competes with the message they are writing.
    var shortName: String {
        switch self {
        case .inherit:  return "Auto"
        case .fable5:   return "Fable 5"
        case .opus5:    return "Opus 5"
        case .sonnet5:  return "Sonnet 5"
        case .haiku45:  return "Haiku 4.5"
        case .opus48:   return "Opus 4.8"
        case .opus47:   return "Opus 4.7"
        case .opus46:   return "Opus 4.6"
        case .sonnet46: return "Sonnet 4.6"
        }
    }

    /// The current generation, offered first. Ordered strongest to cheapest rather than
    /// alphabetically, because the list is a spend decision.
    static let current: [ClaudeCodeModel] = [.fable5, .opus5, .sonnet5, .haiku45]

    /// Previous generations, behind a submenu. Kept because a founder who tuned a prompt
    /// against one of these has a real reason to pin it, and "the newest" is not always the
    /// one that behaves the way their work expects.
    static let older: [ClaudeCodeModel] = [.opus48, .opus47, .opus46, .sonnet46]

    func note(_ lang: AppLanguage) -> String {
        switch self {
        case .inherit:
            return lang == .vi ? "Để Claude Code của bạn tự chọn." : "Let your Claude Code choose."
        case .fable5:
            return lang == .vi ? "Mạnh nhất, tốn hạn mức nhất. Gói của bạn có thể chưa có."
                               : "Most capable, heaviest on quota. Your plan may not include it."
        case .opus5:
            return lang == .vi ? "Cho việc phức tạp." : "For complex work."
        case .sonnet5:
            return lang == .vi ? "Cân bằng. Hợp hầu hết câu hỏi." : "Balanced. Fine for most questions."
        case .haiku45:
            return lang == .vi ? "Nhanh và rẻ hạn mức nhất." : "Fastest, cheapest on quota."
        case .opus48, .opus47, .opus46, .sonnet46:
            return lang == .vi ? "Thế hệ trước." : "Previous generation."
        }
    }
}

/// How much thinking the turn gets.
///
/// Verified on 2.1.241 that `--effort` is accepted alongside every model above, Haiku 4.5
/// included — the API rejects `effort` on some models, but the CLI absorbs that rather than
/// passing the error through, so the picker does not have to hide levels per model.
enum ClaudeCodeEffort: String, CaseIterable, Identifiable, Equatable {
    /// Pass no `--effort`. The default: Claude Code's own default is `high` for most work,
    /// and re-declaring someone else's default is how the two silently diverge later.
    case inherit
    case low, medium, high, xhigh, max

    var id: String { rawValue }
    var flag: String? { self == .inherit ? nil : rawValue }

    var shortName: String {
        switch self {
        case .inherit: return "Auto"
        case .low:     return "Low"
        case .medium:  return "Medium"
        case .high:    return "High"
        case .xhigh:   return "XHigh"
        case .max:     return "Max"
        }
    }

    static let choices: [ClaudeCodeEffort] = [.inherit, .low, .medium, .high, .xhigh, .max]
}

/// The founder's model and effort choice, persisted per company id.
///
/// Per company for the reason `ClaudeCodeAuthorisation` records: one Mac can hold two
/// accounts, and A's taste is not B's. Closures rather than direct `UserDefaults` reads so
/// tests never touch the real domain.
struct ClaudeCodeModelPreference {
    static func modelKey(_ companyId: String) -> String { "cp_claudeModel_\(companyId)" }
    static func effortKey(_ companyId: String) -> String { "cp_claudeEffort_\(companyId)" }

    var model: (String) -> ClaudeCodeModel = { companyId in
        guard let raw = UserDefaults.standard.string(forKey: modelKey(companyId)),
              let parsed = ClaudeCodeModel(rawValue: raw) else { return .inherit }
        return parsed
    }

    var setModel: (String, ClaudeCodeModel) -> Void = { companyId, model in
        UserDefaults.standard.set(model.rawValue, forKey: modelKey(companyId))
    }

    var effort: (String) -> ClaudeCodeEffort = { companyId in
        guard let raw = UserDefaults.standard.string(forKey: effortKey(companyId)),
              let parsed = ClaudeCodeEffort(rawValue: raw) else { return .inherit }
        return parsed
    }

    var setEffort: (String, ClaudeCodeEffort) -> Void = { companyId, effort in
        UserDefaults.standard.set(effort.rawValue, forKey: effortKey(companyId))
    }
}

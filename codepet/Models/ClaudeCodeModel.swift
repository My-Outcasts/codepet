import Foundation

/// Which Claude model the founder's own plan should answer with.
///
/// **Aliases, not pinned versions, and that is the point.** `claude --model opus` resolves
/// to whatever the latest Opus is; a pinned `claude-opus-5` would quietly become last
/// year's model the moment a new one shipped, and nothing in this app would notice. All
/// four were verified against 2.1.241 rather than taken from documentation:
///
///     haiku  → claude-haiku-4-5-20251001
///     sonnet → claude-sonnet-5
///     opus   → claude-opus-5
///     fable  → claude-fable-5
///
/// **This is the founder's money, so the copy says what each one costs them.** It is not
/// Codepet's bill any more — the whole reason the choice can be theirs at all is that the
/// spend moved onto their plan.
enum ClaudeCodeModel: String, CaseIterable, Identifiable, Equatable {
    /// Whatever their Claude Code is already set to. The default, because a founder who has
    /// picked a model in their own CLI has already answered this question, and overriding
    /// that silently would be Codepet deciding something they had decided.
    case inherit
    case haiku
    case sonnet
    case opus
    case fable

    var id: String { rawValue }

    /// The `--model` value, or nil to pass no flag at all and let Claude Code choose.
    var alias: String? {
        switch self {
        case .inherit: return nil
        case .haiku: return "haiku"
        case .sonnet: return "sonnet"
        case .opus: return "opus"
        case .fable: return "fable"
        }
    }

    func title(_ lang: AppLanguage) -> String {
        switch self {
        case .inherit: return lang == .vi ? "Theo Claude Code của bạn" : "Whatever your Claude Code uses"
        case .haiku: return "Haiku"
        case .sonnet: return "Sonnet"
        case .opus: return "Opus"
        case .fable: return "Fable"
        }
    }

    /// One line on what picking this costs the founder, in quota rather than dollars —
    /// quota is what they actually run out of.
    func note(_ lang: AppLanguage) -> String {
        switch self {
        case .inherit:
            return lang == .vi ? "Không truyền cờ nào; Claude Code tự quyết."
                               : "Passes no flag; Claude Code decides."
        case .haiku:
            return lang == .vi ? "Nhanh và rẻ hạn mức nhất. Trả lời ngắn hơn."
                               : "Fastest, cheapest on quota. Shorter answers."
        case .sonnet:
            return lang == .vi ? "Cân bằng. Hợp cho hầu hết câu hỏi."
                               : "Balanced. Fine for most questions."
        case .opus:
            return lang == .vi ? "Mạnh hơn, tiêu hạn mức nhanh hơn."
                               : "Stronger, burns quota faster."
        case .fable:
            return lang == .vi ? "Mạnh nhất và đắt hạn mức nhất. Có thể gói của bạn chưa có."
                               : "Most capable, heaviest on quota. Your plan may not include it."
        }
    }

    /// Which models a plan can actually reach is not something the app can enumerate — the
    /// CLI answers `unrecognized_model` or a permission error at call time, and there is no
    /// endpoint that lists them. So every option is offered and a plan that cannot serve one
    /// fails that turn honestly, rather than Codepet guessing a restriction and hiding a
    /// model the founder does in fact have.
    ///
    /// Deliberately NOT paired with `--fallback-model`. It exists and would paper over an
    /// overloaded model, but it also answers with a model the founder did not choose, and
    /// `CompanyStore.swift:743` records why this app refuses silent substitution. A failed
    /// turn they can retry beats an answer from somewhere they did not ask for.
    static let all = ClaudeCodeModel.allCases
}

/// The founder's model choice, persisted.
///
/// Keyed per company id for the reason `ClaudeCodeAuthorisation` records: one Mac can hold
/// two accounts, and A's taste is not B's. Closures rather than direct `UserDefaults` reads
/// so tests never touch the real domain.
struct ClaudeCodeModelPreference {
    static func key(_ companyId: String) -> String { "cp_claudeModel_\(companyId)" }

    var model: (String) -> ClaudeCodeModel = { companyId in
        guard let raw = UserDefaults.standard.string(forKey: key(companyId)),
              let parsed = ClaudeCodeModel(rawValue: raw) else { return .inherit }
        return parsed
    }

    var setModel: (String, ClaudeCodeModel) -> Void = { companyId, model in
        UserDefaults.standard.set(model.rawValue, forKey: key(companyId))
    }
}

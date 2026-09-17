// codepet/Services/BlockedOffer.swift
import Foundation

/// What a blocked surface should actually show the founder.
///
/// `LocalTransportRouter.transport()` returns the plain `.notGranted` because it must not
/// spend a subprocess probing on every call (its own doc comment says so). This turns that
/// bare reason into something actionable, using an install status probed once —
/// `InstalledProviders`, which is the one place that knows both facts (what is blocked, and
/// what is on disk) at the same time. The router still doesn't know; the VIEW does, and this
/// is where that knowledge is applied.
///
/// Kept as a plain value type with a static resolver — same reasoning as `ProvenanceRow`,
/// `ProviderGrantRow` and `OnboardingProviderStep`: a test calls `resolve` with no store, no
/// view, no `@MainActor` object to crash the XCTest host on deallocation (landmine 3).
enum BlockedOffer: Equatable {
    /// Installed, ungranted: ask for this provider's grant, right here.
    case grant(AIProvider)
    /// Nothing installed: a grant would be an instruction nobody can follow.
    case install
    /// Not a consent problem, or a Claude-only surface with no Claude Code to grant. Say the
    /// reason and offer nothing that would run.
    case explain(BlockReason)

    /// Which providers a surface may run on. `LocalTransportRouter.chooseProvider` picks
    /// freely between both; `ChatTransportRouter` (chat) and the virtual company meeting
    /// hardcode Claude and take no `prefer` — a parameter nobody may pass is an invitation to
    /// pass it, so the distinction is carried here instead, as a fact about the SURFACE.
    enum Surface: Equatable {
        /// The one-shot ops: build, run-task, reflection chat. Either provider may run it.
        case anyProvider
        /// Chat streaming and the virtual company meeting. Claude Code or nothing.
        case claudeOnly
    }

    /// **Precedence matches `LocalTransportRouter.chooseProvider` exactly, and that is not a
    /// coincidence to be re-derived independently.** Two orders that can disagree would offer
    /// one provider here and then actually run the other one when the founder acts on it.
    static func resolve(reason: BlockReason, installed: Set<AIProvider>,
                        surface: Surface = .anyProvider) -> BlockedOffer {
        guard reason == .notGranted else { return .explain(reason) }
        if surface == .claudeOnly {
            // This surface cannot run on Codex at all, installed or not — so the only grant
            // worth offering is Claude's, and a Codex-only (or empty) machine gets told what
            // the surface actually needs instead of a button that cannot work.
            return installed.contains(.claudeCode) ? .grant(.claudeCode) : .explain(.needsClaudeCode)
        }
        for candidate in [AIProvider.claudeCode, .codex] where installed.contains(candidate) {
            return .grant(candidate)
        }
        return .install
    }

    /// What to say, in the founder's language.
    func founderText(lang: AppLanguage) -> String {
        switch self {
        case .grant(let provider):
            let reason = BlockReason.notGrantedFor(provider)
            return lang == .vi ? reason.founderTextVi : reason.founderText
        case .install:
            // Reached only on `.anyProvider` with neither CLI present — Claude Code would
            // serve equally well as Codex here, so naming just one is the specific wrong
            // answer the spec calls out ("she has a plan, just not that one"). Deliberately
            // its own copy, not `BlockReason.claudeCodeMissing` (which is Claude-specific and
            // used nowhere else): reusing it would say "install Claude Code" to a founder who
            // has never touched Anthropic and pays for ChatGPT instead. Framing matches
            // `OnboardingProviderStep`'s gate ("Install either one") so the product speaks
            // with one voice at both surfaces.
            return lang == .vi
                ? "Codepet chạy trên Claude Code hoặc Codex. Cài đặt một trong hai rồi thử lại."
                : "Codepet runs on Claude Code, or Codex. Install either one, then try again."
        case .explain(let reason):
            return lang == .vi ? reason.founderTextVi : reason.founderText
        }
    }
}

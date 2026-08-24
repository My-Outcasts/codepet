// codepet/Models/DepartmentRouter.swift
import Foundation

/// Which department a chat turn belongs to, and how sure we are.
///
/// **Why this is its own type.** Both recorded routing regressions came from one function
/// answering two questions at once, and `DepartmentCompanions` has already been split once for
/// exactly that reason — `actingSpecialist` → `actingDeptKey`, whose comment says the fusion
/// "cost the answer". *Who speaks*, *what they know*, and *how sure we are* are three
/// questions. This file owns the third and only the third: it returns a department key and
/// never resolves a pet. `DepartmentCompanions.specialistId(for:host:)` still decides whether
/// there is a handoff to show, which is why `host` is not a parameter here.
///
/// **Tier order is the safety model.** Tier 1 is `mentionedDeptKey`, unchanged and first, so
/// every message that routes today routes identically. The new tiers can only produce an
/// answer where there was none — never a different one.
enum DepartmentRouter {
    enum Tier: Equatable {
        /// The founder addressed a department by name — "ask finance". Today's behaviour.
        case addressed
        /// The founder's words match a department's vocabulary. New, and guarded (§4.3).
        case topical
        /// Nothing in this draft, but a department owns the conversation. New.
        case carryOver
    }

    struct Suggestion: Equatable {
        let deptKey: String
        let tier: Tier
        /// The term that fired, for the founder-facing "you mentioned …" hover. nil at tiers
        /// that matched on something other than a word. The view composes the sentence, so
        /// this stays a bare term and stays localizable.
        let matched: String?
    }

    /// The department to suggest, or nil to leave the turn with the host.
    ///
    /// Pure and deterministic: same inputs, same answer, no clock, no network, no state. That
    /// is what lets the two August regressions be held down by tests rather than by hope.
    static func suggest(text: String,
                        tasks: [RoadmapTask],
                        lastActed: String?,
                        language: AppLanguage) -> Suggestion? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Tier 1 — addressed by name. Today's rule, first, unchanged.
        if let key = DepartmentCompanions.mentionedDeptKey(in: trimmed) {
            return Suggestion(deptKey: key, tier: .addressed, matched: nil)
        }

        // Tier 4 — nothing to go on. Tiers 2 and 3 land between these in Tasks 4 and 5.
        return nil
    }
}

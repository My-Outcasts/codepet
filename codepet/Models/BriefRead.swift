// codepet/Models/BriefRead.swift
import Foundation

/// The greeting's "here's what I understood" paragraph, composed from the founder's own brief.
///
/// **Composed locally, on purpose.** Chat is `.claudeOnly` and blocked until the founder grants
/// her plan, so a model-written welcome would either arrive blocked on a fresh account or force
/// the permission ask to the front of onboarding — the trade `OnboardingProviderStep` exists to
/// avoid. This is a pure function over `CompanyBrief`.
///
/// **What it may read.** Only the fields `CompanyOnboardingModel.brief` actually fills:
/// `oneLiner`, `audience`, `stage`, plus `summary` when a later brief edit enriched it.
/// `goal`, `traction`, `problem`, `runway` and `constraints` are nil for every real founder —
/// written only by the enrich interview, which has no caller in the app — and non-nil only in
/// the Murror fixture, which is the worst possible place for a paragraph to look correct.
///
/// Kept outside any `@MainActor ObservableObject` — landmine 3 — so a test exercises it with no
/// store and no view.
enum BriefRead {

    /// The paragraph, or nil when there is nothing worth saying.
    ///
    /// **The anchor rule.** `stage` is the only field that is always present
    /// (`CompanyOnboardingModel` defaults it to "Building"), so a naive composition would emit
    /// "You're at the Building stage." for a founder who typed nothing else — telling her what
    /// she picked from a slider and calling it a read. The paragraph therefore requires
    /// `summary` or `oneLiner`; audience and stage are trimmings on that anchor, never the
    /// whole sentence.
    static func compose(brief: CompanyBrief, language: AppLanguage) -> String? {
        // `MeaningfulText.clean`, not `??` — it rejects a one-character answer, an all-digits
        // one and an email address. The convention for this exact field at `RoadmapView:62`.
        guard let anchor = MeaningfulText.clean(brief.summary)
                        ?? MeaningfulText.clean(brief.oneLiner) else { return nil }

        let vi = language == .vi
        var out = vi ? "Đây là những gì mình hiểu: \(sentence(anchor))"
                     : "Here's what I understood: \(sentence(anchor))"

        if let audience = MeaningfulText.clean(brief.audience) {
            out += vi ? " Dành cho \(sentence(audience))" : " It's for \(sentence(audience))"
        }
        if let stage = MeaningfulText.clean(brief.stage) {
            out += vi ? " Bạn đang ở giai đoạn \(stageLabel(stage, vi: true))."
                      : " You're at the \(stageLabel(stage, vi: false)) stage."
        }
        return out
    }

    /// Ends a founder-typed fragment with a full stop without doubling one she already typed.
    private static func sentence(_ raw: String) -> String {
        let last = raw.last
        return (last == "." || last == "!" || last == "?") ? raw : raw + "."
    }

    /// The five values `CompanyOnboardingModel.stages` can produce, translated.
    ///
    /// They are English literals in that array, so the Vietnamese read has to map them or it
    /// splices an English word into a Vietnamese sentence. Anything else — an older brief, a
    /// hand-edited document — passes through unchanged rather than vanishing.
    private static func stageLabel(_ raw: String, vi: Bool) -> String {
        guard vi else { return raw.lowercased() }
        switch raw {
        case "Idea":         return "ý tưởng"
        case "Prototype":    return "nguyên mẫu"
        case "Building":     return "đang xây dựng"
        case "Private beta": return "beta kín"
        case "Launched":     return "đã ra mắt"
        default:             return raw
        }
    }
}

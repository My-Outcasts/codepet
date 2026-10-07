// codepet/Models/FounderChoice.swift
import Foundation

/// The room's open question as two options to pick (CP-031). The call card used to end on a
/// ~120-word "Unresolved — your call" paragraph with the actual choice buried in it; when the
/// room returns exactly two options, the card offers them instead and the lock-in names the
/// pick. The paragraph is still in "Read the full call".
enum FounderChoice {
    /// The options to offer, or nil to keep the paragraph. Exactly two, both with text.
    static func options(_ brief: VCBrief) -> [VCFounderOption]? {
        guard let o = brief.founderOptions, o.count == 2,
              o.allSatisfy({ !$0.label.trimmingCharacters(in: .whitespaces).isEmpty
                             && !$0.consequence.trimmingCharacters(in: .whitespaces).isEmpty })
        else { return nil }
        return o
    }

    /// The room's call with the founder's pick as THE decision (7 Oct): the recommendation becomes
    /// the pick, the trade-off names what she turned down, and no open choice is left. What the
    /// Team build planner and its build step read, so neither settles the choice on its own.
    static func decided(_ brief: VCBrief, pick: VCFounderOption) -> VCBrief {
        let others = (brief.founderOptions ?? []).filter { $0.label != pick.label }.map(\.label)
        let turnedDown = others.isEmpty ? ""
            : " The founder turned down: " + others.map { "\"\($0)\"" }.joined(separator: ", ") + "."
        return VCBrief(recommendation: "\(pick.label): \(pick.consequence)",
                       confidence: brief.confidence, confidenceReason: brief.confidenceReason,
                       theRealDisagreement: brief.theRealDisagreement,
                       tradeoffFounderMustOwn: "The founder chose \"\(pick.label)\"." + turnedDown,
                       killCriteria: brief.killCriteria, nextAction: brief.nextAction,
                       whatWeDontKnow: brief.whatWeDontKnow, unresolved: false, founderOptions: nil)
    }

    static func lockInTitle(_ pick: VCFounderOption?, lang: AppLanguage) -> String {
        guard let pick else { return lang == .vi ? "Chọn một để chốt" : "Pick one to lock in" }
        return (lang == .vi ? "Chốt: " : "Lock in: ") + pick.label
    }
}

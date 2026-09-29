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

    static func lockInTitle(_ pick: VCFounderOption?, lang: AppLanguage) -> String {
        guard let pick else { return lang == .vi ? "Chọn một để chốt" : "Pick one to lock in" }
        return (lang == .vi ? "Chốt: " : "Lock in: ") + pick.label
    }
}

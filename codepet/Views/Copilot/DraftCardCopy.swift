// codepet/Views/Copilot/DraftCardCopy.swift
import Foundation

/// Copy and one decision for the draft card, kept out of the view so the suite can pin them.
///
/// **Why the note exists.** "Nothing is committed until you approve it" is the product's
/// governing promise, and the app stated it BEFORE a run (`BeaconOffer`: "you approve before it
/// is filed") and confirmed it AFTER ("Added to Library") — with nothing in between. So at the
/// one moment it becomes concrete, the founder was looking at a finished-LOOKING deliverable
/// beside a button marked Approve, with no indication it was unsaved.
enum DraftCardCopy {

    /// Whether to tell the founder this draft is not filed yet.
    ///
    /// **A pure static, not a condition in `draftCard`'s body.** Same reasoning as
    /// `DraftPayloadPreview.hasStructuredPreview`: the decision is where a bug here would live,
    /// and a decision inside a `View` body is only testable by rendering it.
    ///
    /// `hasApproved` is `company.firstApprovalAt != nil` — it retires because the rule was
    /// LEARNED, not because a counter ran out. `draftApproved` suppresses it on a card that
    /// already says "Added to Library": two answers to one question is worse than none.
    static func shouldShowNotFiledNote(hasApproved: Bool, draftApproved: Bool) -> Bool {
        !hasApproved && !draftApproved
    }

    /// The note itself. Wording fixed by
    /// `docs/superpowers/specs/2026-09-04-first-run-approval-note-design.md`.
    ///
    /// "Not saved yet" rather than "Not approved yet": the founder can see it is unapproved —
    /// the Approve button is right there. What they cannot see is that unapproved means unsaved.
    static func notFiledNote(_ lang: AppLanguage) -> String {
        lang == .vi
            ? "Chưa lưu — duyệt để đưa vào Thư viện."
            : "Not saved yet — approving files it in your Library."
    }
}

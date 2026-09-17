// codepet/Views/Settings/PrototypeSettingsCopy.swift
import Foundation

/// What Settings says while prototype mode is standing in for the company.
///
/// **The contradiction this resolves.** Prototype mode swaps the COMPANY for a fixture and
/// leaves the ACCOUNT alone — so the sidebar says "A fixture company, 0 credits. Nothing is
/// written to your account" while, two clicks away, Advanced said "Your progress stays saved
/// in the cloud" and Billing and Usage rendered the founder's real numbers. Both halves were
/// telling the truth about a different half, and nothing on screen said which was which. The
/// effect is that the whole mode reads as untrustworthy: if one of those sentences is wrong,
/// the founder has no way to know which.
///
/// Nothing is hidden, deliberately. Billing, Usage and the profile are not WRONG in prototype
/// mode — that account genuinely exists and those numbers are genuinely its own — so hiding
/// them would trade a confusing screen for a misleading one, and a founder who wants to check
/// their real usage mid-demo should not have to leave the demo to do it. The defect was never
/// that real data is visible; it is that the screen did not say which half is real.
///
/// A pure type rather than inline ternaries, for the same reason
/// `DraftCardCopy.shouldShowNotFiledNote` is one: the decision is then testable without
/// rendering a view or standing up a Firebase session, and both languages stay in one place
/// where a future edit cannot update the English and quietly leave the Vietnamese lying.
enum PrototypeSettingsCopy {

    /// The sign-out row's description.
    ///
    /// In prototype mode the old sentence was simply false about what the founder is looking
    /// at: no fixture run is saved anywhere. It is still true about their real account, which
    /// is why the replacement says both halves rather than dropping the reassurance.
    static func signOutDescription(prototypeOn: Bool, lang: AppLanguage) -> String {
        guard prototypeOn else {
            return lang == .vi ? "Tiến trình của bạn vẫn được lưu trên đám mây."
                               : "Your progress stays saved in the cloud."
        }
        return lang == .vi
            ? "Công ty mẫu này không được lưu. Tiến trình thật của bạn vẫn ở trên đám mây."
            : "Nothing from this fixture company was saved. Your real progress stays in the cloud."
    }

    /// The one line at the top of Settings naming the split.
    ///
    /// On every panel rather than only Billing and Usage: the founder arrives at whichever
    /// section they clicked, and a note that appears on some sections teaches nothing about
    /// the ones it does not appear on.
    static func accountIsRealNote(lang: AppLanguage) -> String {
        lang == .vi
            ? "Chế độ nguyên mẫu — công ty là dữ liệu mẫu. Tài khoản, thanh toán và mức dùng bên dưới là thật."
            : "Prototype mode — the company is a fixture. Your account, billing and usage below are real."
    }

    /// What the Email row shows.
    ///
    /// It is the ONE real-account field in an otherwise fixture profile — the name beside it
    /// comes from `brief.founderName`, which both fixtures hardcode — so while prototype mode
    /// stands in for an account it rendered a bare em-dash. That reads as missing data ("why
    /// is my email blank?") when the truthful statement is that there is no account here and
    /// the demo does not need one.
    ///
    /// A real address still wins whenever there is one: signing in during prototype mode is a
    /// legitimate state, and blanking a founder's own email to keep the demo tidy would be the
    /// same species of lie in the other direction.
    static func emailValue(realEmail: String?, prototypeOn: Bool, lang: AppLanguage) -> String {
        if let realEmail, !realEmail.isEmpty { return realEmail }
        guard prototypeOn else { return "—" }
        return lang == .vi ? "Không có tài khoản — bản demo" : "No account — demo"
    }

    /// Whether that note belongs on screen at all.
    ///
    /// Separate from the string so the RULE is what the test pins. A test asserting the
    /// sentence's wording passes whether or not the sentence is ever rendered — which is the
    /// exact gap that let the contradiction ship.
    static func showsAccountIsRealNote(prototypeOn: Bool) -> Bool { prototypeOn }
}

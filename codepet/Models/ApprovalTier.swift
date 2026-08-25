// codepet/Models/ApprovalTier.swift
import Foundation

/// How much rope a Developer session gets — spec §8.2.
///
/// **Three gates get conflated, and only the first is friction:** step approvals
/// during a run, the commit gate (a reading, not an interruption), and the ceiling
/// (never automatic). A tier moves the first two. Nothing moves the third.
///
/// Per-session rather than global, because the right answer is different on your own
/// repo and on a client's — and the default is the permissive middle, because
/// defaulting to `Ask me` ships the complaint as the default.
enum ApprovalTier: String, CaseIterable, Identifiable, Codable {
    /// Every file edit and every command prompts.
    case askMe
    /// Edits and test runs inside the folder proceed silently; stops for anything
    /// outside it and for network installs. **The default.**
    case worksOnItsOwn
    /// No step prompts, and it commits to the session branch itself.
    case letItRun

    var id: String { rawValue }

    static let standard = ApprovalTier.worksOnItsOwn

    /// The prototype's own keys (`data-t`), kept identical so the two can be
    /// compared without a translation table — and because a mismatch here is
    /// invisible until someone reads both by hand.
    var prototypeKey: String {
        switch self {
        case .askMe:         return "ask"
        case .worksOnItsOwn: return "own"
        case .letItRun:      return "run"
        }
    }

    var icon: String {
        switch self {
        case .askMe:         return "hand.raised"
        case .worksOnItsOwn: return "play"
        case .letItRun:      return "bolt"
        }
    }

    func label(_ lang: AppLanguage) -> String {
        switch self {
        case .askMe:
            return lang == .vi ? "Hỏi tôi" : "Ask me"
        case .worksOnItsOwn:
            return lang == .vi ? "Tự làm" : "Works on its own"
        case .letItRun:
            return lang == .vi ? "Cứ chạy" : "Let it run"
        }
    }

    func detail(_ lang: AppLanguage) -> String {
        switch self {
        case .askMe:
            return lang == .vi
                ? "Mọi sửa tệp và mọi lệnh đều hỏi."
                : "Every file edit and every command prompts."
        case .worksOnItsOwn:
            return lang == .vi
                ? "Sửa tệp và chạy kiểm thử trong thư mục thì cứ làm. Dừng lại với bất cứ gì ngoài thư mục, với cài đặt qua mạng, và luôn dừng ở bước commit."
                : "Edits and test runs inside the folder proceed. It stops for anything "
                + "outside it, for network installs, and always for the commit."
        case .letItRun:
            return lang == .vi
                ? "Không hỏi từng bước, và tự commit lên nhánh của phiên — bạn sẽ không thấy diff trước."
                : "No step prompts, and it commits to the session branch itself — "
                + "you will not see the diff first."
        }
    }

    /// **Does the commit stop for a human?**
    ///
    /// The one axis the app can actually honour today, and the one §8.3 calls an
    /// amendment to a written rail: Codepet never writes the real tree without
    /// approval *unless the founder has selected `Let it run` for this session*.
    var promptsBeforeCommit: Bool { self != .letItRun }

    /// Whether every step is supposed to prompt.
    var promptsEveryStep: Bool { self == .askMe }

    /// **Whether the app can keep this tier's promise today.**
    ///
    /// `Ask me` cannot be honoured and is offered disabled rather than silently
    /// behaving like the middle tier. Gating individual steps needs a runner that
    /// can SUSPEND between tool uses and resume on an answer; `CodeRunning.run` is
    /// one call that returns an outcome, and the real backend is the `claude` CLI
    /// running its own tool loop in a subprocess — its permission prompts are its
    /// own, not ours to intercept. Shipping the chip anyway would mean a founder
    /// selecting "every command prompts" and getting a run that prompts for nothing,
    /// which is the most dangerous possible direction for this control to be wrong in.
    var isHonoured: Bool { !promptsEveryStep }

    func unavailableReason(_ lang: AppLanguage) -> String? {
        guard !isHonoured else { return nil }
        return lang == .vi
            ? "Chưa dùng được: cần một runner có thể dừng giữa các bước."
            : "Not available yet — needs a runner that can pause between steps."
    }

    /// What no tier lifts. Kept next to the tiers on purpose: the ceiling is the
    /// reason a permissive tier is safe to offer at all, so the two belong in one
    /// file and one test.
    static func ceiling(_ lang: AppLanguage) -> String {
        lang == .vi
            ? "merge · deploy · xoá · force-push · chạm vào tệp ngoài thư mục"
            : "merge · deploy · delete · force-push · touch a file outside the folder"
    }
}

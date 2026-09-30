// codepet/Models/DeliverableFieldText.swift
import Foundation

/// How the CP-002 C fields read as text — one definition for Copy, the exported file and a Team
/// Build's `docs/`, which each used to spell out a checklist line by hand. Empty fields render as
/// nothing, so a deliverable filed before the fields existed reads exactly as it did.

private func nonEmpty(_ s: String?) -> String? {
    guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
    return t
}

extension ChecklistItem {
    /// "you · before launch", or nil when the step has neither.
    var meta: String? {
        let parts = [nonEmpty(owner), nonEmpty(due)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// `- [ ] Buy the domain — you · today`
    var markdownLine: String {
        "- [\(done ? "x" : " ")] \(t)" + (meta.map { " — \($0)" } ?? "")
    }
}

extension DocSection {
    var sourceText: String? { nonEmpty(source) }
}

extension DeliverablePayload {
    var rulesOutItems: [String] { (rulesOut ?? []).compactMap(nonEmpty) }
    var emailSubject: String? { nonEmpty(subject) }
    var emailTo: String? { nonEmpty(to) }
    var postPlatform: String? { nonEmpty(platform) }
}

/// A post against its platform's limit. Counted in grapheme clusters, which is what a person
/// counts; X weights URLs and some emoji differently, so a post within a character or two of the
/// limit can still be refused there. It is a warning before publishing, not the platform's check.
struct PostLength: Equatable {
    let count: Int
    let limit: Int
    var over: Int { max(0, count - limit) }

    init?(body: String, limit: Int?) {
        guard let limit, limit > 0 else { return nil }
        self.count = body.trimmingCharacters(in: .whitespacesAndNewlines).count
        self.limit = limit
    }

    func label(_ lang: AppLanguage) -> String {
        over > 0
            ? (lang == .vi ? "\(count) / \(limit) ký tự — dư \(over)" : "\(count) / \(limit) characters — \(over) over")
            : (lang == .vi ? "\(count) / \(limit) ký tự" : "\(count) / \(limit) characters")
    }
}

/// "To: the two who asked to pay" — an email's recipient line, as the card draws it and as the
/// chat transcript copies it. "" when there is no recipient, so callers can skip it.
enum RecipientLine {
    static func text(_ recipient: String?, _ lang: AppLanguage) -> String {
        guard let r = nonEmpty(recipient) else { return "" }
        return (lang == .vi ? "Gửi tới: " : "To: ") + r
    }
}

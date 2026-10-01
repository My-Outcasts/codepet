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

extension CalendarItem {
    /// "T-5 · verify · X · Marketing" — whichever of the four the item has, in that order. One
    /// definition for Copy and the Team Build markdown; the viewer draws the same four as chips.
    var tags: String {
        [when, format, channel, owner].compactMap(nonEmpty).joined(separator: " · ")
    }
}

/// What a screen's illustration slot shows (CP-002 E3). `art` was one of three values, forced to
/// "connect" when it was anything else; it is a free description now.
enum ScreenArt: Equatable {
    /// One of the three the viewer has art for, as its SF Symbol pairing.
    case symbols(primary: String, secondary: String)
    /// Anything else: a description of a picture the app cannot draw.
    case brief(String)
    case none

    init(_ art: String) {
        switch art.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "connect": self = .symbols(primary: "link", secondary: "person.2")
        case "session": self = .symbols(primary: "bubble.left.and.bubble.right", secondary: "sparkles")
        case "recap":   self = .symbols(primary: "checkmark.seal", secondary: "chart.bar")
        case "":        self = .none
        case let d:     self = .brief(d)
        }
    }
}

// codepet/Models/LibraryVersions.swift
import Foundation

/// What the Library shows about an item's version history (CP-025 follow-up, design option A):
/// a "V3" badge on the card, and a "v3 ▾" menu in the detail header that previews an older
/// version in place and offers Restore. Pure, so the decisions are pinned by
/// `LibraryVersionsTests` rather than by rendering a view.
enum LibraryVersions {

    /// One row of the version menu. `historyIndex` is the position in `Deliverable.versions`
    /// (what `LibraryFiling.restore` takes); nil for the current version.
    struct Entry: Equatable {
        let number: Int
        let isCurrent: Bool
        let historyIndex: Int?
        let createdAt: String?
    }

    /// "V3" when the item has been revised; nil when it never has — a badge on every card would
    /// say nothing.
    static func badge(for item: Deliverable) -> String? {
        guard let history = item.versions, !history.isEmpty else { return nil }
        return "V\(history.count + 1)"
    }

    /// Current first, then older versions newest first. Empty for an item never revised: a menu
    /// with one choice is a control with nothing to choose.
    static func entries(for item: Deliverable) -> [Entry] {
        guard let history = item.versions, !history.isEmpty else { return [] }
        let top = history.count + 1
        return [Entry(number: top, isCurrent: true, historyIndex: nil, createdAt: item.createdAt)]
            + history.enumerated().map { i, v in
                Entry(number: top - 1 - i, isCurrent: false, historyIndex: i, createdAt: v.createdAt)
            }
    }

    /// The item as it looked at that version — same id, that version's title, body, kind and
    /// payload (a Site or sheet is drawn from its payload). An index that does not exist shows
    /// the current version rather than nothing.
    static func preview(of item: Deliverable, historyIndex: Int) -> Deliverable {
        guard let history = item.versions, history.indices.contains(historyIndex) else { return item }
        let v = history[historyIndex]
        var shown = item
        shown.title = v.title
        shown.body = v.body
        shown.createdAt = v.createdAt
        shown.kind = v.kind ?? item.kind
        shown.payload = v.payload
        return shown
    }

    /// "24 Sep 04:06" in the given zone; "" when the date is missing or unreadable.
    static func dateLabel(_ iso: String?, timeZone: TimeZone = .current) -> String {
        guard let iso else { return "" }
        let parse = ISO8601DateFormatter()
        parse.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        guard let date = parse.date(from: iso) ?? plain.date(from: iso) else { return "" }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.timeZone = timeZone
        out.dateFormat = "d MMM HH:mm"
        return out.string(from: date)
    }
}

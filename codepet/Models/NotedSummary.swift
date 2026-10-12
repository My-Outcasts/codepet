import Foundation

/// The one line a reply's remembered facts fold into (12 Oct design pass).
///
/// Three facts used to print as three grey pills, each repeating "📌 Noted · topic —" before a
/// full sentence — a block taller than many answers, saying three times what one line says. One
/// fact still reads inline; several collapse to a count and their topics, and the sentences open
/// on click. Never hidden outright: the line is the only receipt that memory changed, and the
/// only place a wrong fact can be caught before it is recalled in a later chat.
enum NotedSummary {
    /// "Noted · burn — Tiffin burns $6k a month." for one fact; "Noted 3 facts · burn, cash,
    /// runway" for several. Nil when there is nothing to acknowledge.
    static func line(_ facts: [RememberedFact], lang: AppLanguage) -> String? {
        guard let first = facts.first else { return nil }
        let vi = lang == .vi
        if facts.count == 1 {
            return (vi ? "Đã ghi nhớ" : "Noted") + " · \(first.topic) — \(first.statement)"
        }
        let topics = facts.map(\.topic).joined(separator: ", ")
        return (vi ? "Đã ghi nhớ \(facts.count) điều" : "Noted \(facts.count) facts") + " · \(topics)"
    }

    /// Only several facts fold; a single one is already a line.
    static func folds(_ facts: [RememberedFact]) -> Bool { facts.count > 1 }
}

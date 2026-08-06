// codepet/Models/BriefDocument.swift
import Foundation

/// THE CALL, as a document instead of a chat message.
///
/// The card used to render seven sections from eight `VCBrief` fields — about 550 words, nothing
/// clamped, inside a 380pt dock column, with two more expanded cards under it (founder, Aug 7:
/// "the text is too cramped, there's no breathing room"). A plan that long needs margins, headings
/// and one column, which a transcript cannot give it.
///
/// So the long half becomes a `Deliverable` of kind `.doc` and opens in `DeliverableDetailView` —
/// the same reader an approved deliverable opens into. The founder's call, asked directly: the call
/// should read like every other document in the app. That also means `DocViewer` does the layout,
/// so this file only has to decide what belongs in the document and in what order.
///
/// What deliberately does NOT come here, because the contract pins it to the card:
/// `tradeoff_founder_must_own` (rule 5 — the room ends on the either/or), `unresolved` (rule 6),
/// `confidence` (rule 7 — dots, and only on the card). The document repeats none of them.
enum BriefDocument {

    /// The decision in one line — the card's headline.
    ///
    /// The first sentence of `recommendation`, which the model reliably writes as the call itself
    /// ("Don't build a pricing plan this week — run a price test this week."). Everything after it
    /// is the reasoning, and the reasoning is what the document is for.
    static func headline(_ recommendation: String) -> String {
        let text = recommendation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        // An em-dash clause is part of the call, so only sentence enders split it. A decimal or an
        // abbreviation would split wrongly on ".", so the terminator must be followed by a space.
        var end: String.Index?
        var i = text.startIndex
        while i < text.endIndex {
            if ".!?".contains(text[i]) {
                let next = text.index(after: i)
                if next == text.endIndex || text[next] == " " || text[next] == "\n" {
                    end = next
                    break
                }
            }
            i = text.index(after: i)
        }
        guard let end else { return text }
        let first = String(text[text.startIndex..<end]).trimmingCharacters(in: .whitespaces)
        // A opener of two or three words is a throat-clear, not the call — "Two things.",
        // "Concretely:", "Short answer." — so fall back to the whole paragraph rather than headline
        // the card with something that says nothing.
        //
        // Counted in WORDS, not characters. A character threshold got this wrong: "Run the test
        // this week." is 23 characters and a complete decision, and a 24-character cutoff called it
        // a fragment. Length does not distinguish a sentence from a throat-clear; word count does.
        let words = first.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
        return words >= 4 ? first : text
    }

    /// True when the recommendation carries more than its headline, i.e. the reader has something
    /// to show. A one-sentence call needs no "Read the full call" button.
    static func hasMore(_ brief: VCBrief) -> Bool {
        if headline(brief.recommendation) != brief.recommendation
            .trimmingCharacters(in: .whitespacesAndNewlines) { return true }
        return !brief.killCriteria.isEmpty
            || !brief.whatWeDontKnow.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !brief.nextAction.action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The document the reader opens. Order is reading order, not field order: the call, then what
    /// to do about it, then what would kill it, then what nobody knew.
    static func document(_ brief: VCBrief, language: AppLanguage) -> Deliverable {
        let vi = language == .vi
        var sections: [DocSection] = []

        let owner = brief.nextAction.owner.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = brief.nextAction.action.trimmingCharacters(in: .whitespacesAndNewlines)
        if !action.isEmpty {
            sections.append(DocSection(
                h: (vi ? "Việc tiếp theo" : "Do this next") + (owner.isEmpty ? "" : " · \(owner)"),
                p: action))
        }
        if !brief.killCriteria.isEmpty {
            sections.append(DocSection(h: vi ? "Dừng nếu" : "Stop if",
                                       p: brief.killCriteria.map { "· \($0)" }
                                           .joined(separator: "\n")))
        }
        let unknown = brief.whatWeDontKnow.trimmingCharacters(in: .whitespacesAndNewlines)
        if !unknown.isEmpty {
            sections.append(DocSection(h: vi ? "Vẫn chưa biết" : "Still unknown", p: unknown))
        }

        return Deliverable(
            kind: .doc,
            title: vi ? "Quyết định" : "The call",
            // `body` is the plain-text fallback for anything that reads a deliverable without the
            // typed payload (search, a future export). It is not what the reader draws.
            body: brief.recommendation,
            payload: DeliverablePayload(call: brief.recommendation, sections: sections)
        )
    }
}

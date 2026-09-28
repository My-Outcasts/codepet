// codepet/Models/StepAskSummary.swift
import Foundation

/// The one- or two-line version of what a Team Build step was asked to do (CP-035).
///
/// Step detail used to open with the whole instruction sent to the department (around 380 words
/// on a real run), in the raw form the model received, above the result the founder actually
/// wanted. The result now comes first; this is the ask as a reader needs it, and the full
/// instruction is one click away.
enum StepAskSummary {
    static let defaultLimit = 200

    static func summary(_ instruction: String, limit: Int = defaultLimit) -> String {
        let text = DraftPreview.plain(instruction).trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > limit else { return text }
        let head = String(text.prefix(limit))
        // The last sentence end inside the limit, if there is one past the first quarter.
        if let end = head.lastIndex(where: { ".!?".contains($0) }),
           head.distance(from: head.startIndex, to: end) >= limit / 4 {
            return String(head[...end])
        }
        let cut = head.lastIndex(of: " ").map { String(head[..<$0]) } ?? head
        return cut.trimmingCharacters(in: .whitespaces) + "…"
    }

    static func isShortened(_ instruction: String, limit: Int = defaultLimit) -> Bool {
        DraftPreview.plain(instruction).trimmingCharacters(in: .whitespacesAndNewlines).count > limit
    }
}

import Foundation

/// A lightweight, generic grader for the prompt the user writes during an
/// exercise. Unlike `PromptAnalyzer` (which needs per-scenario required
/// elements), this scores any prompt on the universal qualities of a good
/// agentic-coding instruction, so every SkillChallenge can grade a from-scratch
/// prompt without bespoke data. Rule-based — costs zero tokens.
enum PracticePromptGrader {

    struct Grade: Equatable {
        let score: Int          // 0–100
        let letter: String      // S / A / B / C / D
        let checklist: [Check]  // the 4 qualities of a good prompt, met or not

        /// One quality of a good agentic-coding prompt.
        struct Check: Equatable {
            let met: Bool
            let label: String   // short name, e.g. "Names a place"
            let hint: String    // beginner-friendly guidance + example, shown when not met
        }

        // Kept for any caller that just wants flat lists.
        var strengths: [String] { checklist.filter { $0.met }.map { $0.label } }
        var tips: [String] { checklist.filter { !$0.met }.map { $0.hint } }
    }

    private static let actionVerbs = [
        "extract", "move", "create", "add", "wrap", "refactor", "split",
        "rename", "replace", "validate", "handle", "show", "make", "build", "fix"
    ]

    static func grade(prompt: String, goal: String) -> Grade {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.lowercased()
        let words = text.split { $0 == " " || $0 == "\n" }.count

        var score = 0
        var checklist: [Grade.Check] = []

        // 1) Enough detail to act on (0–30)
        let detailMet = words >= 12
        if words >= 25 { score += 30 } else if words >= 12 { score += 18 }
        checklist.append(.init(
            met: detailMet,
            label: "Enough detail",
            hint: words >= 12
                ? "Almost — add a touch more so it's unmistakable: what to change, where, and what it should look like when done."
                : "It's very short. Describe the change in a full sentence or two, the way you'd explain it to a teammate who can't see your screen."
        ))

        // 2) A concrete action verb (0–20)
        let verbMet = actionVerbs.contains(where: { lower.contains($0) })
        if verbMet { score += 20 }
        checklist.append(.init(
            met: verbMet,
            label: "Clear action",
            hint: "Begin with a doing-word so the task is obvious — e.g. \"Create…\", \"Add…\", \"Move…\", \"Wrap…\", \"Validate…\"."
        ))

        // 3) Names a target — a file, component, or place (0–25)
        let targetMet = mentionsTarget(lower)
        if targetMet { score += 25 }
        checklist.append(.init(
            met: targetMet,
            label: "Names a place",
            hint: "Point to where it goes — name a file or part, e.g. \"in a new file app/lib/utils.ts\" or \"the sign-up form\"."
        ))

        // 4) States an outcome / acceptance (0–25)
        let outcomeMet = lower.contains("so that") || lower.contains("should") ||
            lower.contains("make sure") || lower.contains("without breaking") ||
            lower.contains("still work") || lower.contains("instead of")
        if outcomeMet { score += 25 }
        checklist.append(.init(
            met: outcomeMet,
            label: "Says what 'done' looks like",
            hint: "Add the result you want, starting with \"so that…\" — e.g. \"…so that both pages use it instead of repeating the code.\""
        ))

        score = min(100, score)
        return Grade(score: score, letter: letter(for: score), checklist: checklist)
    }

    private static func mentionsTarget(_ lower: String) -> Bool {
        if lower.contains(".tsx") || lower.contains(".ts") || lower.contains(".js")
            || lower.contains("file") || lower.contains("component")
            || lower.contains("function") || lower.contains("section")
            || lower.contains("form") || lower.contains("page") { return true }
        return false
    }

    private static func letter(for score: Int) -> String {
        switch score {
        case 90...: return "S"
        case 75..<90: return "A"
        case 60..<75: return "B"
        case 40..<60: return "C"
        default: return "D"
        }
    }
}

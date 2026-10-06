// codepet/Models/MeetingQuietCard.swift
import Foundation

/// The meeting's process as five fixed steps (6 Oct design pass). One quiet strip at the top of
/// the meeting card replaces "0 of 2 answered", the empty roster bars and the separate progress
/// row — and keeps rule 1 (the process is visible while it happens) in one line.
///
/// The current step is read off `VCProgressStage`, the same stage the old row printed, so the
/// strip and the old wording cannot disagree. A room that skips negotiating (everyone aligned)
/// goes from Comparing straight to Call; the strip shows Negotiating as passed, which is true.
enum MeetingSteps {
    static func current(_ stage: VCProgressStage) -> Int {
        switch stage {
        case .routing:     return 0
        case .answering:   return 1
        case .comparing:   return 2
        case .negotiating: return 3
        case .finishing:   return 4
        }
    }

    static func titles(_ lang: AppLanguage) -> [String] {
        lang == .vi ? ["Hỏi", "Trả lời", "So sánh", "Thương lượng", "Kết luận"]
                    : ["Asked", "Answering", "Comparing", "Negotiating", "Call"]
    }
}

/// Founder-facing words for the room's wire values.
enum MeetingWords {
    /// Under the department's name, in place of a tinted "with conditions" chip.
    static func stance(_ stance: String, lang: AppLanguage) -> String {
        switch (stance, lang) {
        case ("proceed", .vi):                 return "Nên làm"
        case ("proceed", _):                   return "Yes"
        case ("proceed_with_conditions", .vi): return "Làm, có điều kiện"
        case ("proceed_with_conditions", _):   return "Yes, with conditions"
        case ("do_not_proceed", .vi):          return "Không nên"
        default:                               return "No"
        }
    }

    /// Beside the dots (rule 7: dots, never a number — a word is not a number).
    static func confidence(_ value: Int, lang: AppLanguage) -> String {
        let vi = lang == .vi
        switch value {
        case ...2: return vi ? "Chưa chắc lắm" : "Not very sure"
        case 3:    return vi ? "Khá chắc" : "Fairly sure"
        case 4:    return vi ? "Chắc" : "Sure"
        default:   return vi ? "Rất chắc" : "Very sure"
        }
    }

    /// Rule 4: each side's `what_would_change_my_mind`. The wire carries it on negotiation
    /// TURNS, not on positions, so this is the department's latest non-blank turn — and nil
    /// before negotiating starts, rather than an invented line.
    static func changesMind(_ agentId: String, rounds: [VCNegotiationRound]) -> String? {
        for round in rounds.reversed() {
            if let t = round.turns.last(where: { $0.agent == agentId }) {
                let line = t.whatWouldChangeMyMind.trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty { return line }
            }
        }
        return nil
    }

    /// A column shows the answer's first full sentence; the rest is one click away. Clamped at a
    /// sentence, never rewritten (rule 2). Same sentence rule as the call's headline.
    static func lead(_ position: String) -> String {
        BriefDocument.headline(position)
    }

    static func hasMore(_ position: String) -> Bool {
        lead(position) != position.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "Design, Sales and Legal".
    static func list(_ names: [String], lang: AppLanguage) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + (lang == .vi ? " và " : " and ") + names.last!
        }
    }

    /// "Design and Sales are in the room" — replaces the IN THE ROOM / SAT OUT cells.
    static func inTheRoom(_ names: [String], lang: AppLanguage) -> String {
        let joined = list(names, lang: lang)
        if lang == .vi { return "\(joined) đang họp" }
        return names.count == 1 ? "\(joined) is in the room" : "\(joined) are in the room"
    }
}

/// Where the departments sit on the meeting card.
enum MeetingSeats {
    /// Column counts to try, widest first: everyone in one row up to three, a 2×2 grid for four,
    /// and one stacked column as the last resort (the dock is 380 pt wide).
    static func columnChoices(count: Int) -> [Int] {
        guard count > 1 else { return [1] }
        return count <= 3 ? [count, 1] : [2, 1]
    }

    /// The room's departments in seat order. The chief of staff and the challenger have no
    /// department key and take no seat — they speak in the call, not as a side.
    static func departments(_ agents: [VCAgentMeta]) -> [VCAgentMeta] {
        agents.filter { $0.departmentKey != nil }
    }
}

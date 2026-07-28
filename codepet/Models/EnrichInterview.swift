// codepet/Models/EnrichInterview.swift
import Foundation

/// One of the three plan-shaping brief fields the first-run interview fills,
/// in priority order. Verbatim-logic port of the web `Gap` (lib/ai/enrichInterview.ts).
enum InterviewGap: String, CaseIterable, Equatable, Codable {
    case goal, traction, problem
}

/// byte's question for a gap plus the one-line reason it's asking (so it reads
/// like a companion, not a form).
struct InterviewQuestion: Equatable {
    let ask: String
    let why: String
}

/// Pure, dependency-free gap detector + static question copy. No I/O, no LLM —
/// unit-tested. The web distills answers via a server route; we intentionally
/// save the founder's raw text instead, so there is no distill logic here.
enum EnrichInterview {
    /// Priority order: goal (drives task priority), then traction (grounds the
    /// numbers), then problem (sharpens positioning). `detectGaps` preserves it.
    static let gapOrder: [InterviewGap] = [.goal, .traction, .problem]

    /// The most gaps byte asks about in one interview — keep it short.
    static let maxQuestions = 3

    private static func filled(_ v: String?) -> Bool {
        guard let v else { return false }
        return !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func value(_ brief: CompanyBrief, _ gap: InterviewGap) -> String? {
        switch gap {
        case .goal: return brief.goal
        case .traction: return brief.traction
        case .problem: return brief.problem
        }
    }

    /// The empty plan-shaping fields, in priority order. A nil brief means ask all
    /// three; a full brief returns []. Never more than `maxQuestions`.
    static func detectGaps(_ brief: CompanyBrief?) -> [InterviewGap] {
        guard let brief else { return Array(gapOrder.prefix(maxQuestions)) }
        return Array(gapOrder.filter { !filled(value(brief, $0)) }.prefix(maxQuestions))
    }

    /// Static question + why-line per gap, localized. EN ported from the web
    /// `QUESTION_FOR`; VI added natively.
    static func question(for gap: InterviewGap, language: AppLanguage) -> InterviewQuestion {
        switch gap {
        case .goal:
            return language == .vi
                ? InterviewQuestion(
                    ask: "Mục tiêu chính của bạn trong vài tuần tới là gì?",
                    why: "để mình ưu tiên những việc thật sự đưa bạn tới đó trước")
                : InterviewQuestion(
                    ask: "What\u{2019}s your main goal for the next few weeks?",
                    why: "so byte plans the moves that actually get you there first")
        case .traction:
            return language == .vi
                ? InterviewQuestion(
                    ask: "Hiện tại bạn đang ở đâu — danh sách chờ, người dùng, doanh thu, đã có gì chạy chưa?",
                    why: "để các con số trong kế hoạch là của bạn, không phải bịa ra")
                : InterviewQuestion(
                    ask: "Where are you right now — waitlist, users, revenue, anything live yet?",
                    why: "so the numbers in your plan are yours, not made up")
        case .problem:
            return language == .vi
                ? InterviewQuestion(
                    ask: "Sản phẩm giải quyết vấn đề gì, và ai cảm nhận rõ nhất?",
                    why: "để định vị và nội dung của bạn nói đúng người dùng thật")
                : InterviewQuestion(
                    ask: "What problem does it solve, and who feels it most?",
                    why: "so your positioning and copy speak to the real user")
        }
    }
}

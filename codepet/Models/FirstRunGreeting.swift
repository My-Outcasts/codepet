// codepet/Models/FirstRunGreeting.swift
import Foundation

/// The one-tap "Do it with me: {task}" action carried by the first-run greeting.
struct FirstRunAction: Equatable {
    let taskId: String
    let taskTitle: String
}

/// The first-run greeting: byte's opening message + an optional inline action.
struct FirstRunGreeting: Equatable {
    let text: String
    let action: FirstRunAction?
    /// Whether this greeting offers the first-run tour.
    ///
    /// Always true today. Carried as a field rather than assumed at the call site so
    /// `CompanyStore` does not have to know which greetings do — the day one of them
    /// should not (a returning founder, say), this is the single place that decides.
    let offersTour: Bool
}

/// Pure builder — verbatim-logic port of the web `buildFirstRunGreeting`
/// (lib/onboarding/firstRun.ts). No I/O; unit-tested.
enum FirstRunGreetingBuilder {
    /// - Parameter tasks: the whole board. `nextStep` names ONE task; the shape line counts
    ///   them all, so the count cannot be derived from what was already passed.
    static func build(brief: CompanyBrief, nextStep: RoadmapTask?,
                      tasks: [RoadmapTask], language: AppLanguage) -> FirstRunGreeting {
        let who = (brief.founderName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let projRaw = (brief.projectName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let proj = projRaw.isEmpty ? (language == .vi ? "sản phẩm của bạn" : "your product") : projRaw

        let lead: String
        if who.isEmpty {
            lead = language == .vi
                ? "Công ty cho \(proj) đã sẵn sàng."
                : "Your company for \(proj) is ready."
        } else {
            lead = language == .vi
                ? "\(who), công ty cho \(proj) đã sẵn sàng."
                : "\(who), your company for \(proj) is ready."
        }

        // The two new paragraphs, either of which may be absent. Collected as optionals and
        // joined ONCE below: appending to a string with conditional "\n\n" prefixes is how a
        // dropped middle paragraph leaves a hole, and a brief with no readable anchor is the
        // common case on first run.
        let middle = [BriefRead.compose(brief: brief, language: language),
                      RoadmapShapeLine.compose(tasks: tasks, language: language)]

        guard let task = nextStep else {
            let tail = language == .vi
                ? "Cứ khám phá xung quanh — mở bất kỳ phần nào trong công ty để xem mình đã chuẩn bị gì, và mình sẽ làm cùng bạn khi bạn sẵn sàng."
                : "Take a look around — open any part of your company to see what I've lined up, and I'll produce the work with you whenever you're ready."
            return FirstRunGreeting(text: paragraphs([lead] + middle + [tail]),
                                    action: nil, offersTour: true)
        }

        let tail = language == .vi
            ? "Bước đầu tốt nhất là \"\(task.title)\". Bạn muốn mình làm cùng bạn ngay tại đây chứ? Mình soạn bản nháp, bạn duyệt — không có gì được xuất bản nếu bạn chưa đồng ý."
            : "The best first move is \"\(task.title)\". Want me to do it with you, right here? I'll draft it and you approve — nothing ships without your say-so."
        return FirstRunGreeting(text: paragraphs([lead] + middle + [tail]),
                                action: FirstRunAction(taskId: task.id, taskTitle: task.title),
                                offersTour: true)
    }

    /// Joins the paragraphs that exist. `CopilotChatView.prose` splits on blank lines and
    /// renders one block per paragraph, so "\n\n" is the separator it expects.
    private static func paragraphs(_ parts: [String?]) -> String {
        parts.compactMap { $0 }
             .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
             .filter { !$0.isEmpty }
             .joined(separator: "\n\n")
    }
}

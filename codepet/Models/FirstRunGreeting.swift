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
}

/// Pure builder — verbatim-logic port of the web `buildFirstRunGreeting`
/// (lib/onboarding/firstRun.ts). No I/O; unit-tested.
enum FirstRunGreetingBuilder {
    static func build(brief: CompanyBrief, nextStep: RoadmapTask?, language: AppLanguage) -> FirstRunGreeting {
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

        guard let task = nextStep else {
            let tail = language == .vi
                ? " Cứ khám phá xung quanh — mở bất kỳ phần nào trong công ty để xem mình đã chuẩn bị gì, và mình sẽ làm cùng bạn khi bạn sẵn sàng."
                : " Take a look around — open any part of your company to see what I've lined up, and I'll produce the work with you whenever you're ready."
            return FirstRunGreeting(text: lead + tail, action: nil)
        }

        let tail = language == .vi
            ? " Bước đầu tốt nhất là \"\(task.title)\". Bạn muốn mình làm cùng bạn ngay tại đây chứ? Mình soạn bản nháp, bạn duyệt — không có gì được xuất bản nếu bạn chưa đồng ý."
            : " The best first move is \"\(task.title)\". Want me to do it with you, right here? I'll draft it and you approve — nothing ships without your say-so."
        return FirstRunGreeting(text: lead + tail,
                                action: FirstRunAction(taskId: task.id, taskTitle: task.title))
    }
}

import Foundation

/// Pure landing-state for the empty chat: greeting + the live roadmap signals
/// that drive the landing cards. Deterministic given `now`. SwiftUI-free.
struct ChatLandingState {
    let greeting: String
    let question: String
    let beacon: RoadmapTask?
    let needsYouCount: Int
    let awaitingApprovalCount: Int
    let isEmpty: Bool

    init(company: CompanyState, now: Date, language: AppLanguage) {
        let founderRaw = (company.brief.founderName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let founder = founderRaw.isEmpty ? (language == .vi ? "bạn" : "there") : founderRaw
        let hour = Calendar.current.component(.hour, from: now)
        let part: String
        switch hour {
        case ..<12:   part = language == .vi ? "Chào buổi sáng" : "Good morning"
        case 12..<18: part = language == .vi ? "Chào buổi chiều" : "Good afternoon"
        default:      part = language == .vi ? "Chào buổi tối" : "Good evening"
        }
        greeting = "\(part), \(founder)."

        let projectRaw = (company.brief.projectName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let project = projectRaw.isEmpty ? "Codepet" : projectRaw
        question = language == .vi ? "Hôm nay mình xây gì cho \(project)?" : "What should we build for \(project) today?"

        let tasks = company.tasks
        let next = RoadmapEngine.nextStep(tasks)
        beacon = next
        needsYouCount = tasks.filter { RoadmapEngine.status(for: $0, in: tasks) == .needsYou && $0.id != next?.id }.count
        awaitingApprovalCount = tasks.filter { RoadmapEngine.status(for: $0, in: tasks) == .needsApproval }.count
        isEmpty = tasks.isEmpty
    }
}

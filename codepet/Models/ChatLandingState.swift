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
    /// The one word of `question` the hero accents — the prototype's `.greet b`.
    /// A gradient across the whole line (what the dock does) makes the sentence
    /// itself the decoration; accenting the verb points at the thing being offered.
    let accentWord: String

    /// `accountName` is the signed-in account's display name (`AppState.displayName`,
    /// captured from Firebase). Defaulted so callers that have no account context —
    /// previews, tests — keep working; the live chat passes it, because a founder
    /// who signed in with Google should not be greeted as a stranger by an app that
    /// already has their name.
    init(company: CompanyState, now: Date, language: AppLanguage, accountName: String? = nil) {
        let hour = Calendar.current.component(.hour, from: now)
        let part: String
        switch hour {
        case ..<12:   part = language == .vi ? "Chào buổi sáng" : "Good morning"
        case 12..<18: part = language == .vi ? "Chào buổi chiều" : "Good afternoon"
        default:      part = language == .vi ? "Chào buổi tối" : "Good evening"
        }
        // No name → "Good afternoon.", not "Good afternoon, there." See `FounderName`.
        greeting = FounderName.greeting(part: part, brief: company.brief, accountName: accountName)

        let projectRaw = (company.brief.projectName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let project = projectRaw.isEmpty ? "Codepet" : projectRaw
        question = language == .vi ? "Hôm nay mình xây gì cho \(project)?" : "What should we build for \(project) today?"
        accentWord = language == .vi ? "xây" : "build"

        let tasks = company.tasks
        let next = RoadmapEngine.nextStep(tasks)
        beacon = next
        needsYouCount = tasks.filter { RoadmapEngine.status(for: $0, in: tasks) == .needsYou && $0.id != next?.id }.count
        awaitingApprovalCount = tasks.filter { RoadmapEngine.status(for: $0, in: tasks) == .needsApproval }.count
        isEmpty = tasks.isEmpty
    }

    /// `question` split into runs, with exactly the first occurrence of `accentWord`
    /// marked. Returns one unaccented run when the word is absent — a founder whose
    /// project name happens to contain the verb must not get a second highlight, and
    /// a language whose phrasing drops it must not get none at all.
    var questionSegments: [(text: String, accent: Bool)] {
        guard !accentWord.isEmpty, let r = question.range(of: accentWord) else {
            return [(question, false)]
        }
        var out: [(String, Bool)] = []
        let lead = String(question[question.startIndex..<r.lowerBound])
        let tail = String(question[r.upperBound...])
        if !lead.isEmpty { out.append((lead, false)) }
        out.append((String(question[r]), true))
        if !tail.isEmpty { out.append((tail, false)) }
        return out
    }
}

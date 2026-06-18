import Foundation
import Combine

/// Drives the "Sprout × Byte" hardcoded demo. Pure state — no I/O, no API
/// calls. Hotkey input drives the methods on this controller, and the
/// Reflection tab renders from its @Published state.
@MainActor
final class DemoScriptController: ObservableObject {

    @Published private(set) var firedMilestones: [DemoScript.Milestone] = []
    @Published private(set) var reflectionRevealed: Bool = false
    @Published private(set) var sessionStartedAt: Date? = nil

    /// Currently-displayed health-nudge modal (⌥6/⌥7/⌥8). Modal-style — pops
    /// up over the app instead of being logged as a Turn. Set by
    /// `fireHealthStage`, cleared by `dismissHealthModal`.
    @Published var activeHealthModal: DemoScript.HealthStage? = nil

    /// Display language for resolving L10n fields when synthesizing
    /// `demoSession`. Driven by `AppState.uiLanguage` via CodePetApp.
    @Published var language: AppLanguage = .vi

    func startSession(now: Date = Date()) {
        sessionStartedAt = now
        firedMilestones = []
        reflectionRevealed = false
        activeHealthModal = nil
    }

    func fireMilestone(index: Int) {
        guard sessionStartedAt != nil else { return }
        guard let milestone = DemoScript.milestones.first(where: { $0.index == index }) else { return }
        guard !firedMilestones.contains(where: { $0.index == index }) else { return }
        firedMilestones.append(milestone)
    }

    /// Fires one of the 3 health-rhythm stages (⌥6/⌥7/⌥8). Pops up a modal
    /// over the app — does NOT log a Turn into the chat history. Replaces
    /// any currently-active modal so consecutive ⌥6→⌥7→⌥8 just swap content.
    func fireHealthStage(index: Int) {
        guard sessionStartedAt != nil else { return }
        guard let stage = DemoScript.healthStages.first(where: { $0.index == index }) else { return }
        activeHealthModal = stage
    }

    /// Dismiss the health-nudge modal (Đóng button / Esc / click outside).
    func dismissHealthModal() {
        activeHealthModal = nil
    }

    func revealReflection() {
        guard sessionStartedAt != nil else { return }
        reflectionRevealed = true
    }

    func reset() {
        firedMilestones = []
        reflectionRevealed = false
        sessionStartedAt = nil
        activeHealthModal = nil
    }

    /// Populate the Tips tab with sample data so it looks live during demos.
    /// Bound to ⌥9.
    func populateTipsDemo(tipsState: TipsState, petId: String) {
        // Reset all tips state first so repeated ⌥9 presses don't stack
        tipsState.reset()
        TipsPersistence.shared.resetAll()

        // Simulate some skill practice across the active pet's 4 skills
        // Skill 0: mastered (5/5)
        for _ in 0..<5 { tipsState.recordPractice(for: petId, index: 0) }
        // Skill 1: in-progress (3/5)
        for _ in 0..<3 { tipsState.recordPractice(for: petId, index: 1) }
        // Skill 2: just started (1/5)
        tipsState.recordPractice(for: petId, index: 2)
        // Skill 3: untouched (0/5)

        // Mark one setup item as completed
        tipsState.markSetupCompleted(petId: petId, index: 0)
        tipsState.markSetupCompleted(petId: petId, index: 1)

        // Inject a mock daily guidance result
        let isVi = language == .vi
        tipsState.currentGuidance = GuidanceResult(
            headline: isVi
                ? "Tuần này bạn đang viết test nhiều hơn trước"
                : "You're writing more tests this week than before",
            project: "money-tracking",
            strength: isVi
                ? "3 trong 5 session gần đây có test — một thói quen rất tốt."
                : "3 of your last 5 sessions included tests — a really solid habit.",
            gap: isVi
                ? "Nhưng các edge case (trường hợp hiếm) thì chưa được cover."
                : "But the edge cases (the rare, tricky inputs) aren't covered yet.",
            move: isVi
                ? "Lần tới, thêm một test cho một edge case bạn nghĩ có thể làm hỏng app."
                : "Next time, add one test for an edge case you think could break the app.",
            status: "new",
            mood: "proud",
            generatedAt: Date()
        )
    }

    /// "Panic" skip: forces all 4 milestones to be fired + reveals the
    /// reflection. Bound to ⌥0 for safety during live demo if something
    /// gets out of order.
    func panicSkip() {
        if sessionStartedAt == nil { startSession() }
        for milestone in DemoScript.milestones {
            if !firedMilestones.contains(where: { $0.index == milestone.index }) {
                firedMilestones.append(milestone)
            }
        }
        reflectionRevealed = true
    }

    // MARK: - Synthesized production-shape data

    /// Synthesizes a `Session` (with Turns, Narratives, optional summary) from
    /// the current demo state, shaped exactly like a production session so the
    /// existing ReflectionTab UI renders it without any branching. L10n fields
    /// are resolved with `self.language`.
    /// Returns nil before `startSession()` is called.
    var demoSession: Session? {
        guard let start = sessionStartedAt else { return nil }
        let lang = language

        let turns: [Turn] = firedMilestones.map { milestone in
            let turnTime = start.addingTimeInterval(
                TimeInterval(milestone.offsetMinutesFromStart * 60)
            )
            let narrative = Narrative(
                title: milestone.sidebarLabel(lang),
                whatYouWanted: milestone.whatYouWanted(lang),
                whatHappened: milestone.whatHappened(lang),
                lesson: milestone.lesson(lang),
                nextSteps: milestone.nextSteps.map { $0(lang) } ?? "",
                mood: milestone.mood,
                model: "demo",
                generatedAt: turnTime,
                schemaVersion: 1
            )
            return Turn(
                id: "\(DemoScript.sessionId):turn-\(milestone.index)",
                sessionId: DemoScript.sessionId,
                startedAt: turnTime,
                endedAt: turnTime.addingTimeInterval(60),
                prompt: milestone.prompt,
                rawEvents: [],
                narrative: narrative,
                state: .ready,
                cwd: nil
            )
        }

        let summary: SessionSummary? = reflectionRevealed
            ? SessionSummary(
                sessionId: DemoScript.sessionId,
                summary: DemoScript.reflectionSummary(lang),
                lesson: DemoScript.reflectionSessionLesson(lang),
                generatedAt: Date(),
                model: "demo",
                schemaVersion: 1
            )
            : nil

        return Session(
            id: DemoScript.sessionId,
            turns: turns,
            startedAt: start,
            endedAt: nil,
            summary: summary,
            projectPath: nil,
            filePaths: []
        )
    }
}

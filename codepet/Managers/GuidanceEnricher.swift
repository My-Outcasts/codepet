import Foundation
import Combine
import os

/// Fetches AI-generated daily guidance from the Cloud Function and writes
/// the result into `TipsState.currentGuidance`. Designed to be called once
/// per app launch (or once per day) — skips the network call if today's
/// guidance is already cached in `TipsState`.
///
/// Not registered as an @EnvironmentObject itself — it's a service owned
/// by `ReflectionComposition` (or called directly from the Tips tab).
@MainActor
final class GuidanceEnricher: ObservableObject {

    private let api: ReflectionAPIClientProtocol
    private let logger = Logger(subsystem: "app.murror.codepet", category: "GuidanceEnricher")

    /// Last error from a failed fetch, for UI display.
    @Published private(set) var lastError: String?

    init(api: ReflectionAPIClientProtocol) {
        self.api = api
    }

    /// Fetch daily guidance if needed. Reads recent narratives from the
    /// narrative store to build context for the AI.
    ///
    /// - Parameters:
    ///   - tipsState: The central tips state to write guidance into.
    ///   - narrativeStore: Source of recent turn narratives for context.
    ///   - appState: For active pet ID and language.
    ///   - skillProgress: Current skill progress from TipsState (optional).
    ///   - petMemory: Cross-session pet memory string (optional).
    func fetchIfNeeded(
        tipsState: TipsState,
        narrativeStore: NarrativeStore,
        appState: AppState,
        petMemory: String? = nil,
        projectStore: ProjectStore? = nil,
        force: Bool = false
    ) async {
        // Already have fresh guidance for today — skip (unless forced).
        if !force {
            guard tipsState.needsGuidanceFetch else {
                logger.info("guidance is fresh, skipping fetch")
                return
            }
        }

        // Already loading — don't double-fetch.
        guard !tipsState.isLoadingGuidance else {
            logger.info("guidance fetch already in progress, skipping")
            return
        }

        // Need at least one narrative to generate guidance from.
        let recentNarratives = buildNarrativeSummaries(from: narrativeStore, projectStore: projectStore)
        guard !recentNarratives.isEmpty else {
            logger.info("no narratives available, skipping guidance fetch")
            return
        }

        tipsState.isLoadingGuidance = true
        tipsState.guidanceError = nil
        lastError = nil

        do {
            let petPersona = buildPetPersona(appState: appState)
            let skillProgressDTOs = buildSkillProgress(tipsState: tipsState, petId: appState.activeChar)
            let language = appState.uiLanguage.rawValue  // "vi" or "en"

            // The previous focus lets the server check whether the user acted
            // on its last suggestion, then continue / complete+advance / start
            // new. Expert knowledge (Astro Tran) is intentionally omitted —
            // the card speaks in the pet's own voice.
            let previousFocus = tipsState.currentGuidance.map { prev in
                GenerateGuidanceRequest.PreviousFocusDTO(
                    project: prev.project,
                    move: prev.move,
                    repeatCount: tipsState.focusRepeatCount
                )
            }

            let request = GenerateGuidanceRequest(
                language: language,
                petPersona: petPersona,
                recentNarratives: recentNarratives,
                skillProgress: skillProgressDTOs.isEmpty ? nil : skillProgressDTOs,
                petMemory: petMemory,
                expertKnowledge: nil,
                previousFocus: previousFocus
            )

            let response = try await api.fetchGuidance(request)

            // Convert API response → TipsState model
            let g = response.guidance
            let guidance = GuidanceResult(
                headline: g.headline,
                project: g.project?.isEmpty == false ? g.project : nil,
                strength: g.strength,
                gap: g.gap?.isEmpty == false ? g.gap : nil,
                move: g.move,
                status: g.status,
                mood: g.mood,
                generatedAt: Date()
            )

            // Track how long the same focus has persisted, so the server can
            // rotate projects if it keeps repeating without progress.
            tipsState.focusRepeatCount = (g.status == "continued")
                ? tipsState.focusRepeatCount + 1
                : 0

            tipsState.currentGuidance = guidance
            tipsState.isLoadingGuidance = false
            logger.info("guidance fetched successfully (\(g.status)): \(guidance.headline)")
        } catch {
            tipsState.isLoadingGuidance = false
            tipsState.guidanceError = error.localizedDescription
            lastError = error.localizedDescription
            logger.error("guidance fetch failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private helpers

    /// Pull up to 10 most recent narratives from the NarrativeStore, each
    /// tagged with the project it came from (resolved via ProjectStore) so the
    /// guidance can attribute its evidence to a specific project.
    private func buildNarrativeSummaries(
        from store: NarrativeStore,
        projectStore: ProjectStore?
    ) -> [GenerateGuidanceRequest.NarrativeSummaryDTO] {
        // Use only the language-qualified keys (they contain ":") so we skip the
        // duplicate plain-turnId entries kept for backward compatibility.
        let keyed = store.narratives.filter { $0.key.contains(":") }
        let sorted = keyed.sorted { $0.value.generatedAt > $1.value.generatedAt }
        return sorted.prefix(10).map { (key, narrative) in
            GenerateGuidanceRequest.NarrativeSummaryDTO(
                title: narrative.title,
                whatHappened: narrative.whatHappened,
                lesson: narrative.lesson.isEmpty ? nil : narrative.lesson,
                mood: narrative.mood,
                project: projectName(forNarrativeKey: key, store: store, projectStore: projectStore)
            )
        }
    }

    /// Resolve the display name of the project a narrative belongs to, via its
    /// sessionId → resolved project path. Returns nil if it can't be resolved.
    private func projectName(
        forNarrativeKey key: String,
        store: NarrativeStore,
        projectStore: ProjectStore?
    ) -> String? {
        guard let projectStore = projectStore,
              let sessionId = store.sessionIds[key],
              let path = projectStore.resolvedProjectPath(for: nil, sessionId: sessionId),
              !path.isEmpty else { return nil }
        return projectStore.project(for: path)?.displayName ?? Project.nameFromPath(path)
    }

    /// Build pet persona DTO from the active character in AppState.
    private func buildPetPersona(appState: AppState) -> SummarizeTurnRequest.PetPersonaDTO? {
        guard let character = PetCharacter.all[appState.activeChar] else { return nil }
        return SummarizeTurnRequest.PetPersonaDTO(
            id: character.id,
            name: character.name,
            personality: character.personality,
            domain: character.domain,
            voiceGuide: character.voiceGuide,
            lensGuide: character.lensGuide,
            emotionalTriggers: character.emotionalTriggers,
            metaphorFamily: character.metaphorFamily,
            signatureEmojis: character.signatureEmojis
        )
    }

    /// Convert current skill progress from TipsState into DTOs.
    private func buildSkillProgress(
        tipsState: TipsState,
        petId: String
    ) -> [GenerateGuidanceRequest.SkillProgressDTO] {
        (0..<tipsState.totalSkillsPerPet).map { index in
            let progress = tipsState.progress(for: petId, index: index)
            return GenerateGuidanceRequest.SkillProgressDTO(
                skillId: progress.skillId,
                practiceCount: progress.practiceCount,
                isMastered: progress.isMastered
            )
        }
    }

    /// Match Astro's knowledge entries against the user's active projects
    /// and return the top 5 most relevant as DTOs for the Cloud Function.
    private func buildExpertKnowledge(
        projectStore: ProjectStore?
    ) -> [GenerateGuidanceRequest.ExpertKnowledgeDTO] {
        guard let store = projectStore else { return [] }

        // Build project context from all active projects
        let reports = ProjectHealthEngine.evaluateAll(projects: store.projects)

        // Aggregate tech stack and health gaps across all projects
        var allTech: Set<String> = []
        var allGaps: Set<String> = []
        for report in reports {
            for tag in report.inferredTags {
                allTech.insert(tag.rawValue)
            }
            for result in report.results where !result.passed {
                allGaps.insert(result.rule.id)
            }
        }

        let context = KnowledgeMatcher.ProjectContext(
            techStack: Array(allTech),
            healthGaps: Array(allGaps),
            recentActivities: [],   // TODO: derive from recent session events
            inactiveAreas: [],      // TODO: derive from session history
            // Stage of the most recently active project (reports are recency-sorted).
            projectStage: reports.first?.stage.rawValue ?? "building"
        )

        let matched = KnowledgeMatcher.match(
            entries: AstroKnowledge.entries,
            context: context,
            limit: 5
        )

        let expert = ExpertContent.experts.first { $0.id == "expert_astro" }

        return matched.map { entry in
            GenerateGuidanceRequest.ExpertKnowledgeDTO(
                expertName: expert?.name ?? "Astro Tran",
                kind: entry.kind.rawValue,
                advice: entry.advice,
                oneLiner: entry.oneLiner
            )
        }
    }
}

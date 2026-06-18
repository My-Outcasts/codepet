import Foundation
import Combine
import os

/// Fetches AI-generated, per-section action plans from the generatePlan Cloud
/// Function and caches them in `TipsState.plansByKey`. Mirrors `GuidanceEnricher`,
/// but plans are on-demand and per (project + check + stage) rather than daily.
///
/// Owned by the Tips tab (an `@StateObject`), like `GuidanceEnricher`.
@MainActor
final class PlanEnricher: ObservableObject {

    private let api: ReflectionAPIClientProtocol
    private let logger = Logger(subsystem: "app.murror.codepet", category: "PlanEnricher")

    /// Plan cache keys with an in-flight request, so the UI can show a spinner
    /// on the right row and we don't double-fetch the same plan.
    @Published private(set) var loadingKeys: Set<String> = []

    /// Last error from a failed fetch, for UI display.
    @Published private(set) var lastError: String?

    init(api: ReflectionAPIClientProtocol) {
        self.api = api
    }

    /// Reading-reference keys currently being distilled into principles, so the
    /// "Add" button can show a spinner while the AI call is in flight.
    @Published private(set) var distillingKeys: Set<String> = []

    /// Stable key for a reference distillation (project path + resource title).
    static func distillKey(projectPath: String, title: String) -> String {
        "\(projectPath)|\(title)"
    }

    /// Whether a plan for this key is currently being generated.
    func isLoading(_ key: String) -> Bool { loadingKeys.contains(key) }

    /// Whether this reference is currently being distilled.
    func isDistilling(_ key: String) -> Bool { distillingKeys.contains(key) }

    /// Distill a recommended resource into a few concrete, project-specific
    /// principles. Returns nil on failure (the caller keeps the plain blurb).
    func distillReference(
        project: Project,
        report: ProjectHealthReport,
        resource: DistillReferenceRequest.ResourceDTO,
        language: AppLanguage
    ) async -> [String]? {
        let key = Self.distillKey(projectPath: project.id, title: resource.title)
        guard !distillingKeys.contains(key) else { return nil }
        distillingKeys.insert(key)
        defer { distillingKeys.remove(key) }

        let domains = ProjectSignals.inferDomains(from: project.id, brief: project.brief)
        let request = DistillReferenceRequest(
            language: language.rawValue,
            project: .init(
                name: project.displayName,
                stage: report.stage.rawValue,
                brief: project.brief,
                tags: report.inferredTags.map { $0.rawValue }.sorted(),
                domains: domains.map { $0.rawValue }.sorted()
            ),
            resource: resource
        )

        do {
            let response = try await api.fetchReferenceDistillation(request)
            let cleaned = response.principles
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return cleaned.isEmpty ? nil : cleaned
        } catch {
            logger.error("distill failed for \(resource.title): \(error.localizedDescription)")
            return nil
        }
    }

    /// Generate (or regenerate) the action plan for one health check.
    ///
    /// - Parameters:
    ///   - project: The project the check belongs to (source of brief + domains).
    ///   - report: The evaluated health report (source of stage + inferred tags).
    ///   - result: The specific check to plan (rule + current state).
    ///   - language: UI language for the generated copy.
    ///   - tipsState: Where the resulting `SectionPlan` is cached.
    ///   - force: Regenerate even if a cached plan already exists.
    func generatePlan(
        project: Project,
        report: ProjectHealthReport,
        result: ProjectHealthResult,
        language: AppLanguage,
        tipsState: TipsState,
        force: Bool = false
    ) async {
        let key = SectionPlan.key(
            projectPath: project.id,
            ruleId: result.rule.id,
            stage: report.stage.rawValue
        )

        // Cached already (and not forced) — nothing to do.
        if !force, tipsState.plansByKey[key] != nil { return }
        // Already generating — don't double-fetch.
        guard !loadingKeys.contains(key) else { return }

        loadingKeys.insert(key)
        lastError = nil
        defer { loadingKeys.remove(key) }

        let domains = ProjectSignals.inferDomains(from: project.id, brief: project.brief)
        let request = GeneratePlanRequest(
            language: language.rawValue,
            project: .init(
                name: project.displayName,
                stage: report.stage.rawValue,
                brief: project.brief,
                tags: report.inferredTags.map { $0.rawValue }.sorted(),
                domains: domains.map { $0.rawValue }.sorted()
            ),
            section: .init(
                ruleId: result.rule.id,
                title: result.rule.title(language),
                pillar: result.rule.pillar.rawValue,
                currentState: Self.stateString(result.state)
            ),
            recentNarratives: nil  // personalization is a later knob (see spec §7)
        )

        do {
            let response = try await api.fetchPlan(request)
            tipsState.plansByKey[key] = Self.makePlan(from: response)
            logger.info("plan generated for \(result.rule.id) (tier: \(response.tier))")
        } catch {
            lastError = error.localizedDescription
            logger.error("plan fetch failed for \(result.rule.id): \(error.localizedDescription)")
        }
    }

    // MARK: - Private helpers

    /// Map the API response into the persisted model. An empty `detail` means
    /// the step was locked by the server (free tier) → represented as `nil`.
    private static func makePlan(from response: GeneratePlanResponse) -> SectionPlan {
        let steps = response.plan.steps.map { s in
            SectionPlan.Step(
                title: s.title,
                detail: s.detail.isEmpty ? nil : s.detail,
                doneWhen: s.doneWhen
            )
        }
        return SectionPlan(
            summary: response.plan.summary,
            steps: steps,
            pitfalls: response.plan.pitfalls ?? [],
            estEffort: response.plan.estEffort,
            tier: response.tier,
            lockedStepCount: response.lockedStepCount,
            generatedAt: Date()
        )
    }

    /// Wire string for the section's current state. `notYetRelevant` shouldn't
    /// reach here (we only plan relevant checks), but map it defensively.
    private static func stateString(_ state: HealthState) -> String {
        switch state {
        case .passed:                    return "passed"
        case .attested:                  return "attested"
        case .missing, .notYetRelevant:  return "missing"
        }
    }
}

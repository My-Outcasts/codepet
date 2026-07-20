// codepet/Views/Onboarding/ProjectInterviewModel.swift
import Foundation
import Combine

/// Drives the per-project founder interview. The 6 fields mirror the web
/// onboarding (components/Onboarding.tsx): name, role, product name, one-liner,
/// audience, stage. On submit it enriches via the server and persists the brief.
@MainActor
final class ProjectInterviewModel: ObservableObject {
    @Published var founderName = ""
    @Published var role = ""
    @Published var projectName = ""
    @Published var oneLiner = ""
    @Published var audience = ""
    @Published var stageIndex = 2
    @Published var isSubmitting = false

    /// Onboarding stage labels (mirror the web OB_STAGES ordering).
    static let stages = ["Idea", "Prototype", "Building", "Private beta", "Launched"]

    /// Prompt the interview only when the project has no founder brief yet.
    static func shouldPrompt(for project: Project) -> Bool { project.companyBrief == nil }

    /// Map the collected fields into a CompanyBrief (empty fields → nil).
    func buildBrief() -> CompanyBrief {
        func nz(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        return CompanyBrief(
            founderName: nz(founderName), role: nz(role),
            stage: Self.stages[min(max(stageIndex, 0), Self.stages.count - 1)],
            projectName: nz(projectName), oneLiner: nz(oneLiner), audience: nz(audience)
        )
    }

    /// Enrich (fail-open) and persist. Returns true when a brief was stored.
    /// A genuinely empty interview (no product signal at all) is a no-op: it
    /// must NOT persist a blank brief, because `setCompanyBrief` marks the
    /// project user-owned and permanently demotes from-history auto-synthesis
    /// (BriefSynthesizer) — losing that safety net for nothing in return.
    func submit(projectId: String, store: ProjectStore, api: ReflectionAPIClientProtocol) async -> Bool {
        isSubmitting = true
        defer { isSubmitting = false }
        let raw = buildBrief()
        let enriched = (try? await api.enrichBrief(raw)) ?? raw   // fail-open
        guard BriefContext.compose(enriched) != nil else { return false }
        store.setCompanyBrief(projectId: projectId, brief: enriched)
        return true
    }
}

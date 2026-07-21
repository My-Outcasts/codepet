import Foundation
import Combine

/// Drives the first-run founder interview (per-account). Re-bases SP1's field
/// mapping onto CompanyStore: collect 6 fields → enrich (fail-open) → the store
/// persists to companies/{uid} and stamps onboardedAt.
@MainActor
final class CompanyOnboardingModel: ObservableObject {
    @Published var founderName = ""
    @Published var role = ""
    @Published var projectName = ""
    @Published var oneLiner = ""
    @Published var audience = ""
    @Published var stageIndex = 2
    @Published var isSubmitting = false

    /// Onboarding stage labels (mirror the web OB_STAGES ordering).
    static let stages = ["Idea", "Prototype", "Building", "Private beta", "Launched"]

    func buildBrief() -> CompanyBrief {
        func nz(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        return CompanyBrief(
            founderName: nz(founderName), role: nz(role),
            stage: Self.stages[min(max(stageIndex, 0), Self.stages.count - 1)],
            projectName: nz(projectName), oneLiner: nz(oneLiner), audience: nz(audience))
    }

    /// Prefill the fields from an existing brief (for edit-from-Settings). Maps the
    /// stage string back to its index; an absent/unknown stage falls to the default.
    func prefill(from brief: CompanyBrief) {
        founderName = brief.founderName ?? ""
        role = brief.role ?? ""
        projectName = brief.projectName ?? ""
        oneLiner = brief.oneLiner ?? ""
        audience = brief.audience ?? ""
        stageIndex = brief.stage.flatMap { Self.stages.firstIndex(of: $0) } ?? 2
    }

    /// Enrich (fail-open) then hand to the store to persist + finish onboarding.
    /// Captures the onboarding token BEFORE the enrich await so a mid-await account
    /// switch can't misroute the write (the store discards a superseded finish).
    func submit(store: CompanyStore, api: ReflectionAPIClientProtocol) async {
        isSubmitting = true
        defer { isSubmitting = false }
        let token = store.onboardingToken
        let raw = buildBrief()
        let enriched = (try? await api.enrichBrief(raw)) ?? raw
        await store.finishOnboarding(brief: enriched, token: token)
    }
}

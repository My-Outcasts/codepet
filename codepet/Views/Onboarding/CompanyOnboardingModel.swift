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
    @Published var stageIndex = CompanyOnboardingModel.defaultStageIndex
    @Published var isSubmitting = false

    /// The first-run onboarding's own stages, not a second list. This wizard had five of its
    /// own ("Idea / Prototype / Building / Private beta / Launched") beside onboarding's six, so
    /// "Start a different business" asked the same question with different answers (build 8
    /// retest, 6 Oct).
    static let stages = OnboardingContent.stages

    /// "Just an idea" — the founder's call for a new company (CP-065).
    static let defaultStageIndex = 0

    /// A stage string back to its index. Briefs saved by the old five-stage list keep a
    /// sensible place: "Idea" was "Just an idea", and "Building" — this wizard's old default,
    /// so mostly never chosen — sits between Prototype and Private beta and reads as Prototype.
    static func stageIndex(for stage: String?) -> Int {
        guard let stage else { return defaultStageIndex }
        if let i = stages.firstIndex(of: stage) { return i }
        switch stage {
        case "Idea":     return stages.firstIndex(of: "Just an idea") ?? defaultStageIndex
        case "Building": return stages.firstIndex(of: "Prototype") ?? defaultStageIndex
        default:         return defaultStageIndex
        }
    }

    /// The step that asks the company's name (`CompanyOnboardingView`).
    static let nameStep = 2

    /// Whether Next may leave `step`. The name may not be skipped: left empty, the new
    /// business's greeting read "your company for your product is ready" and the map said
    /// "Your company" (build 8 retest, 6 Oct).
    func canLeave(step: Int) -> Bool { Self.canLeave(step: step, projectName: projectName) }

    var hasName: Bool { Self.isName(projectName) }

    /// Static so a test needs no instance — this type is a `@MainActor ObservableObject`, and
    /// deallocating one crashes the XCTest host on Xcode 26.2 (landmine 3).
    static func canLeave(step: Int, projectName: String) -> Bool {
        step != nameStep || isName(projectName)
    }

    static func isName(_ s: String) -> Bool {
        !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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
    /// stage string back to its index (`stageIndex(for:)`).
    func prefill(from brief: CompanyBrief) {
        founderName = brief.founderName ?? ""
        role = brief.role ?? ""
        projectName = brief.projectName ?? ""
        oneLiner = brief.oneLiner ?? ""
        audience = brief.audience ?? ""
        stageIndex = Self.stageIndex(for: brief.stage)
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

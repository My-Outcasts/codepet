// codepet/Managers/CompanyStore.swift
import Foundation
import Combine

/// The app's primary store — the single company (companies/{uid}) + the active
/// view. Native port of the web `useApp`/`lib/store`. Replaces ProjectStore's
/// role as the top-level store (ProjectStore/reflection are being retired).
@MainActor
final class CompanyStore: ObservableObject {
    @Published var view: AppView = .overview
    @Published private(set) var company: CompanyState = .empty
    @Published private(set) var isHydrating: Bool = false
    @Published private(set) var isOnboarding: Bool = false

    /// The hydrated company's id, needed for writes. Set by `hydrate`, cleared by `reset`.
    private(set) var companyId: String?

    /// Injectable so tests can supply a stub without Firestore.
    private let loader: (String) async -> CompanyState
    private let saver: (String, CompanyBrief) async -> Bool

    /// Bumped on every hydrate/reset; lets a suspended hydrate detect it has
    /// been superseded (account switch mid-flight) and discard its result
    /// instead of clobbering newer state.
    private var hydrationToken = 0

    init(loader: @escaping (String) async -> CompanyState = CompanyData.load,
         saver: @escaping (String, CompanyBrief) async -> Bool = CompanyData.saveBrief) {
        self.loader = loader
        self.saver = saver
    }

    func select(_ view: AppView) { self.view = view }

    /// Mirrors the web: onboard unless a stamp exists OR the brief already has signal.
    var needsOnboarding: Bool {
        company.onboardedAt == nil && BriefContext.compose(company.brief) == nil
    }

    /// Hydrate the company from Firestore (fail-soft inside the loader).
    func hydrate(companyId: String) async {
        hydrationToken &+= 1
        let token = hydrationToken
        self.companyId = companyId
        isHydrating = true
        let loaded = await loader(companyId)
        guard token == hydrationToken else { return }  // a newer hydrate/reset superseded us
        company = loaded
        isHydrating = false
        isOnboarding = needsOnboarding
    }

    /// Enrich already happened in the model; here we persist + stamp + leave onboarding.
    /// Fail-soft: a failed cloud write still lets the founder into the app.
    func finishOnboarding(brief: CompanyBrief) async {
        if let cid = companyId { _ = await saver(cid, brief) }
        company.brief = brief
        company.onboardedAt = Date()
        isOnboarding = false
    }

    /// Skip: stamp with the current (empty) brief so they aren't re-blocked.
    func skipOnboarding() async {
        if let cid = companyId { _ = await saver(cid, company.brief) }
        company.onboardedAt = Date()
        isOnboarding = false
    }

    /// Clear on sign-out / account switch.
    func reset() {
        hydrationToken &+= 1
        companyId = nil
        company = .empty
        view = .overview
        isHydrating = false
        isOnboarding = false
    }
}

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

    /// Injectable so tests can supply a stub without Firestore.
    private let loader: (String) async -> CompanyState

    /// Bumped on every hydrate/reset; lets a suspended hydrate detect it has
    /// been superseded (account switch mid-flight) and discard its result
    /// instead of clobbering newer state.
    private var hydrationToken = 0

    init(loader: @escaping (String) async -> CompanyState = CompanyData.load) {
        self.loader = loader
    }

    func select(_ view: AppView) { self.view = view }

    /// Hydrate the company from Firestore (fail-soft inside the loader).
    func hydrate(companyId: String) async {
        hydrationToken &+= 1
        let token = hydrationToken
        isHydrating = true
        let loaded = await loader(companyId)
        guard token == hydrationToken else { return }  // a newer hydrate/reset superseded us
        company = loaded
        isHydrating = false
    }

    /// Clear on sign-out / account switch.
    func reset() {
        hydrationToken &+= 1
        company = .empty
        view = .overview
        isHydrating = false
    }
}

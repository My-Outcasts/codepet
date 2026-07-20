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

    init(loader: @escaping (String) async -> CompanyState = CompanyData.load) {
        self.loader = loader
    }

    func select(_ view: AppView) { self.view = view }

    /// Hydrate the company from Firestore (fail-soft inside the loader).
    func hydrate(companyId: String) async {
        isHydrating = true
        company = await loader(companyId)
        isHydrating = false
    }

    /// Clear on sign-out / account switch.
    func reset() {
        company = .empty
        view = .overview
    }
}

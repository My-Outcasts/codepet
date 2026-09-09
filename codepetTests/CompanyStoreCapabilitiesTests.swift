// codepetTests/CompanyStoreCapabilitiesTests.swift
import XCTest
@testable import codepet

/// `CompanyStore` is exercised through its injected closures — see
/// CompanyStoreChatTests for the same pattern. Never construct the real client.
@MainActor
final class CompanyStoreCapabilitiesTests: XCTestCase {

    private func store(
        capabilities: @escaping () async -> Set<String>? = { nil }
    ) -> CompanyStore {
        CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                     capabilitiesFetcher: capabilities)
    }

    func testStartsAtTheBundledFloorBeforeAnyFetch() {
        // First paint must never render a built skill as unbuilt, so the floor is
        // the starting value rather than an empty set.
        XCTAssertEqual(store().builtSkills, Toolkit.bundledBuiltSkills)
    }

    func testAdoptsTheManifestWhenTheFetchSucceeds() async {
        let s = store(capabilities: { ["web-research", "prd-writer", "changelog"] })
        await s.refreshCapabilities()
        XCTAssertEqual(s.builtSkills, ["web-research", "prd-writer", "changelog"])
    }

    func testFallsBackToTheFloorRatherThanEmptyWhenTheFetchFails() async {
        let s = store(capabilities: { nil })
        await s.refreshCapabilities()
        // An empty set would render EVERY skill as unbuilt — a worse lie than the
        // one this pass fixes. nil and "no skills" must stay different things.
        XCTAssertEqual(s.builtSkills, Toolkit.bundledBuiltSkills)
        XCTAssertFalse(s.builtSkills.isEmpty)
    }

    func testAnEmptyManifestIsHonouredAndIsNotTreatedAsAFailure() async {
        // A backend that genuinely implements nothing is a real answer, distinct
        // from an unreachable one.
        let s = store(capabilities: { [] })
        await s.refreshCapabilities()
        XCTAssertTrue(s.builtSkills.isEmpty)
    }

    /// Records every `toolsSaver` call so a test can prove no WRITE happened,
    /// not merely that no visible change happened.
    private final class SaveSpy {
        var calls: [[String]] = []
    }

    // NOTE ON A BRIEF DEVIATION: the brief's version of this helper stopped at
    // construction and never called `hydrate`. Without it `companyId` stays nil
    // forever, so `toggleTool`'s `if let cid = companyId { toolsSaver(...) }`
    // guard can NEVER fire — `testTogglingABuiltItemStillWorks` failed even
    // pre-guard (spy.calls.count was 0, not 1), and worse,
    // `testAStoredUnbuiltIdSurvivesUntouched` PASSED pre-guard for the wrong
    // reason: `company` stayed `.empty` instead of loading the seeded
    // `enabled` set, so `toggleTool` freshly INSERTED "explorer" rather than
    // preserving a stored one. That is exactly the "passes with and without
    // the guard" trap this plan warns against, so `hydrate` was added here to
    // make the seeded state and the saver both real.
    private func storeWithSpy(
        enabled: Set<String>,
        capabilities: @escaping () async -> Set<String>? = { Toolkit.bundledBuiltSkills }
    ) async -> (CompanyStore, SaveSpy) {
        let spy = SaveSpy()
        var state = CompanyState.empty
        state.enabledTools = enabled
        let s = CompanyStore(loader: { _ in state }, saver: { _, _ in true },
                             toolsSaver: { _, ids in spy.calls.append(ids); return true },
                             capabilitiesFetcher: capabilities)
        await s.hydrate(companyId: "test-co")
        return (s, spy)
    }

    func testTogglingAnUnbuiltItemNeitherChangesStateNorWrites() async {
        let (s, spy) = await storeWithSpy(enabled: [])
        await s.refreshCapabilities()
        await s.toggleTool(id: "code-reviewer")     // an agent: nothing can run one
        XCTAssertFalse(s.company.enabledTools.contains("code-reviewer"))
        XCTAssertTrue(spy.calls.isEmpty, "an unbuilt id must not reach the saver")
    }

    func testTogglingAnUnbuiltConnectorDoesNotWrite() async {
        let (s, spy) = await storeWithSpy(enabled: [])
        await s.refreshCapabilities()
        await s.toggleTool(id: "notion")            // recommended, but no OAuth exists
        XCTAssertFalse(s.company.enabledTools.contains("notion"))
        XCTAssertTrue(spy.calls.isEmpty)
    }

    func testTogglingABuiltItemStillWorks() async {
        let (s, spy) = await storeWithSpy(enabled: [])
        await s.refreshCapabilities()
        await s.toggleTool(id: "web-research")
        XCTAssertTrue(s.company.enabledTools.contains("web-research"))
        XCTAssertEqual(spy.calls.count, 1, "the guard must not break the real path")
    }

    func testAnIdOutsideTheCatalogIsRejected() async {
        let (s, spy) = await storeWithSpy(enabled: [])
        await s.refreshCapabilities()
        await s.toggleTool(id: "not-a-real-tool")
        XCTAssertFalse(s.company.enabledTools.contains("not-a-real-tool"))
        XCTAssertTrue(spy.calls.isEmpty)
    }

    func testAStoredUnbuiltIdSurvivesUntouched() async {
        // The migration decision: leave the data, fix the read. The founder's
        // original intent is preserved, so a later-shipped item arrives already on.
        let (s, spy) = await storeWithSpy(enabled: ["prd-writer", "github", "explorer"])
        await s.refreshCapabilities()
        await s.toggleTool(id: "explorer")
        XCTAssertTrue(s.company.enabledTools.contains("explorer"),
                      "nothing in this pass may write to founder prefs")
        XCTAssertTrue(spy.calls.isEmpty)
    }
}

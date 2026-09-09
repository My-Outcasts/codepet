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
}

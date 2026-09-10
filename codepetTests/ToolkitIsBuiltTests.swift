// codepetTests/ToolkitIsBuiltTests.swift
import XCTest
@testable import codepet

final class ToolkitIsBuiltTests: XCTestCase {

    /// `throws` + `XCTUnwrap` rather than a `fatalError` helper. A `fatalError`
    /// here would kill the test HOST on a mistyped id, and a dead host in this
    /// repo reads as landmine 3 (the `@MainActor ObservableObject` crash) — so a
    /// typo would present as a toolchain bug and cost real time. Every test using
    /// it is therefore `func test…() throws`.
    private func item(_ id: String) throws -> ToolItem {
        try XCTUnwrap(Toolkit.catalog.first(where: { $0.id == id }),
                      "no catalog item '\(id)'")
    }

    func testSkillIsBuiltOnlyWhenTheManifestNamesIt() throws {
        XCTAssertTrue(try item("web-research").isBuilt(builtSkills: ["web-research"]))
        XCTAssertFalse(try item("web-research").isBuilt(builtSkills: []))
        // In the catalog, and NOT in the CF's IMPLEMENTED_SKILLS today.
        XCTAssertFalse(try item("code-review").isBuilt(builtSkills: Toolkit.bundledBuiltSkills))
        XCTAssertFalse(try item("changelog").isBuilt(builtSkills: Toolkit.bundledBuiltSkills))
    }

    func testAManifestArrivingLaterBuildsASkillWithNoClientChange() throws {
        // The property Toolkit.swift defends: shipping a skill is a backend deploy,
        // not a client release. A manifest naming 'changelog' must build it here.
        XCTAssertTrue(try item("changelog").isBuilt(builtSkills: ["changelog"]))
    }

    func testConnectorIsBuiltOnlyWhenAProviderCaseExists() throws {
        XCTAssertTrue(try item("github").isBuilt(builtSkills: []))
        // Note the manifest passed in NAMES these connectors. A skills manifest
        // must never be able to build a connector — the categories are separate
        // authorities, and this is the assertion that proves it.
        let lying: Set<String> = ["notion", "figma", "slack", "linear"]
        for id in ["notion", "figma", "slack", "linear"] {
            XCTAssertFalse(try item(id).isBuilt(builtSkills: lying),
                           "\(id) has no ConnectorProvider case")
        }
    }

    func testNoAgentIsEverBuilt() {
        let everything = Set(Toolkit.catalog.map(\.id))
        for agent in Toolkit.items(in: .agents) {
            XCTAssertFalse(agent.isBuilt(builtSkills: everything),
                           "\(agent.id): no mechanism can run an agent yet")
        }
        XCTAssertEqual(Toolkit.items(in: .agents).count, 4)
    }

    func testBundledFallbackNamesTheTwoSkillsTheCFImplements() {
        XCTAssertEqual(Toolkit.bundledBuiltSkills, ["web-research", "prd-writer"])
    }

    func testNothingUnbuiltShipsDefaultOn() {
        // The drift guard. It asserts on the RAW `defaultOn` data rather than on
        // `defaultEnabledIds`, and that distinction is the whole point: if
        // `defaultEnabledIds` filtered by isBuilt, this test would pass forever
        // even after somebody re-added a default-on item that does nothing.
        let defaults = Toolkit.catalog.filter(\.defaultOn)
        for item in defaults {
            XCTAssertTrue(item.isBuilt(builtSkills: Toolkit.bundledBuiltSkills),
                          "'\(item.id)' ships defaultOn but does nothing")
        }
        XCTAssertFalse(defaults.isEmpty, "a catalog with no defaults would pass vacuously")
    }

    func testRecommendationsOnlyOfferWhatCanBeActedOn() {
        let recs = Toolkit.recommended(builtSkills: Toolkit.bundledBuiltSkills)
        XCTAssertEqual(recs.map(\.id).sorted(), ["github", "prd-writer"])
        // Browse all still carries them; only the pitch drops them.
        for id in ["code-review", "notion", "test-writer"] {
            XCTAssertTrue(Toolkit.catalog.contains { $0.id == id },
                          "\(id) must remain in the catalog")
        }
    }

    func testALaterManifestWidensRecommendationsWithNoClientChange() {
        let recs = Toolkit.recommended(builtSkills: ["prd-writer", "code-review"])
        XCTAssertTrue(recs.map(\.id).contains("code-review"))
    }
}

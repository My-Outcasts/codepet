// codepetTests/CompanyStoreToolsTests.swift
import XCTest
@testable import codepet

@MainActor
final class CompanyStoreToolsTests: XCTestCase {
    func testStateMapsEnabledTools() {
        let dflt = CompanyData.state(from: CompanyDoc(brief: nil, stage: nil, companionId: nil,
                                                      onboardedAt: nil, tasks: nil, library: nil, enabledTools: nil))
        XCTAssertEqual(dflt.enabledTools, Toolkit.defaultEnabledIds)   // nil → defaults
        let off = CompanyData.state(from: CompanyDoc(brief: nil, stage: nil, companionId: nil,
                                                     onboardedAt: nil, tasks: nil, library: nil, enabledTools: []))
        XCTAssertTrue(off.enabledTools.isEmpty)                        // [] → all-off
        let set = CompanyData.state(from: CompanyDoc(brief: nil, stage: nil, companionId: nil,
                                                     onboardedAt: nil, tasks: nil, library: nil, enabledTools: ["github"]))
        XCTAssertEqual(set.enabledTools, ["github"])                   // [ids] → set
    }
    func testEnabledToolsPayloadShape() {
        let p = CompanyData.enabledToolsPayload(["github", "notion"])
        XCTAssertEqual(p["enabledTools"] as? [String], ["github", "notion"])
    }
    func testToggleFlipsAndPersists() async {
        var saved: [String] = []
        let s = CompanyStore(loader: { _ in .empty }, saver: { _, _ in true },
                             toolsSaver: { _, t in saved = t; return true })
        await s.hydrate(companyId: "u")
        XCTAssertTrue(s.company.enabledTools.contains("github"))       // default on
        await s.toggleTool(id: "github")
        XCTAssertFalse(s.company.enabledTools.contains("github"))      // off
        XCTAssertFalse(saved.contains("github"))                      // persisted without it
        await s.toggleTool(id: "web-research")
        XCTAssertTrue(s.company.enabledTools.contains("web-research")) // on
        XCTAssertTrue(saved.contains("web-research"))
    }
}

import XCTest
@testable import codepet

final class ProjectLinkTests: XCTestCase {

    /// Make a throwaway project dir; optionally seed a .git dir and/or CLAUDE.md.
    private func tempProject(git: Bool, claudeMd: Bool) -> String {
        let base = NSTemporaryDirectory() + "codepet-2a-" + UUID().uuidString
        let fm = FileManager.default
        try? fm.createDirectory(atPath: base, withIntermediateDirectories: true)
        if git { try? fm.createDirectory(atPath: base + "/.git", withIntermediateDirectories: true) }
        if claudeMd { try? "# hi".write(toFile: base + "/CLAUDE.md", atomically: true, encoding: .utf8) }
        return base
    }

    func test_probe_detectsGitAndClaudeMd() {
        let p = tempProject(git: true, claudeMd: true)
        let link = ProjectProbe.probe(path: p)
        XCTAssertEqual(link.path, p)
        XCTAssertTrue(link.isGitRepo)
        XCTAssertTrue(link.hasClaudeMd)
    }

    func test_probe_detectsNeither() {
        let p = tempProject(git: false, claudeMd: false)
        let link = ProjectProbe.probe(path: p)
        XCTAssertFalse(link.isGitRepo)
        XCTAssertFalse(link.hasClaudeMd)
    }

    func test_slice_mapsFieldsAndHasNilRecentChange() {
        let p = tempProject(git: true, claudeMd: false)
        let slice = ProjectProbe.probe(path: p).slice
        XCTAssertEqual(slice.path, p)
        XCTAssertTrue(slice.isGitRepo)
        XCTAssertFalse(slice.hasClaudeMd)
        XCTAssertNil(slice.recentChangeSummary)   // filled in 2B, nil here
    }

    func test_bootstrap_includesProjectFounderAndDecisions() {
        var b = CompanyBrief()
        b.projectName = "Acme"; b.founderName = "Mona"; b.role = "Solo founder"
        b.tech = "Next.js"; b.stage = "building"; b.oneLiner = "AI coding companion"
        let decisions = [
            DecisionEntry(topic: "pricing", statement: "Charge $20/mo", source: "founder", updatedAt: 1),
        ]
        let md = ClaudeMdBootstrap.compose(brief: b, decisions: decisions)

        XCTAssertTrue(md.contains("Acme"))
        XCTAssertTrue(md.contains("Mona"))
        XCTAssertTrue(md.contains("Next.js"))
        XCTAssertTrue(md.contains("AI coding companion"))
        XCTAssertTrue(md.contains("Charge $20/mo"))
        XCTAssertTrue(md.contains("Codepet"))   // the managed-block marker
    }

    func test_bootstrap_handlesEmptyBriefAndDecisions() {
        let md = ClaudeMdBootstrap.compose(brief: CompanyBrief(), decisions: [])
        XCTAssertFalse(md.isEmpty)               // still a usable seed
        XCTAssertTrue(md.contains("Codepet"))
    }

    @MainActor
    func test_linkProject_setsActiveLinkAndBootstrapsClaudeMd() async {
        // Injected-fake store (no live Firestore), mirroring CompanyStoreFanOutTests.
        var brief = CompanyBrief(); brief.projectName = "Acme"; brief.founderName = "Mona"
        let seed = CompanyState(brief: brief, departments: [], library: [], stage: .building,
                                companionId: "byte", onboardedAt: Date(), tasks: [])
        let store = CompanyStore(loader: { _ in seed },
                                 tasksSaver: { _, _ in true },
                                 librarySaver: { _, _ in true },
                                 threadSaver: { _, _ in true },
                                 threadsLoader: { _ in [] })
        await store.hydrate(companyId: "u")

        // A git project with NO CLAUDE.md → bootstrap should create one.
        let base = NSTemporaryDirectory() + "codepet-2a-store-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: base + "/.git", withIntermediateDirectories: true)

        let link = store.linkProject(path: base, bootstrapClaudeMd: true)
        XCTAssertEqual(store.activeProjectLink, link)
        XCTAssertEqual(link.path, base)
        XCTAssertTrue(link.isGitRepo)
        XCTAssertTrue(link.hasClaudeMd, "bootstrap should have written CLAUDE.md and re-probed")
        let written = try? String(contentsOfFile: base + "/CLAUDE.md", encoding: .utf8)
        XCTAssertEqual(written?.contains("Acme"), true)
    }
}

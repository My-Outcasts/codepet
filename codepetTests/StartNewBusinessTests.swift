// codepetTests/StartNewBusinessTests.swift
import XCTest
@testable import codepet

/// Starting over with a different business. Found testing as a non-technical founder (5 Oct):
/// asked for a candle shop, the companion said it would "rather rebuild the brief" — and the app
/// had no way to. Editing the brief kept Codepet's roadmap, library, decisions and folder, all
/// still read into every prompt.
@MainActor
final class StartNewBusinessTests: XCTestCase {
    private let oldDoc = Deliverable(kind: .doc, title: "Codepet positioning", body: "b", sourceTaskId: "old-0")
    private func seed() -> CompanyState {
        var b = CompanyBrief(); b.projectName = "Codepet"
        return CompanyState(brief: b, departments: [], library: [oldDoc], stage: .building,
                            companionId: "byte", onboardedAt: Date(), greetedAt: Date(),
                            tasks: [RoadmapTask(id: "old-0", title: "Old", detail: "", phase: .find, who: .does, done: true)],
                            decisions: [DecisionEntry(topic: "pricing", statement: "Codepet is $20")])
    }
    private var candles: CompanyBrief { var b = CompanyBrief(); b.projectName = "Wick & Co"; b.oneLiner = "Handmade candles"; return b }
    private let newTasks = [RoadmapTask(id: "new-0", title: "Photograph the candles", detail: "", phase: .find, who: .you)]

    private func store(fetched: [RoadmapTask], saveOK: Bool = true,
                       saved: @escaping (NewBusinessWrite) -> Void = { _ in },
                       fetchedWith: @escaping ([String]) -> Void = { _ in }) -> CompanyStore {
        CompanyStore(loader: { [seed] _ in seed() },
                     roadmapFetcher: { _, _, done in fetchedWith(done); return fetched },
                     enricher: { $0 },
                     newBusinessSaver: { _, w in saved(w); return saveOK })
    }

    func testStartingOverReplacesTheCompany() async {
        var write: NewBusinessWrite?
        let s = store(fetched: newTasks, saved: { write = $0 })
        await s.hydrate(companyId: "u")
        let ok = await s.startNewBusiness(brief: candles, language: .en)
        XCTAssertTrue(ok)
        XCTAssertEqual(s.company.brief.projectName, "Wick & Co")
        XCTAssertEqual(s.company.tasks.map(\.id), ["new-0"])          // old done task gone too
        XCTAssertTrue(s.company.library.isEmpty)                       // nothing old reaches prompts
        XCTAssertEqual(s.company.previousLibrary.map(\.title), ["Codepet positioning"])  // kept
        XCTAssertTrue(s.company.decisions.isEmpty)
        // One write carries all of it.
        XCTAssertEqual(write?.brief.projectName, "Wick & Co")
        XCTAssertEqual(write?.tasks.map(\.id), ["new-0"])
        XCTAssertEqual(write?.previousLibrary.count, 1)
    }

    /// The old business's finished work must not be passed to the planner as "already done".
    func testThePlannerIsNotToldAboutTheOldBusiness() async {
        var done: [String]?
        let s = store(fetched: newTasks, fetchedWith: { done = $0 })
        await s.hydrate(companyId: "u")
        _ = await s.startNewBusiness(brief: candles, language: .en)
        XCTAssertEqual(done, [])
    }

    /// Nothing changes unless the new roadmap exists — a failed plan must not leave a candle
    /// brief over an empty board, or wipe the old company for nothing.
    func testAFailedPlanChangesNothing() async {
        var wrote = false
        let s = store(fetched: [], saved: { _ in wrote = true })
        await s.hydrate(companyId: "u")
        let ok = await s.startNewBusiness(brief: candles, language: .en)
        XCTAssertFalse(ok)
        XCTAssertFalse(wrote)
        XCTAssertEqual(s.company.brief.projectName, "Codepet")
        XCTAssertEqual(s.company.library.count, 1)
    }

    func testAFailedSaveChangesNothing() async {
        let s = store(fetched: newTasks, saveOK: false)
        await s.hydrate(companyId: "u")
        let ok = await s.startNewBusiness(brief: candles, language: .en)
        XCTAssertFalse(ok)
        XCTAssertEqual(s.company.brief.projectName, "Codepet")
        XCTAssertEqual(s.company.tasks.map(\.id), ["old-0"])
    }

    /// The new company is greeted like a new founder, in a fresh conversation.
    func testTheNewCompanyIsGreetedInAFreshChat() async {
        let s = store(fetched: newTasks)
        await s.hydrate(companyId: "u")
        _ = await s.startNewBusiness(brief: candles, language: .en)
        XCTAssertEqual(s.chatMessages.count, 1)
        XCTAssertTrue(s.chatMessages[0].text.contains("Wick & Co"), s.chatMessages[0].text)
    }

    /// A second start-over keeps the first business's work too.
    func testPreviousWorkAccumulates() async {
        let s = store(fetched: newTasks)
        await s.hydrate(companyId: "u")
        _ = await s.startNewBusiness(brief: candles, language: .en)
        _ = await s.startNewBusiness(brief: candles, language: .en)
        XCTAssertEqual(s.company.previousLibrary.count, 1)
    }

    // MARK: persistence

    func testThePayloadClearsWhatBelongsToTheOldBusiness() {
        let p = CompanyData.newBusinessPayload(NewBusinessWrite(brief: candles, tasks: newTasks,
                                                                previousLibrary: [oldDoc]))
        XCTAssertEqual((p["library"] as? [Any])?.count, 0)
        XCTAssertEqual((p["decisions"] as? [Any])?.count, 0)
        XCTAssertEqual((p["tasks"] as? [Any])?.count, 1)
        XCTAssertEqual((p["previousLibrary"] as? [Any])?.count, 1)
        XCTAssertNotNil(p["brief"])
    }

    func testPreviousLibraryRoundTripsThroughTheDoc() {
        var doc = CompanyDoc(); doc.previousLibrary = [oldDoc]
        XCTAssertEqual(CompanyData.state(from: doc).previousLibrary.map(\.title), ["Codepet positioning"])
        XCTAssertTrue(CompanyData.state(from: CompanyDoc()).previousLibrary.isEmpty)
    }

    /// A team build of the old company that is working or waiting on Approve must settle first:
    /// approving it after a start-over would file the old project into the new Library.
    func testAnUnsettledTeamBuildBlocksStartingOver() {
        let plan = WorkPlan(title: "P", slug: "p", summary: "", projectType: "site",
                            steps: [WorkStep(id: "build", dept: "eng", title: "Build", instruction: "",
                                             kind: "other", dependsOn: [])])
        var r = TeamRun(id: "r", request: "page", createdAt: Date(), brief: nil, plan: plan)
        for (phase, blocks) in [(TeamRunPhase.planned, true), (.running, true), (.assembling, true),
                                (.failed, true), (.ready, true), (.filed, false), (.cancelled, false)] {
            r.phase = phase
            XCTAssertEqual(r.blocksStartOver, blocks, "\(phase)")
        }
    }
}

// codepetTests/DepartmentSpecialistReachesModelTests.swift
import XCTest
@testable import codepet

/// The specialist used to be a costume: `actingSpecialist` decided which pet's name, colour and
/// sprite dressed the reply, while the REQUEST went out under the founder's host companion and
/// carried no department at all. "Nova · Marketing" was Byte writing in Nova's name, with no
/// marketing expertise anywhere in the prompt.
///
/// These pin the two halves that make the label true: who the model is told it is, and what the
/// model is told it knows.
@MainActor
final class DepartmentSpecialistReachesModelTests: XCTestCase {
    private static let failingStreamer: (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> = { _ in
        AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.notSignedIn) }
    }

    private func store(host: String,
                       tasks: [RoadmapTask] = [],
                       capture: @escaping (CompanyChatRequest) -> Void = { _ in },
                       captureRun: @escaping (RunTaskRequest) -> Void = { _ in }) -> CompanyStore {
        CompanyStore(loader: { _ in
                        CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                                     companionId: host, onboardedAt: Date(), tasks: tasks)
                     },
                     saver: { _, _ in true },
                     tasksSaver: { _, _ in true },
                     chatSender: { req in
                         capture(req)
                         return CompanyChatReply(text: "ok", runTaskId: nil)
                     },
                     chatStreamer: Self.failingStreamer,
                     taskRunner: { req in
                         captureRun(req)
                         return RunTaskResponse(kind: "post", title: "Launch tweet", body: "hello")
                     },
                     decisionExtractor: { _, _ in [] })
    }

    private var marketing: Department { DepartmentCatalog.find("mkt")! }

    // MARK: - Chat

    /// The chip case: Nova leads, so Nova is who the model is told it is.
    func testTheSpecialistIdentityGoesOutOnTheWire() async {
        var sent: CompanyChatRequest?
        let s = store(host: "byte", capture: { sent = $0 })
        await s.hydrate(companyId: "u")
        await s.sendChat("draft a launch tweet", language: .en, department: marketing)
        XCTAssertEqual(sent?.companionId, "nova", "the pet that signs the reply must be the one writing it")
        XCTAssertEqual(sent?.deptKey, "mkt")
    }

    /// The case that forced `deptKey` to be its own field rather than being read off the
    /// handoff. Nova IS this founder's companion, and the reply signs as Nova anyway — there
    /// is no host-shadow rule any more to suppress it. "Nova · Marketing" says something a
    /// bare "Nova" does not, and the department is the new information in that header: the
    /// old shape hid it from exactly the founder who had chosen Nova. `deptKey` and
    /// `companionId` are still read off two separate fields regardless of who the founder's
    /// own companion is — that half of the original point survives unchanged.
    func testTheDepartmentIsSentEvenWhenItsPetIsAlreadyTheHost() async {
        var sent: CompanyChatRequest?
        let s = store(host: "nova", capture: { sent = $0 })
        await s.hydrate(companyId: "u")
        await s.sendChat("draft a launch tweet", language: .en, department: marketing)
        XCTAssertEqual(sent?.deptKey, "mkt", "a marketing question is a marketing question")
        XCTAssertEqual(sent?.companionId, "nova")
        XCTAssertEqual(s.chatMessages.last?.companionId, "nova",
                       "the reply signs as Nova even though Nova is also this founder's own companion")
    }

    /// An ordinary turn is unchanged: the host speaks and no department rides along, so the
    /// wire (and the prompt, and the bill) look exactly as they did.
    func testAnOrdinaryTurnSendsNoDepartmentAndKeepsTheHost() async {
        var sent: CompanyChatRequest?
        let s = store(host: "byte", capture: { sent = $0 })
        await s.hydrate(companyId: "u")
        await s.sendChat("what should I charge?", language: .en)
        XCTAssertNil(sent?.deptKey)
        XCTAssertEqual(sent?.companionId, "byte")
    }

    /// A department addressed in free text grounds the turn exactly like the chip does — the
    /// text path used to change the label and nothing else.
    func testAnAddressedDepartmentGroundsTheTurnToo() async {
        var sent: CompanyChatRequest?
        let s = store(host: "byte", capture: { sent = $0 })
        await s.hydrate(companyId: "u")
        await s.sendChat("ask marketing what to do about the launch", language: .en)
        XCTAssertEqual(sent?.deptKey, "mkt")
        XCTAssertEqual(sent?.companionId, "nova")
    }

    // MARK: - Runs

    /// A run is performed BY a department, so the deliverable is generated by that
    /// department's pet with that department's key — matching the pet already credited on the
    /// execute log and the draft card.
    func testARunIsGeneratedByTheDepartmentsOwnSpecialist() async {
        let task = RoadmapTask(id: "t1", title: "Draft the launch email", detail: "",
                               phase: .launch, who: .does, dept: "mkt")
        var sent: RunTaskRequest?
        let s = store(host: "byte", tasks: [task], captureRun: { sent = $0 })
        await s.hydrate(companyId: "u")
        await s.runTask(task, language: .en)
        XCTAssertEqual(sent?.companionId, "nova")
        XCTAssertEqual(sent?.deptKey, "mkt")
    }

    /// Legacy boards predate `dept`. No department, no invented one — the host runs it.
    func testADeptLessTaskRunsAsTheHost() async {
        let task = RoadmapTask(id: "t2", title: "Name the company", detail: "",
                               phase: .find, who: .does)
        var sent: RunTaskRequest?
        let s = store(host: "byte", tasks: [task], captureRun: { sent = $0 })
        await s.hydrate(companyId: "u")
        await s.runTask(task, language: .en)
        XCTAssertNil(sent?.deptKey)
        XCTAssertEqual(sent?.companionId, "byte")
    }
}

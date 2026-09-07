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

    // MARK: - Task-grounded chat

    /// The gap this suite closes: `speakerFor` already named the task's own department on the
    /// header, but `dept_key` on the wire was still resolved from the chip-or-keyword rule alone
    /// — which names no department for "Walk me through: <title>" — so the reply could be headed
    /// "Nova · Marketing" while the model was told nothing about marketing.
    func testATaskGroundsTheWireEvenWhenTheTextNamesNoDepartment() async {
        let task = RoadmapTask(id: "mur-interviews", title: "Talk to 12 people about being lonely",
                               detail: "", phase: .find, who: .you, dept: "mkt")
        var sent: CompanyChatRequest?
        let s = store(host: "byte", capture: { sent = $0 })
        await s.hydrate(companyId: "u")
        await s.sendChat("Walk me through: \(task.title)", language: .en, aboutTask: task)
        XCTAssertEqual(sent?.deptKey, "mkt", "the task's own department, not a keyword match over prose with none")
        XCTAssertEqual(sent?.companionId, "nova")
    }

    /// With no task, the wire's `deptKey` still resolves exactly as before — unchanged behaviour
    /// for the overwhelmingly common turn that is about nothing in particular.
    func testWithNoTaskTheWireStillResolvesByChipOrKeyword() async {
        var sent: CompanyChatRequest?
        let s = store(host: "byte", capture: { sent = $0 })
        await s.hydrate(companyId: "u")
        await s.sendChat("ask marketing what to do about the launch", language: .en)
        XCTAssertEqual(sent?.deptKey, "mkt")
    }

    /// The two resolutions stay independent: a task in one department plus text naming a
    /// DIFFERENT department must yield the task's department for both the speaker and the wire's
    /// `deptKey` — neither resolver may answer with the other's department.
    func testATaskWinsOverATextNamedDepartmentForBothSpeakerAndWire() async {
        let task = RoadmapTask(id: "t3", title: "Ship the onboarding flow", detail: "",
                               phase: .find, who: .you, dept: "eng")
        var sent: CompanyChatRequest?
        let s = store(host: "byte", capture: { sent = $0 })
        await s.hydrate(companyId: "u")
        await s.sendChat("Walk me through: \(task.title) — ask marketing first", language: .en, aboutTask: task)
        XCTAssertEqual(sent?.deptKey, "eng", "the task's department, not the department named in the text")
        XCTAssertEqual(sent?.companionId, "byte", "Engineering's own pet, not Marketing's")
        XCTAssertEqual(s.chatMessages.last?.deptName, "Engineering")
    }

    /// A task with no `dept` at all falls back to the chip-or-keyword rule rather than sending a
    /// nil-shaped or invented key.
    func testATaskWithNoDeptFallsBackOnTheWire() async {
        let task = RoadmapTask(id: "t4", title: "Untitled task", detail: "",
                               phase: .find, who: .you, dept: nil)
        var sent: CompanyChatRequest?
        let s = store(host: "byte", capture: { sent = $0 })
        await s.hydrate(companyId: "u")
        await s.sendChat("ask marketing what to do", language: .en, aboutTask: task)
        XCTAssertEqual(sent?.deptKey, "mkt", "no recorded department on the task, so the keyword rule decides")
    }

    /// A task whose `dept` does not resolve in `DepartmentCatalog` (a stale or bogus key) must not
    /// go out on the wire as-is — it falls back exactly like a nil `dept` would.
    func testATaskWithAnUnmappedDeptFallsBackRatherThanSendingABogusKey() async {
        let task = RoadmapTask(id: "t5", title: "Some task", detail: "",
                               phase: .find, who: .you, dept: "not-a-real-department")
        var sent: CompanyChatRequest?
        let s = store(host: "byte", capture: { sent = $0 })
        await s.hydrate(companyId: "u")
        await s.sendChat("ask marketing what to do", language: .en, aboutTask: task)
        XCTAssertEqual(sent?.deptKey, "mkt", "an unmapped dept key is not trusted — falls back to the keyword rule")
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

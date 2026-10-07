// codepetTests/TeamBuildStoreTests.swift
import XCTest
@testable import codepet

/// Shared by `TeamBuildStoreTests` and `ApprovalParityTests`: a `CompanyStore` wired for a Team
/// Build with every seam stubbed — the room, the planner, the task runner, the assembler and every
/// saver. A real saver calls `Firestore.firestore()`, which TRAPS under an unconfigured
/// `FirebaseApp` and takes the test host down with it.
@MainActor
enum TeamBuildFixture {

    /// Records what the store asked of each seam. Mutated only from closures the store calls on
    /// the main actor, same as the suites that read it.
    final class Probe {
        var vcCalls = 0
        /// What the room was asked, and what chat was sent, in order.
        var vcRequests: [VirtualCompanyRequest] = []
        var chats: [CompanyChatRequest] = []
        var plans: [TeamPlanRequest] = []
        var runs: [RunTaskRequest] = []
        var saves: [(cid: String, runs: [TeamRun])] = []
        /// Flipped mid-test to model a founder revoking the grant.
        var granted = true
        /// The department each approval reached decision extraction with.
        var extractedDepts: [String] = []
    }

    /// The build step's coder: writes nothing and succeeds, so the assembler's fallback
    /// `CLAUDE.md` is what lands in the project.
    final class FakeCoder: ProjectCodeRunning {
        func run(prompt: String, dir: String, allowedTools: [String], maxTurns: Int,
                 timeout: TimeInterval, onEvent: @escaping (String) -> Void) async -> String? {
            onEvent("Write index.html")
            try? "<html></html>".write(toFile: dir + "/index.html", atomically: true, encoding: .utf8)
            return nil
        }
    }

    /// Copied verbatim from `CompanyStoreVirtualCompanyTests`.
    static func routing(_ decision: String) -> VCRouting {
        // agent_meta as the router sends it: chief of staff carries no department key.
        let json: [String: Any] = ["decision": decision, "agents": ["product", "finance"],
                                   "real_question": "q", "request_type": "DECISION",
                                   "agent_meta": [["agent_id": "chief_of_staff", "department_key": NSNull()],
                                                  ["agent_id": "product", "department_key": "product"],
                                                  ["agent_id": "finance", "department_key": "fin"]]]
        return try! JSONDecoder().decode(
            VCRouting.self, from: try! JSONSerialization.data(withJSONObject: json))
    }

    static func aBrief(_ recommendation: String, options: [VCFounderOption]? = nil) -> VCBrief {
        VCBrief(recommendation: recommendation, confidence: 4, confidenceReason: "c",
                theRealDisagreement: "d", tradeoffFounderMustOwn: "t", killCriteria: ["k"],
                nextAction: VCNextAction(action: "a", owner: "Founder"),
                whatWeDontKnow: "u", unresolved: false, founderOptions: options)
    }

    /// The two-way call a room ends with when the founder must choose (CP-031), as on 7 Oct.
    static let twoOptions = [
        VCFounderOption(label: "Booking first, report attached", consequence: "A sprint later, every report attributable."),
        VCFounderOption(label: "Tagged report page this week", consequence: "In tenants' hands within days."),
    ]

    /// Marketing writes the message, Design builds on it, then the build step.
    static let plan = WorkPlan(
        title: "Pants page", slug: "pants-page", summary: "A landing page selling office pants.",
        projectType: "static landing page",
        steps: [
            WorkStep(id: "s1", dept: "mkt", title: "Write the message", instruction: "Headline and copy",
                     kind: "doc", dependsOn: []),
            WorkStep(id: "s2", dept: "design", title: "Design the page", instruction: "Layout and palette",
                     kind: "doc", dependsOn: ["s1"]),
            WorkStep(id: "build", dept: "eng", title: "Build it", instruction: "Static HTML",
                     kind: "other", dependsOn: ["s1", "s2"]),
        ])

    /// A room shaped like `CompanyStoreVirtualCompanyTests.roomWithABrief`: routing, a 60 ms gap,
    /// then the brief. For any decision but `multi_agent` the stream ends after routing (the store
    /// breaks out on the escape hatch anyway). `briefs: false` drops the brief and `done` frames so
    /// the store seals the room as failed.
    static func room(_ decision: String, briefs: Bool = true, options: [VCFounderOption]? = nil,
                     probe: Probe)
    -> (VirtualCompanyRequest) -> AsyncThrowingStream<VirtualCompanyEvent, Error> {
        { req in
            probe.vcCalls += 1
            probe.vcRequests.append(req)
            return AsyncThrowingStream { cont in
                Task {
                    cont.yield(.runStarted(runId: "r1"))
                    cont.yield(.routing(routing(decision)))
                    if decision == "multi_agent" {
                        try? await Task.sleep(nanoseconds: 60_000_000)
                        if briefs {
                            cont.yield(.brief(aBrief("Ship a single landing page", options: options)))
                            cont.yield(.done(runId: "r1", unresolved: false, skipped: nil))
                        }
                    }
                    cont.finish()
                }
            }
        }
    }

    /// Holds a room between `run_started` and its routing frame, for as long as a test needs —
    /// the stretch where the real router spends 60-70 s on its own `claude -p` call.
    final class Gate {
        private var cont: CheckedContinuation<Void, Never>?
        var isWaiting: Bool { cont != nil }
        func wait() async { await withCheckedContinuation { cont = $0 } }
        func open() { cont?.resume(); cont = nil }
    }

    /// `room`, but parked at the gate before routing. `fails: true` ends the stream with an error
    /// instead of routing, the way a dead sidecar does.
    /// `hold` parks it again after routing, so a test can look at the store while the room is on
    /// screen and still running — otherwise the run ends at once and its end-of-run cleanup
    /// hides whether the hand-off itself did anything.
    static func gatedRoom(_ decision: String, gate: Gate, hold: Gate? = nil, fails: Bool = false,
                          probe: Probe)
    -> (VirtualCompanyRequest) -> AsyncThrowingStream<VirtualCompanyEvent, Error> {
        { _ in
            probe.vcCalls += 1
            return AsyncThrowingStream { cont in
                Task {
                    cont.yield(.runStarted(runId: "r1"))
                    await gate.wait()
                    if fails { cont.finish(throwing: VirtualCompanyRunError.malformedResponse); return }
                    cont.yield(.routing(routing(decision)))
                    if let hold { await hold.wait() }
                    if decision == "multi_agent" {
                        cont.yield(.brief(aBrief("Ship a single landing page")))
                        cont.yield(.done(runId: "r1", unresolved: false, skipped: nil))
                    }
                    cont.finish()
                }
            }
        }
    }

    static let failingStreamer: (CompanyChatRequest) -> AsyncThrowingStream<CompanyChatStreamEvent, Error> = { _ in
        AsyncThrowingStream { $0.finish(throwing: CompanyChatStreamError.notSignedIn) }
    }

    static func store(probe: Probe, root: URL, decision: String = "multi_agent", briefs: Bool = true,
                      options: [VCFounderOption]? = nil,
                      grant: Bool = true, runnerDelayNanos: UInt64 = 0, plannerDelayNanos: UInt64 = 0,
                      librarySaverDelayNanos: UInt64 = 5_000_000,
                      planner: (() -> WorkPlan)? = nil,
                      room roomOverride: ((VirtualCompanyRequest) -> AsyncThrowingStream<VirtualCompanyEvent, Error>)? = nil,
                      usageLedger: UsageLedgering? = nil,
                      initial: CompanyState = CompanyState(brief: CompanyBrief(), departments: [], library: [],
                                                           stage: .idea, companionId: "byte", onboardedAt: Date()))
    -> CompanyStore {
        CompanyStore(
            loader: { cid in cid == "u" ? initial : .empty },
            saver: { _, _ in true },
            tasksSaver: { _, _ in true },
            chatSender: { _ in CompanyChatReply(text: "byte's answer", runTaskId: nil) },
            chatStreamer: { req in probe.chats.append(req); return failingStreamer(req) },
            vcRunner: roomOverride ?? room(decision, briefs: briefs, options: options, probe: probe),
            taskRunner: { req in
                probe.runs.append(req)
                if runnerDelayNanos > 0 { try? await Task.sleep(nanoseconds: runnerDelayNanos) }
                return RunTaskResponse(kind: "doc", title: req.taskTitle, body: "# \(req.taskTitle)")
            },
            // A real suspension, like the Firestore write it stands in for. Without it
            // `fileApproval` never yields, so two overlapping approvals cannot interleave and
            // `testApprovingATeamRunTwiceFilesOnce` would pass with or without its guard.
            librarySaver: { _, _ in try? await Task.sleep(nanoseconds: librarySaverDelayNanos); return true },
            firstApprovalSaver: { _, _ in true },
            decisionsSaver: { _, _ in true },
            decisionExtractor: { dto, _ in probe.extractedDepts.append(dto.dept); return [] },
            claudeAuthorisation: ProviderAuthorisation(isAuthorised: { _, _ in grant && probe.granted },
                                                       setAuthorised: { _, _, _ in }),
            teamPlanner: { req in
                probe.plans.append(req)
                if plannerDelayNanos > 0 { try? await Task.sleep(nanoseconds: plannerDelayNanos) }
                return planner?() ?? plan
            },
            teamRunsSaver: { cid, runs in probe.saves.append((cid, runs)); return true },
            assemblerFactory: { ProjectAssembler(root: root, coder: FakeCoder(), git: { _, _ in true }) },
            usageLedger: usageLedger)
    }

    /// Polls rather than sleeping a fixed time: returns as soon as `condition` holds, false on
    /// timeout. Never force-unwrap after this — assert on the Bool, so a timeout fails the one
    /// test instead of trapping the host.
    static func waitFor(timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return true
    }

    /// Hydrate, press Team build, and wait for the plan card.
    static func planned(_ s: CompanyStore) async -> Bool {
        await s.hydrate(companyId: "u")
        await s.startTeamBuild("pants page", language: .en)
        return await waitFor { s.teamRun?.run?.phase == .planned }
    }
}

@MainActor
final class TeamBuildStoreTests: XCTestCase {
    private typealias F = TeamBuildFixture
    private var root: URL!

    override func setUp() {
        super.setUp()
        CompanyStore.execStepNanos = 0
        root = FileManager.default.temporaryDirectory.appendingPathComponent("tbs-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    // MARK: - Library grouping across runs

    /// Every plan numbers its steps s1, s2…, so a synthetic id of just `team-<stepId>` collided
    /// across runs: the resolver took the NEWEST run's "s1", and the first build's Marketing work
    /// was grouped under the second build's Sales — the "Sales showing Engineering's work" bug
    /// class. Two real builds, both with an "s1" in different departments.
    func testTwoRunsWithTheSameStepIdEachFileUnderTheirOwnDepartment() async throws {
        let probe = F.Probe()
        func plan(_ dept: String, _ title: String) -> WorkPlan {
            WorkPlan(title: title, slug: title, summary: "s", projectType: "static landing page",
                     steps: [WorkStep(id: "s1", dept: dept, title: "\(title) step", instruction: "i",
                                      kind: "doc", dependsOn: []),
                             WorkStep(id: "build", dept: "eng", title: "Build", instruction: "b",
                                      kind: "other", dependsOn: ["s1"])])
        }
        var plans = [plan("mkt", "first"), plan("sales", "second")]
        let s = F.store(probe: probe, root: root, planner: { plans.removeFirst() })
        await s.hydrate(companyId: "u")

        for _ in 0..<2 {
            await s.startTeamBuild("a page", language: .en)
            let planned = await F.waitFor { s.teamRun?.run?.phase == .planned }
            XCTAssertTrue(planned, "the plan card never appeared")
            await s.confirmTeamPlan()
            XCTAssertEqual(s.teamRun?.run?.phase, .ready)
            await s.approveTeamRun()
            XCTAssertEqual(s.teamRun?.run?.phase, .filed)
        }

        let drafts = s.company.library.filter { $0.projectPath == nil }
        XCTAssertEqual(drafts.count, 2)
        let firstDraft = try XCTUnwrap(drafts.first { $0.title == "first step" })
        let secondDraft = try XCTUnwrap(drafts.first { $0.title == "second step" })
        XCTAssertEqual(s.deptKey(forSourceTaskId: firstDraft.sourceTaskId), "mkt")
        XCTAssertEqual(s.deptKey(forSourceTaskId: secondDraft.sourceTaskId), "sales")

        let projects = s.company.library.filter { $0.projectPath != nil }
        XCTAssertEqual(projects.count, 2)
        for p in projects {
            XCTAssertEqual(s.deptKey(forSourceTaskId: p.sourceTaskId), "eng", "the project is the build step's work")
        }
    }

    /// Spec §3: the run request carries the step's kind. `RunTaskRequest` has no kind field, so
    /// it rides in the task detail as an instruction to the model.
    func testEachStepsKindReachesTheRunner() async throws {
        let probe = F.Probe()
        var plan = F.plan
        plan.steps[1] = WorkStep(id: "s2", dept: "design", title: "Design the page", instruction: "Layout and palette",
                                 kind: "checklist", dependsOn: ["s1"])
        let s = F.store(probe: probe, root: root, planner: { plan })
        let planned = await F.planned(s)
        XCTAssertTrue(planned, "the plan card never appeared")
        await s.confirmTeamPlan()
        let runId = try XCTUnwrap(s.teamRun?.run?.id)

        let s1 = try XCTUnwrap(probe.runs.first { $0.taskTitle == "Write the message" })
        let s2 = try XCTUnwrap(probe.runs.first { $0.taskTitle == "Design the page" })
        XCTAssertTrue(s1.taskDetail.hasPrefix("Headline and copy"), s1.taskDetail)
        XCTAssertTrue(s1.taskDetail.contains("Deliver it as a doc."), s1.taskDetail)
        XCTAssertTrue(s2.taskDetail.contains("Deliver it as a checklist."), s2.taskDetail)
        XCTAssertEqual(s1.taskId, "team-\(runId)-s1")
    }

    /// The saver is what reaches `companies/{uid}`: once approved, the run is persisted without its
    /// drafts (they are in the Library), and never more than ten runs are written.
    func testAFiledRunIsPersistedWithoutDraftsAndRunsAreCapped() async throws {
        var initial = CompanyState(brief: CompanyBrief(), departments: [], library: [],
                                   stage: .idea, companionId: "byte", onboardedAt: Date())
        initial.teamRuns = (0..<10).map { i -> TeamRun in
            var r = TeamRun(request: "old\(i)", createdAt: Date(timeIntervalSince1970: TimeInterval(i)),
                            brief: nil, plan: F.plan)
            r.phase = .filed
            return r
        }
        let probe = F.Probe()
        let s = F.store(probe: probe, root: root, initial: initial)
        let planned = await F.planned(s)
        XCTAssertTrue(planned, "the plan card never appeared")
        await s.confirmTeamPlan()
        XCTAssertNotNil(s.teamRun?.run?.state("s1")?.draft, "precondition: the ready run holds drafts")
        await s.approveTeamRun()

        let saved = try XCTUnwrap(probe.saves.last?.runs)
        XCTAssertLessThanOrEqual(saved.count, 10)
        XCTAssertFalse(saved.contains { $0.request == "old0" }, "the oldest filed run is dropped first")
        let filed = try XCTUnwrap(saved.first { $0.id == s.teamRun?.run?.id })
        XCTAssertEqual(filed.phase, .filed)
        XCTAssertTrue(filed.steps.allSatisfy { $0.draft == nil }, "a filed run persists without drafts")
        XCTAssertEqual(s.company.teamRuns, saved, "memory and Firestore hold the same list")
    }

    /// Planning can take up to 180 s, and a greyed button was the only sign anything was happening.
    /// `isPlanningTeamBuild` drives the "Planning the work…" row: on once the room has ended and
    /// the planner is working, off once the plan lands. Not on during the room itself — the room
    /// has its own card.
    func testIsPlanningTeamBuildIsTrueOnlyWhileThePlannerWorks() async throws {
        let probe = F.Probe()
        let s = F.store(probe: probe, root: root, plannerDelayNanos: 400_000_000)
        await s.hydrate(companyId: "u")
        XCTAssertFalse(s.isPlanningTeamBuild)
        await s.startTeamBuild("pants page", language: .en)
        let planning = await F.waitFor { probe.plans.count == 1 }
        XCTAssertTrue(planning, "the planner was never asked")
        XCTAssertTrue(s.isPlanningTeamBuild, "the room ended with a brief and the planner is working")
        XCTAssertNil(s.teamRun, "no plan yet")

        let planned = await F.waitFor { s.teamRun?.run?.phase == .planned }
        XCTAssertTrue(planned, "the plan card never appeared")
        XCTAssertFalse(s.isPlanningTeamBuild, "the plan landed")
    }

    /// The planning line's pets are the room's seats (6 Oct design pass), so the founder sees who
    /// is splitting the work. They clear when the plan lands, and a press the router sent straight
    /// to the planner (`single_agent`, no room) shows none rather than a guess.
    func testPlanningShowsTheDepartmentsTheRoomSeated() async throws {
        let probe = F.Probe()
        let s = F.store(probe: probe, root: root, plannerDelayNanos: 400_000_000)
        await s.hydrate(companyId: "u")
        XCTAssertEqual(s.teamPlanningDepartments, [])
        await s.startTeamBuild("pants page", language: .en)
        _ = await F.waitFor { probe.plans.count == 1 }
        XCTAssertTrue(s.isPlanningTeamBuild, "precondition: the planner is working")
        XCTAssertEqual(s.teamPlanningDepartments, ["product", "fin"], "the room's seats, chief of staff left out")
        _ = await F.waitFor { s.teamRun?.run?.phase == .planned }
        XCTAssertEqual(s.teamPlanningDepartments, [], "the plan landed; the line is gone")
    }

    func testPlanningWithoutARoomShowsNoPets() async throws {
        let probe = F.Probe()
        let s = F.store(probe: probe, root: root, decision: "single_agent", plannerDelayNanos: 400_000_000)
        await s.hydrate(companyId: "u")
        await s.startTeamBuild("pants page", language: .en)
        _ = await F.waitFor { probe.plans.count == 1 }
        XCTAssertTrue(s.isPlanningTeamBuild, "precondition: single_agent still plans, from the request")
        XCTAssertEqual(s.teamPlanningDepartments, [])
        _ = await F.waitFor { s.teamRun?.run?.phase == .planned }
    }

    /// 6 Oct (build 8 and main): pressing Team build sent chat the bare request, so the reply that
    /// runs alongside the room read it as an ordinary ask and answered "I can't build that from
    /// this chat" / "I've put it up as an offer" — while the team went on to build it. Chat is now
    /// told the team is taking it on; the founder's bubble and the room's question keep her words.
    func testTeamBuildTellsChatTheTeamIsTakingItOn() async throws {
        let probe = F.Probe()
        let s = F.store(probe: probe, root: root)
        await s.hydrate(companyId: "u")
        await s.startTeamBuild("pants page", language: .en)
        let chat = try XCTUnwrap(probe.chats.first, "no chat turn went out")
        XCTAssertEqual(chat.userMessage, TeamBuildCopy.chatFrame("pants page", lang: .en))
        XCTAssertEqual(s.chatMessages.first { $0.role == .me }?.text, "pants page", "her bubble shows her words")
        XCTAssertEqual(probe.vcRequests.first?.request, "pants page", "the room is asked her words, unframed")
        _ = await F.waitFor { s.teamRun?.run?.phase == .planned }
    }

    func testIsPlanningTeamBuildIsFalseWhileTheRoomIsStillMeeting() async throws {
        let probe = F.Probe()
        let s = F.store(probe: probe, root: root)
        await s.hydrate(companyId: "u")
        let press = Task { await s.startTeamBuild("pants page", language: .en) }
        let roomStarted = await F.waitFor { probe.vcCalls == 1 }
        XCTAssertTrue(roomStarted)
        XCTAssertTrue(probe.plans.isEmpty, "precondition: the room has not ended")
        XCTAssertFalse(s.isPlanningTeamBuild, "the room has its own card; this row is for planning")
        await press.value
        _ = await F.waitFor { s.teamRun?.run?.phase == .planned }
    }

    /// Drafts filed before ids were namespaced by run still resolve, best effort.
    func testALegacyTeamIdStillResolves() async throws {
        var run = TeamRun(request: "r", createdAt: Date(), brief: nil, plan: F.plan)
        run.phase = .filed
        var initial = CompanyState(brief: CompanyBrief(), departments: [], library: [],
                                   stage: .idea, companionId: "byte", onboardedAt: Date())
        initial.teamRuns = [run]
        let s = F.store(probe: F.Probe(), root: root, initial: initial)
        await s.hydrate(companyId: "u")
        XCTAssertEqual(s.deptKey(forSourceTaskId: "team-s2"), "design")
        XCTAssertEqual(s.deptKey(forSourceTaskId: "team-\(run.id)-s2"), "design")
        XCTAssertNil(s.deptKey(forSourceTaskId: "team-nope"))
    }

    // MARK: - Room → plan

    func testTeamBuildConvenesThePlansAndShowsAPlanCard() async throws {
        let probe = F.Probe()
        let s = F.store(probe: probe, root: root)
        let planned = await F.planned(s)
        XCTAssertTrue(planned, "the plan card never appeared")

        XCTAssertEqual(probe.vcCalls, 1, "Team build must convene the room")
        XCTAssertEqual(probe.plans.count, 1)
        let req = try XCTUnwrap(probe.plans.first)
        XCTAssertNotNil(req.brief, "a room that delivered a brief must plan from it")
        XCTAssertEqual(req.brief?.recommendation, "Ship a single landing page")
        XCTAssertEqual(req.request, "pants page")
        XCTAssertEqual(req.language, "en")
        // `.empty`-shaped company has no departments, so the roster falls back to every
        // routable department.
        XCTAssertEqual(Set(req.roster), WorkPlanValidation.routable)

        let run = try XCTUnwrap(s.teamRun?.run)
        XCTAssertEqual(run.request, "pants page")
        XCTAssertEqual(run.plan.steps.map(\.id), ["s1", "s2", "build"])
        XCTAssertTrue(s.chatMessages.contains { $0.teamRunId == run.id }, "no plan card in the transcript")
        XCTAssertFalse(s.teamBuildAvailable, "a planned run is active, so another must not start")
    }

    // MARK: - A two-way call: the plan waits for the founder (7 Oct)

    /// Seen twice on 7 Oct: the room ended with "Your call" (two options), Team build planned at
    /// once from the room's own recommendation, and the founder then locked in the OTHER option.
    /// The plan card still led with the option she had turned down, and Start building would
    /// have built it. A room that ends with two options now plans nothing until she picks.
    func testARoomThatEndsWithTwoOptionsWaitsForTheCall() async throws {
        let probe = F.Probe()
        let s = F.store(probe: probe, root: root, options: F.twoOptions)
        await s.hydrate(companyId: "u")
        await s.startTeamBuild("pants page", language: .en)
        let landed = await F.waitFor { s.chatMessages.contains { $0.vcRun?.brief != nil } }
        XCTAssertTrue(landed, "the room never delivered its call")
        let said = await F.waitFor { s.chatMessages.contains { $0.text == TeamBuildCopy.awaitingCall(.en) } }
        XCTAssertTrue(said, "she must be told the plan follows her call")
        _ = await F.waitFor(timeout: 0.3) { false }
        XCTAssertTrue(probe.plans.isEmpty, "nothing may be planned before she picks")
        XCTAssertNil(s.teamRun)
        XCTAssertFalse(s.isPlanningTeamBuild, "no planning row while it waits on her")
        XCTAssertTrue(s.teamBuildAvailable, "waiting on her must not hold the Team build button")
    }

    /// Her pick IS the plan's starting point: the planner and the run see the chosen option as
    /// the decision, with no open choice left for either to settle on its own.
    func testLockingInAnOptionPlansFromThePick() async throws {
        let probe = F.Probe()
        let s = F.store(probe: probe, root: root, options: F.twoOptions)
        await s.hydrate(companyId: "u")
        await s.startTeamBuild("pants page", language: .en)
        let landed = await F.waitFor { s.chatMessages.contains { $0.text == TeamBuildCopy.awaitingCall(.en) } }
        XCTAssertTrue(landed)
        let room = try XCTUnwrap(s.chatMessages.first { $0.vcRun?.brief != nil })
        let pick = F.twoOptions[1]
        await s.lockInVirtualCompanyDecision(try XCTUnwrap(room.vcRun), messageId: room.id, choice: pick)

        let planned = await F.waitFor { s.teamRun?.run?.phase == .planned }
        XCTAssertTrue(planned, "locking in must plan")
        XCTAssertEqual(probe.plans.count, 1)
        let brief = try XCTUnwrap(probe.plans.first?.brief)
        XCTAssertEqual(brief.recommendation, "Tagged report page this week: In tenants' hands within days.")
        XCTAssertNil(brief.founderOptions, "no open choice may reach the planner")
        XCTAssertTrue(brief.tradeoffFounderMustOwn.contains("Booking first, report attached"),
                      "what she turned down is named, so the plan does not drift back to it")
        XCTAssertEqual(s.teamRun?.run?.brief?.recommendation, brief.recommendation,
                       "the build step reads the run's brief, so it must carry the pick too")
    }

    /// Locking in a room that is not the waiting Team build's (a Plan-mode room) plans nothing.
    func testLockingInAnotherRoomDoesNotPlan() async throws {
        let probe = F.Probe()
        let s = F.store(probe: probe, root: root, options: F.twoOptions)
        await s.hydrate(companyId: "u")
        await s.sendChat("should we raise prices", language: .en, convenesRoom: true)
        let landed = await F.waitFor { s.chatMessages.contains { $0.vcRun?.brief != nil } }
        XCTAssertTrue(landed)
        let room = try XCTUnwrap(s.chatMessages.first { $0.vcRun?.brief != nil })
        await s.lockInVirtualCompanyDecision(try XCTUnwrap(room.vcRun), messageId: room.id,
                                             choice: F.twoOptions[0])
        _ = await F.waitFor(timeout: 0.3) { false }
        XCTAssertTrue(probe.plans.isEmpty)
        XCTAssertFalse(s.chatMessages.contains { $0.text == TeamBuildCopy.awaitingCall(.en) })
    }

    func testSingleAgentPlansFromTheRequestAlone() async throws {
        let probe = F.Probe()
        let s = F.store(probe: probe, root: root, decision: "single_agent")
        let planned = await F.planned(s)
        XCTAssertTrue(planned, "a single_agent routing must still plan")
        XCTAssertEqual(probe.plans.count, 1)
        XCTAssertNil(probe.plans.first?.brief, "no room sat, so there is no brief to plan from")
        XCTAssertEqual(probe.plans.first?.request, "pants page")
    }

    func testNeedsClarificationDoesNotPlan() async throws {
        let probe = F.Probe()
        let s = F.store(probe: probe, root: root, decision: "needs_clarification")
        await s.hydrate(companyId: "u")
        await s.startTeamBuild("pants page", language: .en)
        // Nothing observable happens on this path by design, so give the room time to end.
        _ = await F.waitFor(timeout: 0.4) { false }
        XCTAssertEqual(probe.vcCalls, 1, "the room must have been convened for this to mean anything")
        XCTAssertTrue(probe.plans.isEmpty, "a clarifying question must not be planned around")
        XCTAssertNil(s.teamRun)
    }

    func testARoomThatFailsSaysSoAndDoesNotPlan() async throws {
        let probe = F.Probe()
        let s = F.store(probe: probe, root: root, briefs: false)
        await s.hydrate(companyId: "u")
        await s.startTeamBuild("pants page", language: .en)
        let said = await F.waitFor {
            s.chatMessages.contains { $0.text == "The team couldn't finish meeting. Tap Team build to try again." }
        }
        XCTAssertTrue(said, "a failed room must say so")
        XCTAssertTrue(probe.plans.isEmpty)
        XCTAssertNil(s.teamRun)
    }

    // MARK: - Go

    func testGoRunsTheStepsAndReachesReady() async throws {
        let probe = F.Probe()
        let s = F.store(probe: probe, root: root)
        let planned = await F.planned(s)
        XCTAssertTrue(planned)
        XCTAssertTrue(probe.runs.isEmpty, "nothing may run before Go")

        await s.confirmTeamPlan()

        let run = try XCTUnwrap(s.teamRun?.run)
        XCTAssertEqual(run.phase, .ready)
        XCTAssertEqual(probe.runs.map(\.deptKey), ["mkt", "design"], "one run per department step, in dependency order")
        XCTAssertEqual(probe.runs.map(\.taskTitle), ["Write the message", "Design the page"])
        // Design waits for Marketing and receives its draft.
        XCTAssertNil(probe.runs[0].upstream)
        XCTAssertEqual(probe.runs[1].upstream?.map(\.taskTitle), ["Write the message"])
        let path = try XCTUnwrap(run.projectPath)
        XCTAssertTrue(path.hasPrefix(root.path), "project landed outside the assembler's root: \(path)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path + "/CLAUDE.md"))
        XCTAssertTrue(probe.saves.allSatisfy { $0.cid == "u" })
        XCTAssertEqual(probe.saves.last?.runs.last?.phase, .ready)
        XCTAssertEqual(s.company.teamRuns.last?.phase, .ready)
        XCTAssertTrue(s.company.library.isEmpty, "nothing is filed before approval")
    }

    // MARK: - Gates

    func testWithoutAGrantNothingRunsAndTheReasonIsShown() async {
        let probe = F.Probe()
        let s = F.store(probe: probe, root: root, grant: false)
        await s.hydrate(companyId: "u")
        XCTAssertFalse(s.teamBuildAvailable)
        await s.startTeamBuild("pants page", language: .en)

        let expected = BlockedOffer.resolve(reason: .notGranted, installed: s.installedProviders.installed,
                                            surface: .claudeOnly).founderText(lang: .en)
        XCTAssertEqual(s.chatMessages.last?.text, expected)
        XCTAssertEqual(probe.vcCalls, 0, "no room without a grant")
        XCTAssertTrue(probe.plans.isEmpty)
        XCTAssertNil(s.teamRun)
    }

    func testASecondTeamBuildIsRefusedWhileOneIsActive() async throws {
        let probe = F.Probe()
        let s = F.store(probe: probe, root: root)
        let planned = await F.planned(s)
        XCTAssertTrue(planned)
        let firstId = s.teamRun?.run?.id
        let before = s.chatMessages.count

        await s.startTeamBuild("another page", language: .en)
        _ = await F.waitFor(timeout: 0.3) { false }

        XCTAssertEqual(probe.vcCalls, 1, "a second room was convened while a run was active")
        XCTAssertEqual(probe.plans.count, 1)
        XCTAssertEqual(s.chatMessages.count, before)
        XCTAssertEqual(s.teamRun?.run?.id, firstId)

        // Cancelling the plan ends the run, and the button comes back.
        s.cancelTeamPlan()
        XCTAssertEqual(s.teamRun?.run?.phase, .cancelled)
        XCTAssertTrue(s.teamBuildAvailable)
    }

    // MARK: - Account safety

    func testAccountSwitchDropsLateResults() async throws {
        let probe = F.Probe()
        let s = F.store(probe: probe, root: root, runnerDelayNanos: 200_000_000)
        let planned = await F.planned(s)
        XCTAssertTrue(planned)
        let runId = try XCTUnwrap(s.teamRun?.run?.id)

        let go = Task { await s.confirmTeamPlan() }
        let started = await F.waitFor { probe.runs.count == 1 }
        XCTAssertTrue(started, "the first step never started")

        await s.hydrate(companyId: "other")
        XCTAssertNil(s.teamRun, "the outgoing account's run must not survive the switch")
        let savesAtSwitch = probe.saves.count

        await go.value   // the late result lands and the run settles
        _ = await F.waitFor(timeout: 0.3) { false }

        XCTAssertFalse(probe.saves.contains { $0.cid == "other" && $0.runs.contains { $0.id == runId } },
                       "the first account's run was saved into the second account")
        XCTAssertEqual(probe.saves.count, savesAtSwitch, "a late result was saved after the switch")
        XCTAssertFalse(s.company.teamRuns.contains { $0.id == runId },
                       "the first account's run leaked into the second account's state")
        XCTAssertNil(s.teamRun)
    }

    func testHydrateRestoresAnActiveRunAsInterrupted() async throws {
        var run = TeamRun(request: "pants page", createdAt: Date(), brief: nil, plan: F.plan)
        run.phase = .running
        run.steps[0].status = .running
        let probe = F.Probe()
        let s = F.store(probe: probe, root: root,
                        initial: CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                                              companionId: "byte", onboardedAt: Date(), teamRuns: [run]))
        await s.hydrate(companyId: "u")

        XCTAssertEqual(s.teamRun?.run?.id, run.id)
        XCTAssertEqual(s.teamRun?.run?.state("s1")?.status, .interrupted)
        XCTAssertFalse(s.teamBuildAvailable, "a restored active run still holds the one slot")
        XCTAssertTrue(probe.runs.isEmpty, "restoring must not resume work on its own")
    }

    func testHydrateDoesNotRestoreAFinishedRun() async {
        var run = TeamRun(request: "pants page", createdAt: Date(), brief: nil, plan: F.plan)
        run.phase = .filed
        let s = F.store(probe: F.Probe(), root: root,
                        initial: CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                                              companionId: "byte", onboardedAt: Date(), teamRuns: [run]))
        await s.hydrate(companyId: "u")
        XCTAssertNil(s.teamRun)
        XCTAssertTrue(s.teamBuildAvailable)
    }

    // MARK: - Review round 1

    /// A fixture company whose one Team Build is in `phase`, loaded by `hydrate`.
    private func storeWithRun(_ probe: F.Probe, _ mutate: (inout TeamRun) -> Void) -> CompanyStore {
        var run = TeamRun(request: "pants page", createdAt: Date(), brief: nil, plan: F.plan)
        mutate(&run)
        return F.store(probe: probe, root: root,
                       initial: CompanyState(brief: CompanyBrief(), departments: [], library: [], stage: .idea,
                                             companionId: "byte", onboardedAt: Date(), teamRuns: [run]))
    }

    private func notGrantedText(_ s: CompanyStore) -> String {
        BlockedOffer.resolve(reason: .notGranted, installed: s.installedProviders.installed,
                             surface: .claudeOnly).founderText(lang: .en)
    }

    /// Go, Retry and Continue each spend the plan (the build step spawns `claude`), and the grant
    /// can be revoked between the press and any of them.
    func testGoRetryAndContinueRefuseOnceTheGrantIsRevoked() async throws {
        // Go on a planned run.
        let p1 = F.Probe()
        let s1 = F.store(probe: p1, root: root)
        let planned = await F.planned(s1)
        XCTAssertTrue(planned)
        p1.granted = false
        await s1.confirmTeamPlan()
        XCTAssertEqual(s1.teamRun?.run?.phase, .planned, "Go ran without a grant")
        XCTAssertTrue(p1.runs.isEmpty)
        XCTAssertEqual(s1.chatMessages.last?.text, notGrantedText(s1))

        // Continue on a run restored with an interrupted step.
        let p2 = F.Probe()
        let s2 = storeWithRun(p2) { $0.phase = .running; $0.steps[0].status = .running }
        await s2.hydrate(companyId: "u")
        p2.granted = false
        await s2.continueTeamRun()
        XCTAssertEqual(s2.teamRun?.run?.state("s1")?.status, .interrupted, "Continue ran without a grant")
        XCTAssertTrue(p2.runs.isEmpty)
        XCTAssertEqual(s2.chatMessages.last?.text, notGrantedText(s2))

        // Retry on a failed step.
        let p3 = F.Probe()
        let s3 = storeWithRun(p3) { $0.phase = .failed; $0.steps[0].status = .failed("x") }
        await s3.hydrate(companyId: "u")
        p3.granted = false
        await s3.retryTeamStep("s1")
        XCTAssertEqual(s3.teamRun?.run?.state("s1")?.status, .failed("x"), "Retry ran without a grant")
        XCTAssertTrue(p3.runs.isEmpty)
        XCTAssertEqual(s3.chatMessages.last?.text, notGrantedText(s3))
    }

    /// A finished project waiting for Approve survives a relaunch, can still be approved, and
    /// does not hold the one-run slot.
    func testHydrateRestoresAReadyRunAndItCanBeApproved() async throws {
        let dir = root.appendingPathComponent("pants-page")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let probe = F.Probe()
        let s = storeWithRun(probe) { r in
            r.phase = .ready
            r.projectPath = dir.path
            for (i, id) in ["s1", "s2", "build"].enumerated() {
                r.steps[i].status = .done
                if id != "build" {
                    r.steps[i].draft = Deliverable(kind: .doc, title: "Draft \(id)", body: "# \(id)",
                                                   sourceTaskId: "team-\(id)")
                }
            }
        }
        await s.hydrate(companyId: "u")
        XCTAssertEqual(s.teamRun?.run?.phase, .ready, "a ready run was lost on relaunch")
        XCTAssertTrue(s.teamBuildAvailable, "a ready run must not hold the one-run slot")

        await s.approveTeamRun()
        XCTAssertEqual(s.company.library.count, 3)
        XCTAssertEqual(s.company.library.last?.projectPath, dir.path)
        XCTAssertEqual(s.company.library.last?.body, "A landing page selling office pants.",
                       "with no CLAUDE.md the body falls back to the plan summary")
        XCTAssertEqual(s.teamRun?.run?.phase, .filed)
    }

    /// An account switch mid-approval must not file the outgoing founder's work into the next.
    func testAccountSwitchMidApprovalFilesNothingIntoTheNewAccount() async throws {
        let probe = F.Probe()
        let s = F.store(probe: probe, root: root, librarySaverDelayNanos: 200_000_000)
        let planned = await F.planned(s)
        XCTAssertTrue(planned)
        await s.confirmTeamPlan()
        XCTAssertEqual(s.teamRun?.run?.phase, .ready)

        let approve = Task { await s.approveTeamRun() }
        // The first draft is appended before `fileApproval`'s first suspension (the library
        // saver sleeps), so this is the loop parked mid-way.
        let parked = await F.waitFor { s.company.library.count == 1 }
        XCTAssertTrue(parked)
        await s.hydrate(companyId: "other")
        await approve.value

        XCTAssertEqual(s.companyId, "other")
        XCTAssertTrue(s.company.library.isEmpty, "account A's work was filed into account B")
    }

    func testStartTeamBuildDoesNothingInPrototypeMode() async throws {
        let restore = PrototypeMode.isOn
        defer { PrototypeMode.set(restore) }
        let probe = F.Probe()
        let s = F.store(probe: probe, root: root)
        await s.hydrate(companyId: "u")
        XCTAssertTrue(PrototypeMode.set(true), "could not enter prototype mode")
        await s.startTeamBuild("pants page", language: .en)
        PrototypeMode.set(restore)
        XCTAssertEqual(probe.vcCalls, 0, "the demo convened a real room")
        XCTAssertTrue(probe.plans.isEmpty)
    }

    /// Planning runs in its own task, so an account switch can land after the room ends and
    /// before planning starts. It must not read the incoming account's company, or plan at all.
    /// Driven directly: that scheduling gap cannot be held open deterministically from outside.
    func testAnAccountSwitchBeforePlanningStartsPlansNothing() async throws {
        let probe = F.Probe()
        let s = F.store(probe: probe, root: root)
        await s.hydrate(companyId: "other")
        await s.planTeamBuild(CompanyStore.PendingTeamBuild(ask: "pants page", language: .en, cid: "u"), brief: nil)
        XCTAssertTrue(probe.plans.isEmpty, "planning ran for account A after the switch to B")
        XCTAssertNil(s.teamRun)
    }

    /// Between the room ending and the plan landing, `teamRun` is still nil — a second press there
    /// must not convene a second paid room. The slot is released on every exit path.
    func testASecondPressWhilePlanningIsRefused() async throws {
        let probe = F.Probe()
        let s = F.store(probe: probe, root: root, plannerDelayNanos: 300_000_000)
        await s.hydrate(companyId: "u")
        await s.startTeamBuild("pants page", language: .en)
        let planning = await F.waitFor { probe.plans.count == 1 }
        XCTAssertTrue(planning)
        XCTAssertNil(s.teamRun)
        XCTAssertFalse(s.teamBuildAvailable, "the button is live while a plan is in flight")

        await s.startTeamBuild("another page", language: .en)
        XCTAssertEqual(probe.vcCalls, 1, "a second room was convened while the first was planning")

        let landed = await F.waitFor { s.teamRun?.run?.phase == .planned }
        XCTAssertTrue(landed)
        s.cancelTeamPlan()
        XCTAssertTrue(s.teamBuildAvailable, "planning's success path must release the slot")
    }

    func testClarifyAndAFailedRoomReleaseThePlanningSlot() async throws {
        let p1 = F.Probe()
        let s1 = F.store(probe: p1, root: root, decision: "needs_clarification")
        await s1.hydrate(companyId: "u")
        await s1.startTeamBuild("pants page", language: .en)
        let freed1 = await F.waitFor { s1.teamBuildAvailable }
        XCTAssertTrue(freed1, "a clarifying room left the button disabled forever")

        let p2 = F.Probe()
        let s2 = F.store(probe: p2, root: root, briefs: false)
        await s2.hydrate(companyId: "u")
        await s2.startTeamBuild("pants page", language: .en)
        let freed2 = await F.waitFor { s2.teamBuildAvailable }
        XCTAssertTrue(freed2, "a failed room left the button disabled forever")
    }

    /// The incoming account never inherits the outgoing one's planning slot.
    func testHydrateReleasesThePlanningSlot() async throws {
        let probe = F.Probe()
        let s = F.store(probe: probe, root: root, plannerDelayNanos: 1_000_000_000)
        await s.hydrate(companyId: "u")
        await s.startTeamBuild("pants page", language: .en)
        let planning = await F.waitFor { probe.plans.count == 1 }
        XCTAssertTrue(planning)
        XCTAssertFalse(s.teamBuildAvailable)
        await s.hydrate(companyId: "other")
        XCTAssertTrue(s.teamBuildAvailable, "account B's button is disabled by account A's plan")
    }

    // MARK: - CP-027: the press is visible until the room lands

    /// Between the press and the router's hand-off the room has no message of its own, so for the
    /// 60-70 s the router takes there was nothing on screen but byte's first reply — the build 4
    /// "Team Build looks frozen" report. `isConveningTeamRoom` covers exactly that stretch.
    func testATeamBuildShowsAsConveningUntilTheRouterHandsOff() async {
        let probe = F.Probe(), gate = F.Gate(), hold = F.Gate()
        let s = F.store(probe: probe, root: root,
                        room: F.gatedRoom("multi_agent", gate: gate, hold: hold, probe: probe))
        await s.hydrate(companyId: "u")
        XCTAssertFalse(s.isConveningTeamRoom, "nothing is convening before the press")

        await s.startTeamBuild("pants page", language: .en)
        let parked = await F.waitFor { gate.isWaiting }
        XCTAssertTrue(parked, "the room never reached its routing call")
        XCTAssertTrue(s.isConveningTeamRoom, "while the router decides, the press must show")

        gate.open()
        let landed = await F.waitFor { s.chatMessages.contains { $0.vcRun != nil } && hold.isWaiting }
        XCTAssertTrue(landed, "the room card never landed")
        XCTAssertFalse(s.isConveningTeamRoom, "the room card takes over once it is on screen")
        hold.open()
        let planned = await F.waitFor { s.teamRun?.run?.phase == .planned }
        XCTAssertTrue(planned, "the run never reached its plan")
    }

    /// The router can send the ask elsewhere (the escape hatch). No room is coming, so the
    /// convening row must not outlive that answer.
    func testConveningEndsWhenTheRouterDeclinesTheRoom() async {
        let probe = F.Probe(), gate = F.Gate()
        let s = F.store(probe: probe, root: root, room: F.gatedRoom("single_agent", gate: gate, probe: probe))
        await s.hydrate(companyId: "u")
        await s.startTeamBuild("pants page", language: .en)
        let parked = await F.waitFor { gate.isWaiting }
        XCTAssertTrue(parked, "the room never reached its routing call")

        gate.open()
        let cleared = await F.waitFor { !s.isConveningTeamRoom }
        XCTAssertTrue(cleared, "a declined room left the convening row up")
        XCTAssertFalse(s.chatMessages.contains { $0.vcRun != nil }, "precondition: no room was shown")
    }

    /// A sidecar that dies before routing leaves no room at all. The row must end with the run,
    /// or it would tick forever above "The team couldn't finish meeting".
    func testConveningEndsWhenTheRoomFailsBeforeRouting() async {
        let probe = F.Probe(), gate = F.Gate()
        let s = F.store(probe: probe, root: root,
                        room: F.gatedRoom("multi_agent", gate: gate, fails: true, probe: probe))
        await s.hydrate(companyId: "u")
        await s.startTeamBuild("pants page", language: .en)
        let parked = await F.waitFor { gate.isWaiting }
        XCTAssertTrue(parked, "the room never reached its routing call")

        gate.open()
        let cleared = await F.waitFor { !s.isConveningTeamRoom }
        XCTAssertTrue(cleared, "a failed room left the convening row up")
    }
}

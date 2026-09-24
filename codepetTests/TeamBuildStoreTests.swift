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
        let json: [String: Any] = ["decision": decision, "agents": ["product", "finance"],
                                   "real_question": "q", "request_type": "DECISION"]
        return try! JSONDecoder().decode(
            VCRouting.self, from: try! JSONSerialization.data(withJSONObject: json))
    }

    static func aBrief(_ recommendation: String) -> VCBrief {
        VCBrief(recommendation: recommendation, confidence: 4, confidenceReason: "c",
                theRealDisagreement: "d", tradeoffFounderMustOwn: "t", killCriteria: ["k"],
                nextAction: VCNextAction(action: "a", owner: "Founder"),
                whatWeDontKnow: "u", unresolved: false)
    }

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
    static func room(_ decision: String, briefs: Bool = true, probe: Probe)
    -> (VirtualCompanyRequest) -> AsyncThrowingStream<VirtualCompanyEvent, Error> {
        { _ in
            probe.vcCalls += 1
            return AsyncThrowingStream { cont in
                Task {
                    cont.yield(.runStarted(runId: "r1"))
                    cont.yield(.routing(routing(decision)))
                    if decision == "multi_agent" {
                        try? await Task.sleep(nanoseconds: 60_000_000)
                        if briefs {
                            cont.yield(.brief(aBrief("Ship a single landing page")))
                            cont.yield(.done(runId: "r1", unresolved: false, skipped: nil))
                        }
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
                      grant: Bool = true, runnerDelayNanos: UInt64 = 0, plannerDelayNanos: UInt64 = 0,
                      librarySaverDelayNanos: UInt64 = 5_000_000,
                      initial: CompanyState = CompanyState(brief: CompanyBrief(), departments: [], library: [],
                                                           stage: .idea, companionId: "byte", onboardedAt: Date()))
    -> CompanyStore {
        CompanyStore(
            loader: { cid in cid == "u" ? initial : .empty },
            saver: { _, _ in true },
            tasksSaver: { _, _ in true },
            chatSender: { _ in CompanyChatReply(text: "byte's answer", runTaskId: nil) },
            chatStreamer: failingStreamer,
            vcRunner: room(decision, briefs: briefs, probe: probe),
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
                return plan
            },
            teamRunsSaver: { cid, runs in probe.saves.append((cid, runs)); return true },
            assemblerFactory: { ProjectAssembler(root: root, coder: FakeCoder(), git: { _, _ in true }) })
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
}

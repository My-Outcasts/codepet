// codepetTests/TeamRunCoordinatorTests.swift
import XCTest
@testable import codepet

@MainActor
final class TeamRunCoordinatorTests: XCTestCase {
    private actor Log {
        var started: [String] = []; var upstreamFor: [String: [String]] = [:]; var peak = 0; var live = 0
        func begin(_ id: String, _ up: [String]) { started.append(id); upstreamFor[id] = up; live += 1; peak = max(peak, live) }
        func end() { live -= 1 }
    }
    private func step(_ id: String, _ deps: [String] = []) -> WorkStep {
        WorkStep(id: id, dept: "mkt", title: id, instruction: "", kind: "doc", dependsOn: deps)
    }
    private func run(_ steps: [WorkStep]) -> TeamRun {
        let plan = WorkPlanValidation.validate(WorkPlan(title: "t", slug: "t", summary: "", projectType: "", steps: steps),
                                               roster: ["mkt"])!
        return TeamRun(request: "r", createdAt: Date(), brief: nil, plan: plan)
    }
    private func draft(_ id: String) -> Deliverable { Deliverable(kind: .doc, title: "out-\(id)", body: "body \(id)") }

    private func coordinator(log: Log, fail: Set<String> = [], assemble: TeamAssemblyResult = .success(path: "/tmp/p"),
                             saves: (() -> Void)? = nil) -> TeamRunCoordinator {
        TeamRunCoordinator(
            runStep: { step, up in
                await log.begin(step.id, up.map(\.taskTitle))
                try? await Task.sleep(nanoseconds: 20_000_000)
                await log.end()
                return fail.contains(step.id) ? .failure("boom") : .success(self.draft(step.id))
            },
            assemble: { _, onLog in onLog("wrote index.html"); return assemble },
            save: { _ in saves?() })
    }

    func testChainRunsInOrderAndFeedsOnlyDirectDeps() async {
        let log = Log()
        let c = coordinator(log: log)
        c.load(run([step("a"), step("b", ["a"]), step("c", ["b"])]))
        await c.start()
        let started = await log.started
        let up = await log.upstreamFor
        XCTAssertEqual(started, ["a", "b", "c"])
        XCTAssertEqual(up["c"], ["out-b"], "C receives B's draft, not A's")
        XCTAssertEqual(c.run?.phase, .ready)
        XCTAssertEqual(c.run?.projectPath, "/tmp/p")
        XCTAssertEqual(c.buildLog, ["wrote index.html"])
    }
    func testNeverMoreThanThreeAtOnce() async {
        let log = Log()
        let c = coordinator(log: log)
        c.load(run((1...6).map { step("s\($0)") }))
        await c.start()
        let peak = await log.peak
        XCTAssertEqual(peak, 3)
    }
    func testFailureBlocksOnlyDependentsAndRetryResumes() async {
        let log = Log()
        var failing: Set<String> = ["a"]
        let c = TeamRunCoordinator(
            runStep: { step, _ in await log.begin(step.id, []); await log.end()
                return failing.contains(step.id) ? .failure("boom") : .success(self.draft(step.id)) },
            assemble: { _, _ in .success(path: "/tmp/p") }, save: { _ in })
        c.load(run([step("a"), step("b", ["a"]), step("x")]))
        await c.start()
        XCTAssertEqual(c.run?.state("a")?.status, .failed("boom"))
        XCTAssertEqual(c.run?.state("b")?.status, .blocked)
        XCTAssertEqual(c.run?.state("x")?.status, .done)
        XCTAssertEqual(c.run?.state("build")?.status, .blocked)
        XCTAssertEqual(c.run?.phase, .failed)
        failing = []
        await c.retry(stepId: "a")
        XCTAssertEqual(c.run?.state("b")?.status, .done)
        XCTAssertEqual(c.run?.phase, .ready)
    }
    func testAssemblyFailureFailsTheBuildStep() async {
        let c = coordinator(log: Log(), assemble: .failure("Timed out after 15 min"))
        c.load(run([step("a")]))
        await c.start()
        XCTAssertEqual(c.run?.state("build")?.status, .failed("Timed out after 15 min"))
        XCTAssertEqual(c.run?.phase, .failed)
    }
    func testLoneBuildStepGoesStraightToAssembly() async {
        let c = coordinator(log: Log())
        c.load(run([]))
        await c.start()
        XCTAssertEqual(c.run?.phase, .ready)
    }
    func testStopCancelsEverythingNotDone() async {
        let c = TeamRunCoordinator(
            runStep: { _, _ in try? await Task.sleep(nanoseconds: 2_000_000_000); return .failure("late") },
            assemble: { _, _ in .success(path: "/p") }, save: { _ in })
        c.load(run([step("a"), step("b", ["a"])]))
        let t = Task { await c.start() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        c.stop()
        await t.value
        XCTAssertEqual(c.run?.phase, .cancelled)
        XCTAssertEqual(c.run?.steps.map(\.status), [.cancelled, .cancelled, .cancelled])
    }
    func testLoadTurnsRunningIntoInterruptedAndContinueRerunsOnlyThose() async {
        let log = Log()
        var persisted = run([step("a"), step("b", ["a"])])
        persisted.phase = .running
        persisted.steps[0].status = .done; persisted.steps[0].draft = draft("a")
        persisted.steps[1].status = .running
        let c = coordinator(log: log)
        c.load(persisted)
        XCTAssertEqual(c.run?.state("b")?.status, .interrupted)
        await c.continueInterrupted()
        let started = await log.started
        XCTAssertEqual(started, ["b"], "done steps are never re-run")
        XCTAssertEqual(c.run?.phase, .ready)
    }
    func testInterruptedBuildReassembles() async {
        var persisted = run([step("a")])
        persisted.phase = .assembling
        persisted.steps[0].status = .done; persisted.steps[0].draft = draft("a")
        persisted.steps[1].status = .running
        var assembled = 0
        let c = TeamRunCoordinator(runStep: { _, _ in .failure("must not run") },
                                   assemble: { _, _ in assembled += 1; return .success(path: "/p-2") }, save: { _ in })
        c.load(persisted)
        await c.continueInterrupted()
        XCTAssertEqual(assembled, 1)
        XCTAssertEqual(c.run?.projectPath, "/p-2")
    }
    func testSavesOnEveryTransition() async {
        var saves = 0
        let c = coordinator(log: Log(), saves: { saves += 1 })
        c.load(run([step("a")]))
        await c.start()
        // start, a running, a done, build running, build done/ready — at least 5.
        XCTAssertGreaterThanOrEqual(saves, 5)
    }

    // MARK: - Review round 1 fixes

    /// Fix 1: `commit` used to fire an independent `Task { await save(snapshot) }` per call.
    /// If a real saver suspends (Firestore write), an earlier snapshot's save can finish AFTER
    /// a later one's, so the stale snapshot wins and overwrites the fresher state on disk — on
    /// relaunch that either re-runs finished work or leaves a finished run looking active and
    /// blocking "one active TeamRun per company". Reproduces by making the FIRST save sleep much
    /// longer than the rest: without serialization the first (stalest) snapshot's write lands
    /// last; with it, every save is forced to wait for the one before it, so writes always land
    /// in commit order no matter how long any individual save takes.
    func testSavesAreSerializedSoStaleSnapshotCannotWinRace() async {
        actor Recorder {
            private(set) var lastWritten: TeamRunPhase?
            func write(_ phase: TeamRunPhase) { lastWritten = phase }
        }
        let recorder = Recorder()
        var callCount = 0
        let c = TeamRunCoordinator(
            runStep: { step, _ in .success(self.draft(step.id)) },
            assemble: { _, _ in .success(path: "/tmp/p") },
            save: { r in
                callCount += 1
                let nanos: UInt64 = callCount == 1 ? 60_000_000 : 1_000_000
                try? await Task.sleep(nanoseconds: nanos)
                await recorder.write(r.phase)
            })
        c.load(run([step("a")]))
        await c.start()
        try? await Task.sleep(nanoseconds: 200_000_000)
        let last = await recorder.lastWritten
        XCTAssertEqual(last, c.run?.phase,
                        "the last write to land must be the final state, not an earlier stale snapshot")
    }

    /// Fix 2a: `continueInterrupted` had no phase guard, so calling it on a run with nothing
    /// `.interrupted` (`.ready`, `.filed`, `.cancelled`, ...) unconditionally set `.running`.
    /// Nothing is runnable in that state, so the old `settlePhase` (which only ever moved to
    /// `.failed`, never on an all-`.done` board) left it stuck at `.running` and saved it —
    /// silently reopening a finished run.
    func testContinueInterruptedIsANoOpWithoutInterruptedSteps() async {
        let c = coordinator(log: Log())
        c.load(run([step("a")]))
        await c.start()
        XCTAssertEqual(c.run?.phase, .ready)
        await c.continueInterrupted()
        XCTAssertEqual(c.run?.phase, .ready, "continueInterrupted must not touch a run with nothing interrupted")
    }

    /// Fix 2b: a crash mid-run can leave one step `.failed` and a sibling `.running`. `load`
    /// turns the sibling `.interrupted`. Retrying the failed step succeeds, but `retry` only
    /// unblocks `.blocked` steps, never `.interrupted` ones, and `propagateBlocks` doesn't treat
    /// `.interrupted` as dead either — so the build step (which depends on both) is left
    /// `.waiting` forever with nothing in flight and nothing runnable. Without a terminal
    /// fallback in `settlePhase`, the phase stays `.running` forever with no way for the founder
    /// to act on it.
    func testStuckInterruptedStepSettlesRunToFailedNotForeverRunning() async {
        let log = Log()
        var persisted = run([step("a"), step("b")])
        persisted.phase = .running
        persisted.steps[0].status = .failed("boom")
        persisted.steps[1].status = .running
        let c = coordinator(log: log)
        c.load(persisted)
        XCTAssertEqual(c.run?.state("b")?.status, .interrupted)
        await c.retry(stepId: "a")
        XCTAssertEqual(c.run?.state("a")?.status, .done)
        XCTAssertEqual(c.run?.state("b")?.status, .interrupted, "an interrupted step is never silently re-run by retry")
        XCTAssertEqual(c.run?.phase, .failed, "nothing in flight, nothing runnable, build not done — must not stay .running forever")
    }
}

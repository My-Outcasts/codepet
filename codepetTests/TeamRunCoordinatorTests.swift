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
}

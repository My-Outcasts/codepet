// codepet/Managers/TeamRunCoordinator.swift
import Foundation
import Combine

enum TeamStepResult { case success(Deliverable), failure(String) }
enum TeamAssemblyResult { case success(path: String), failure(String) }

/// Schedules a Team Build: department steps in dependency order (≤3 at once), each fed its
/// DIRECT dependencies' drafts, then the build step through the assembler. Every dependency is
/// injected, so the whole state machine is testable without Claude, Firestore or a disk.
@MainActor
final class TeamRunCoordinator: ObservableObject {
    typealias StepRunner = (WorkStep, [UpstreamWork]) async -> TeamStepResult
    typealias Assembler = (TeamRun, @escaping (String) -> Void) async -> TeamAssemblyResult
    typealias Saver = (TeamRun) async -> Void

    static let maxConcurrent = 3

    @Published private(set) var run: TeamRun?
    @Published private(set) var buildLog: [String] = []

    private let runStep: StepRunner
    private let assemble: Assembler
    private let save: Saver
    private let now: () -> Date
    private var inFlight: [String: Task<Void, Never>] = [:]
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(runStep: @escaping StepRunner, assemble: @escaping Assembler, save: @escaping Saver,
         now: @escaping () -> Date = Date.init) {
        self.runStep = runStep; self.assemble = assemble; self.save = save; self.now = now
    }

    func load(_ run: TeamRun) {
        var r = run
        for i in r.steps.indices where r.steps[i].status == .running { r.steps[i].status = .interrupted }
        self.run = r
    }

    func start() async {
        guard var r = run, r.phase == .planned else { return }
        r.phase = .running
        commit(r)
        await pumpUntilSettled()
    }

    func retry(stepId: String) async {
        guard var r = run, let i = r.steps.firstIndex(where: { $0.stepId == stepId }),
              case .failed = r.steps[i].status else { return }
        r.steps[i].status = .waiting
        for j in r.steps.indices where r.steps[j].status == .blocked { r.steps[j].status = .waiting }
        r.phase = .running
        commit(r)
        await pumpUntilSettled()
    }

    func continueInterrupted() async {
        guard var r = run else { return }
        for i in r.steps.indices where r.steps[i].status == .interrupted { r.steps[i].status = .waiting }
        r.phase = .running
        commit(r)
        await pumpUntilSettled()
    }

    func stop() {
        guard var r = run else { return }
        inFlight.values.forEach { $0.cancel() }
        inFlight = [:]
        for i in r.steps.indices where r.steps[i].status != .done { r.steps[i].status = .cancelled }
        r.phase = .cancelled
        commit(r)
        resumeWaiters()
    }

    func markFiled() {
        guard var r = run, r.phase == .ready else { return }
        r.phase = .filed
        commit(r)
    }

    // MARK: - Scheduling

    private func pumpUntilSettled() async {
        schedule()
        if isSettled { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private var isSettled: Bool {
        guard let r = run else { return true }
        return inFlight.isEmpty && !r.steps.contains { $0.status == .waiting && depsDone($0.stepId, in: r) }
    }

    private func depsDone(_ stepId: String, in r: TeamRun) -> Bool {
        guard let step = r.plan.steps.first(where: { $0.id == stepId }) else { return false }
        return step.dependsOn.allSatisfy { r.state($0)?.status == .done }
    }

    private func schedule() {
        guard var r = run, r.phase == .running || r.phase == .assembling else { resumeIfSettled(); return }
        propagateBlocks(&r)
        var slots = Self.maxConcurrent - inFlight.count
        for step in r.plan.steps where slots > 0 {
            guard r.state(step.id)?.status == .waiting, depsDone(step.id, in: r) else { continue }
            let i = r.steps.firstIndex { $0.stepId == step.id }!
            r.steps[i].status = .running
            r.steps[i].startedAt = now()
            slots -= 1
            if step.id == WorkPlan.buildStepId {
                r.phase = .assembling
                launchAssembly(r)
            } else {
                launchStep(step, upstream: upstream(for: step, in: r))
            }
        }
        settlePhase(&r)
        commit(r)
        resumeIfSettled()
    }

    private func launchStep(_ step: WorkStep, upstream: [UpstreamWork]) {
        inFlight[step.id] = Task { [weak self] in
            guard let self else { return }
            let result = await self.runStep(step, upstream)
            guard !Task.isCancelled else { return }
            self.finish(step.id, result: result)
        }
    }

    private func launchAssembly(_ snapshot: TeamRun) {
        buildLog = []
        inFlight[WorkPlan.buildStepId] = Task { [weak self] in
            guard let self else { return }
            let result = await self.assemble(snapshot) { [weak self] line in self?.buildLog.append(line) }
            guard !Task.isCancelled else { return }
            self.finishAssembly(result)
        }
    }

    private func finish(_ stepId: String, result: TeamStepResult) {
        inFlight[stepId] = nil
        guard var r = run, let i = r.steps.firstIndex(where: { $0.stepId == stepId }) else { return }
        r.steps[i].finishedAt = now()
        switch result {
        case .success(let d): r.steps[i].status = .done; r.steps[i].draft = d
        case .failure(let why): r.steps[i].status = .failed(why)
        }
        commit(r)
        schedule()
    }

    private func finishAssembly(_ result: TeamAssemblyResult) {
        inFlight[WorkPlan.buildStepId] = nil
        guard var r = run, let i = r.steps.firstIndex(where: { $0.stepId == WorkPlan.buildStepId }) else { return }
        r.steps[i].finishedAt = now()
        switch result {
        case .success(let path): r.steps[i].status = .done; r.projectPath = path; r.phase = .ready
        case .failure(let why): r.steps[i].status = .failed(why); r.phase = .failed
        }
        commit(r)
        resumeIfSettled()
    }

    /// Direct dependencies only: a dependency's draft already absorbed its own upstream, which is
    /// what makes the chain multi-level without re-sending the whole history.
    private func upstream(for step: WorkStep, in r: TeamRun) -> [UpstreamWork] {
        step.dependsOn.prefix(UpstreamWork.cap).compactMap { depId in
            guard let dep = r.plan.steps.first(where: { $0.id == depId }),
                  let d = r.state(depId)?.draft else { return nil }
            return UpstreamWork.fromDraft(d, task: dep.asRoadmapTask(), unapproved: true)
        }
    }

    private func propagateBlocks(_ r: inout TeamRun) {
        var changed = true
        while changed {
            changed = false
            for step in r.plan.steps {
                guard let i = r.steps.firstIndex(where: { $0.stepId == step.id }), r.steps[i].status == .waiting else { continue }
                let deadDep = step.dependsOn.contains { dep in
                    switch r.state(dep)?.status { case .failed, .blocked, .cancelled: return true; default: return false }
                }
                if deadDep { r.steps[i].status = .blocked; changed = true }
            }
        }
    }

    private func settlePhase(_ r: inout TeamRun) {
        guard inFlight.isEmpty, r.phase == .running || r.phase == .assembling else { return }
        let anyRunnable = r.steps.contains { $0.status == .waiting && depsDone($0.stepId, in: r) }
        if anyRunnable { return }
        if r.steps.contains(where: { if case .failed = $0.status { return true }; return $0.status == .blocked }) {
            r.phase = .failed
        }
    }

    private func commit(_ r: TeamRun) {
        run = r
        let snapshot = r
        Task { await save(snapshot) }
    }

    private func resumeIfSettled() { if isSettled { resumeWaiters() } }
    private func resumeWaiters() { let w = waiters; waiters = []; w.forEach { $0.resume() } }
}

import Foundation
import Combine

/// The state one engineering run is in, and the only place frames are folded
/// into it.
///
/// Testable through an INJECTED `EngineeringRunning`, the way `CompanyStore` is
/// testable through its injected closures. Never construct an
/// `EngineeringClient` in here: the XCTest host on Xcode 26.2 crashes when a
/// `@MainActor ObservableObject` deallocates, and a store that reaches for the
/// network is a store no suite can drive.
@MainActor
final class EngineeringRunStore: ObservableObject {

    @Published private(set) var phase: EngineeringPhase = .preparing
    @Published private(set) var steps: [ExecStep] = []
    /// Outstanding permission asks, oldest first. Usually one; the relay can
    /// send several when the agent batches tool calls in a single turn.
    @Published private(set) var approvals: [EngApproval] = []
    /// The agent's prose, in order. Separate from `steps` because one is what
    /// it DID and the other is what it says about it.
    @Published private(set) var messages: [String] = []
    @Published private(set) var diff: EngDiffSummary?
    @Published private(set) var runId: String?
    /// A refusal the founder has to act on, or nil. Not a phase: a run can be
    /// perfectly healthy while a diff fetch fails.
    @Published private(set) var failure: EngineeringError?

    private let runner: EngineeringRunning
    /// tool_use_ids already answered. The relay replays history on reconnect,
    /// so an ask can arrive again after it was dealt with — and a card that
    /// reappears once answered reads as the agent asking twice.
    private var answered: Set<String> = []

    /// What to do again, captured at the moment a failure was recorded.
    ///
    /// A retry control is only honest if it repeats the thing that actually
    /// failed. `start`, answering a permission card, and fetching a diff are
    /// three different retries — one shared "try again" that always re-runs
    /// the ask would re-spend a founder's credits to fix a diff that merely
    /// failed to load, on work that already succeeded.
    private var retryAction: (() async -> Void)?

    /// Whether to draw a retry control: there has to be something to repeat
    /// AND repeating it has to be capable of a different answer.
    var canRetry: Bool { failure?.isRetryable == true && retryAction != nil }

    init(runner: EngineeringRunning) {
        self.runner = runner
    }

    // MARK: - driving a run

    func start(ask: String) async {
        phase = .preparing
        failure = nil
        retryAction = nil
        do {
            runId = try await runner.start(ask: ask) { [weak self] frame in
                Task { @MainActor in self?.handle(frame) }
            }
            if case .preparing = phase { phase = .running }
        } catch let error as EngineeringError {
            record(error, phase: .failed(String(describing: error))) { [weak self] in
                await self?.start(ask: ask)
            }
        } catch {
            record(.unknown(0), phase: .failed("unknown")) { [weak self] in
                await self?.start(ask: ask)
            }
        }
    }

    func answer(toolUseId: String, allow: Bool, reason: String? = nil) async {
        // Remove the card FIRST. The turn is a round trip, and leaving a live
        // button under the founder's cursor invites a second tap that sends a
        // second confirmation for one tool_use_id.
        approvals.removeAll { $0.id == toolUseId }
        answered.insert(toolUseId)
        if approvals.isEmpty { phase = .running }
        guard let runId else { return }
        let turn: EngineeringTurn = allow
            ? .approve(toolUseId: toolUseId)
            : .deny(toolUseId: toolUseId, reason: reason)
        do {
            try await runner.send(runId: runId, turn: turn)
        } catch let error as EngineeringError {
            // This used to be `try?`. A run paused at its budget answers this
            // call with 409 `budget_reached`, so the swallow meant the card
            // vanished, the run sat paused, and NOTHING said why — the founder
            // is left watching a spinner that will never move.
            record(error, phase: phase(after: error)) { [weak self] in
                await self?.answer(toolUseId: toolUseId, allow: allow, reason: reason)
            }
        } catch {
            record(.unknown(0), phase: phase) { [weak self] in
                await self?.answer(toolUseId: toolUseId, allow: allow, reason: reason)
            }
        }
    }

    func loadDiff(scope: ReviewScope) async {
        guard let runId else { return }
        do {
            diff = try await runner.diff(runId: runId, scope: scope)
            // A retry that succeeded has nothing left to repeat, and a stale
            // failure under a diff that loaded reads as a diff you cannot trust.
            failure = nil
            retryAction = nil
        } catch let error as EngineeringError {
            // A diff that will not load does NOT make the run failed — the
            // work happened and the branch exists. Saying otherwise would send
            // a founder off to re-run something that already succeeded. So the
            // phase is left alone and only the retry is offered.
            record(error, phase: phase) { [weak self] in
                await self?.loadDiff(scope: scope)
            }
        } catch {
            record(.unknown(0), phase: phase) { [weak self] in
                await self?.loadDiff(scope: scope)
            }
        }
    }

    /// One place a failure, its phase, and the way to repeat it are recorded
    /// together — so a surface can never show a retry control wired to a
    /// different operation than the message above it describes.
    private func record(
        _ error: EngineeringError,
        phase newPhase: EngineeringPhase,
        retry: @escaping () async -> Void
    ) {
        failure = error
        phase = newPhase
        retryAction = retry
    }

    /// A paused run is paused, not failed. Every other refusal leaves the
    /// phase where it was, because the run itself is unharmed by a turn that
    /// did not land.
    private func phase(after error: EngineeringError) -> EngineeringPhase {
        if case .budgetReached = error { return .budgetReached }
        return phase
    }

    func retry() async {
        guard let action = retryAction else { return }
        // Cleared BEFORE the await, for the same reason `answer` removes the
        // approval card first: a live button through a round trip invites a
        // second tap, and two retries of one start are two runs and two bills.
        retryAction = nil
        failure = nil
        await action()
    }

    // MARK: - folding frames

    func handle(_ frame: EngineeringFrame) {
        switch frame {
        case .step(let step):
            apply(step)
        case .message(let text):
            messages.append(text)
        case .approval(let approval):
            // Two reasons to ignore one: it is already on screen, or it was
            // already answered and the relay is replaying history.
            guard !answered.contains(approval.id),
                  !approvals.contains(where: { $0.id == approval.id })
            else { return }
            approvals.append(approval)
            phase = .awaitingApproval
        case .done(let stopReason):
            phase = EngineeringRun.phase(fromStopReason: stopReason)
        case .failure(let code):
            failure = .unavailable
            phase = .failed(code)
        }
    }

    /// A step either starts a row or completes one that already exists.
    ///
    /// `engEvents.ts` sends `{ id, label: "", done: true }` to finish a step it
    /// announced earlier. Appending that as its own row would leave the
    /// original spinning forever AND add a blank line under it, so the label
    /// from the announcement is kept and only `done` moves.
    private func apply(_ step: ExecStep) {
        guard let index = steps.firstIndex(where: { $0.id == step.id }) else {
            steps.append(step)
            return
        }
        // `ExecStep.label` is `let`, so this replaces rather than mutates. The
        // announcement's label is kept when the marker carries none — that is
        // the whole point of the marker shape.
        let existing = steps[index]
        steps[index] = ExecStep(
            id: existing.id,
            label: step.label.isEmpty ? existing.label : step.label,
            done: step.done,
            kind: existing.kind
        )
    }
}

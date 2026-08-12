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

    init(runner: EngineeringRunning) {
        self.runner = runner
    }

    // MARK: - driving a run

    func start(ask: String) async {
        phase = .preparing
        failure = nil
        do {
            runId = try await runner.start(ask: ask) { [weak self] frame in
                Task { @MainActor in self?.handle(frame) }
            }
            if case .preparing = phase { phase = .running }
        } catch let error as EngineeringError {
            failure = error
            phase = .failed(String(describing: error))
        } catch {
            failure = .unknown(0)
            phase = .failed("unknown")
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
        try? await runner.send(runId: runId, turn: turn)
    }

    func loadDiff(scope: ReviewScope) async {
        guard let runId else { return }
        do {
            diff = try await runner.diff(runId: runId, scope: scope)
        } catch let error as EngineeringError {
            // A diff that will not load does NOT make the run failed — the
            // work happened and the branch exists. Saying otherwise would send
            // a founder off to re-run something that already succeeded.
            failure = error
        } catch {
            failure = .unknown(0)
        }
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

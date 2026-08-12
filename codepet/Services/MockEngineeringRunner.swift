import Foundation

/// A scripted engineering run, with no network and no credits.
///
/// Not only a test fixture. `MockCodeRunner` plays the same role for the local
/// runner, and with the Anthropic account out of credits this is the only way
/// to see Engineering mode at all — every view in Plan 3 is reviewable through
/// it, and the `#Preview` gallery drives it.
///
/// The script is deliberately the SHAPE a real run has rather than a happy
/// path: the agent narrates, calls a tool, then stops and waits for permission
/// — because that pause is what every real run does under `bash: always_ask`,
/// and a mock that skipped it would let a UI ship that never handles the state
/// a founder spends most of their time in.
@MainActor
final class MockEngineeringRunner: EngineeringRunning {

    /// What the run does after the founder answers.
    enum Ending {
        case finishes
        case pausesAgain
        case failsAtBudget
    }

    private let ending: Ending
    private let stepDelay: Duration
    private var onFrame: ((EngineeringFrame) -> Void)?
    private var pendingApproval: String?

    /// Every turn the caller sent, in order — the oracle a test asserts on.
    private(set) var sent: [EngineeringTurn] = []
    private(set) var diffRequests: [ReviewScope] = []

    /// `stepDelay: .zero` in tests, so a suite does not wait on a dramatisation.
    init(ending: Ending = .finishes, stepDelay: Duration = .zero) {
        self.ending = ending
        self.stepDelay = stepDelay
    }

    func start(ask: String, onFrame: @escaping (EngineeringFrame) -> Void) async throws -> String {
        self.onFrame = onFrame
        Task { await self.playOpening(ask: ask) }
        return "run_mock_1"
    }

    func attach(runId: String, onFrame: @escaping (EngineeringFrame) -> Void) async throws {
        // A real reattach replays history, so the caller must already tolerate
        // frames it has seen. Replaying here is what proves it does.
        self.onFrame = onFrame
        Task { await self.playOpening(ask: "add stripe checkout") }
    }

    func send(runId: String, turn: EngineeringTurn) async throws {
        sent.append(turn)
        switch turn {
        case .approve(let id) where id == pendingApproval:
            pendingApproval = nil
            Task { await self.playAfterApproval() }
        case .deny(let id, _) where id == pendingApproval:
            pendingApproval = nil
            emit(.message("Understood — I'll find another way."))
            emit(.done(stopReason: "end_turn"))
        case .interrupt:
            emit(.done(stopReason: "interrupted"))
        case .text:
            Task { await self.playAfterApproval() }
        default:
            // An answer to a tool_use_id that is not pending. A real backend
            // accepts it and nothing happens; silence here matches that rather
            // than inventing a response the client would never see.
            break
        }
    }

    func diff(runId: String, scope: ReviewScope) async throws -> EngDiffSummary {
        diffRequests.append(scope)
        return EngDiffSummary(
            files: [
                EngFileDiff(file: "api/billing.ts", path: "api/billing.ts", additions: 62,
                            deletions: 0, status: "added",
                            patch: "@@ -0,0 +1,3 @@\n+import Stripe from 'stripe'\n+const sk = process.env.STRIPE_KEY\n+"),
                EngFileDiff(file: "web/Checkout.tsx", path: "web/Checkout.tsx", additions: 21,
                            deletions: 14, status: "modified",
                            patch: "@@ -10,3 +10,4 @@\n-const total = 0\n+const total = cart.sum()\n"),
                // A binary file, because the pane must render one as a row with
                // counts rather than an empty body that reads like a bug.
                EngFileDiff(file: "public/logo.png", path: "public/logo.png", additions: 0,
                            deletions: 0, status: "modified", patch: nil)
            ],
            additions: 83,
            deletions: 14,
            truncated: false,
            // `turn` is asked for and `branch` comes back, with the flag set —
            // exactly what engDiff does until lastTurnBaseSha is written.
            scope: scope == .turn ? .branch : scope,
            scopeFellBack: scope == .turn
        )
    }

    // MARK: - the script

    private func playOpening(ask: String) async {
        emit(.step(ExecStep(id: "s1", label: "read the repository", done: false, kind: .mono)))
        await pause()
        emit(.step(ExecStep(id: "s1", label: "", done: true, kind: .mono)))
        emit(.message("I'll start by looking at how this project runs its tests."))
        await pause()
        pendingApproval = "tu_1"
        emit(.approval(EngApproval(id: "tu_1", name: "bash", input: "npm install stripe")))
    }

    private func playAfterApproval() async {
        emit(.step(ExecStep(id: "s2", label: "npm install stripe", done: false, kind: .mono)))
        await pause()
        emit(.step(ExecStep(id: "s2", label: "", done: true, kind: .mono)))
        switch ending {
        case .finishes:
            emit(.message("Added Stripe checkout across three files. Tests pass."))
            emit(.done(stopReason: "end_turn"))
        case .pausesAgain:
            pendingApproval = "tu_2"
            emit(.approval(EngApproval(id: "tu_2", name: "bash", input: "npm test")))
        case .failsAtBudget:
            emit(.done(stopReason: "budget_reached"))
        }
    }

    private func pause() async {
        guard stepDelay > .zero else { return }
        try? await Task.sleep(for: stepDelay)
    }

    private func emit(_ frame: EngineeringFrame) {
        onFrame?(frame)
    }
}

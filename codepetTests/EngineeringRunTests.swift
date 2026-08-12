// codepetTests/EngineeringRunTests.swift
import XCTest
@testable import codepet

/// The Swift half of a contract whose other half is in TypeScript.
///
/// `engClient.ts`'s `RunStatus` and the Managed Agents stop reasons are what
/// the backend can send; the mappings here are what the card renders. Nothing
/// but these tests connects the two, so every value the backend can produce is
/// pinned by name — a case added there and missed here degrades silently to
/// `.failed`, which looks like a bug in the agent rather than a gap in this
/// file.
final class EngineeringRunTests: XCTestCase {

    // MARK: - stop reasons (the live stream's vocabulary)

    func testEndTurnMeansThereIsADiffToRead() {
        XCTAssertEqual(EngineeringRun.phase(fromStopReason: "end_turn"), .reviewing)
    }

    func testBudgetReachedIsItsOwnPhaseAndNotAFailure() {
        // The session is paused and resumable — raising the cap continues the
        // work in place. Calling it failed makes a founder start over and pay
        // for the same work twice.
        XCTAssertEqual(EngineeringRun.phase(fromStopReason: "budget_reached"), .budgetReached)
    }

    func testRequiresActionMeansTheFounderIsTheBlocker() {
        XCTAssertEqual(EngineeringRun.phase(fromStopReason: "requires_action"), .awaitingApproval)
    }

    func testAnUnknownStopReasonFailsRatherThanInvitingReview() {
        // Mirrors engWebhook.statusFor. If Anthropic adds a stop reason nobody
        // has handled, "we do not know this finished" is the honest read — not
        // a card offering to ship a diff nothing verified.
        guard case .failed = EngineeringRun.phase(fromStopReason: "something_new") else {
            return XCTFail("an unhandled stop reason must not map to a reviewable phase")
        }
        guard case .failed = EngineeringRun.phase(fromStopReason: nil) else {
            return XCTFail("a missing stop reason must not map to a reviewable phase")
        }
    }

    // MARK: - run statuses (the run document's vocabulary)

    func testEveryBackendRunStatusMapsToSomethingOtherThanUnknown() {
        // The exact string set in engClient.ts's RunStatus union. If that union
        // gains a member and this list is not updated, the new state renders as
        // a failure in the app while the backend considers the run healthy.
        let statuses = ["starting", "running", "reviewing", "budgetReached", "failed"]
        for status in statuses {
            let phase = EngineeringRun.phase(fromStatus: status)
            if case .failed(let reason) = phase, reason == "unknown_status" {
                XCTFail("RunStatus '\(status)' is unmapped — it will render as a failure")
            }
        }
    }

    func testStartingIsPreparingNotRunning() {
        // A run whose session does not exist yet has produced nothing. Showing
        // it as running invites the founder to wait for output that cannot come.
        XCTAssertEqual(EngineeringRun.phase(fromStatus: "starting"), .preparing)
    }

    func testAnUnknownStatusFails() {
        guard case .failed = EngineeringRun.phase(fromStatus: "brand_new") else {
            return XCTFail("an unmapped status must not render as healthy")
        }
    }

    // MARK: - diff identity

    func testFileDiffIdentityIsTheFileNotTheDisplayLabel() {
        // A rename's `path` is "old → new" and changes between turns; `file` is
        // stable. Keying a list on `path` animates a rename as a delete plus an
        // insert, and breaks any fetch that uses the id.
        let renamed = EngFileDiff(file: "b.ts", path: "a.ts → b.ts", additions: 1,
                                  deletions: 0, status: "renamed", patch: nil)
        XCTAssertEqual(renamed.id, "b.ts")
    }

    func testABinaryFileIsMarkedRatherThanDropped() {
        // "We changed your logo" is information even when the bytes cannot be
        // shown. An empty body with no explanation reads as a bug.
        let binary = EngFileDiff(file: "logo.png", path: "logo.png", additions: 0,
                                 deletions: 0, status: "modified", patch: nil)
        XCTAssertTrue(binary.isBinary)
    }

    func testATextFileIsNotMarkedBinary() {
        let text = EngFileDiff(file: "a.ts", path: "a.ts", additions: 1,
                               deletions: 0, status: "modified", patch: "@@ -1 +1 @@")
        XCTAssertFalse(text.isBinary)
    }

    // MARK: - review scope

    func testReviewScopeOffersOnlyWhatTheEndpointCanHonour() {
        // `commit` is in the design's selector but engDiff cannot serve it — it
        // needs a commit id the endpoint is never given. A case here would put
        // a control in the UI that lies about what it does.
        XCTAssertEqual(ReviewScope.allCases, [.branch, .turn])
    }

    func testScopeRawValuesMatchTheQueryStringTheEndpointParses() {
        // Sent verbatim as ?scope=; a mismatch silently falls back to branch.
        XCTAssertEqual(ReviewScope.branch.rawValue, "branch")
        XCTAssertEqual(ReviewScope.turn.rawValue, "turn")
    }

    // MARK: - diff summary

    func testAnEmptySummaryClaimsNeitherTruncationNorFallback() {
        // The placeholder a pane renders before its first load must not assert
        // either honesty flag — both mean something specific happened.
        XCTAssertFalse(EngDiffSummary.empty.truncated)
        XCTAssertFalse(EngDiffSummary.empty.scopeFellBack)
        XCTAssertTrue(EngDiffSummary.empty.files.isEmpty)
    }

    func testASummaryDecodesFromWhatEngDiffActuallyReturns() throws {
        // The wire shape, verbatim from engDiff's response — including the two
        // flags a hand-written fixture is most likely to omit.
        let json = """
        {"files":[{"file":"a.ts","path":"a.ts","additions":3,"deletions":1,
        "status":"modified","patch":"@@"}],"additions":3,"deletions":1,
        "truncated":true,"scope":"turn","scopeFellBack":true}
        """.data(using: .utf8)!
        let summary = try JSONDecoder().decode(EngDiffSummary.self, from: json)
        XCTAssertEqual(summary.files.count, 1)
        XCTAssertEqual(summary.scope, .turn)
        XCTAssertTrue(summary.truncated)
        XCTAssertTrue(summary.scopeFellBack)
    }
}

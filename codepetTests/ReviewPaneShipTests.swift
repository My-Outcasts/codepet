// codepetTests/ReviewPaneShipTests.swift
import XCTest
@testable import codepet

/// Shipping and the preview chip: what the pane may claim, and what it must
/// refuse to claim.
///
/// The plan sketches these as properties on the pane (`pane.showsPreviewChip`).
/// They are static functions instead, for the reason the whole engineering
/// suite keeps running into: a `View`'s stored state is not reachable from
/// XCTest, and a chip rendered inside a body is pixels. Asserted as pure
/// values, deleting the rule turns a test red; asserted through a render, it
/// would not.
final class ReviewPanePreviewTests: XCTestCase {

    func test_noPreviewChipWhenThereIsNoDeployTarget() {
        // A dead chip is worse than no chip. The spec: a repo with no deploy
        // target "degrades honestly to diff + PR".
        XCTAssertFalse(ReviewPane.showsPreviewChip(.noDeployTarget))
        XCTAssertNotNil(ReviewPane.previewNote(.noDeployTarget, lang: .en),
                        "no chip AND no explanation is just a missing feature")
    }

    func test_theNoDeployTargetNoteSaysItIsNeverComingAndThatNothingIsBroken() {
        let en = ReviewPane.previewNote(.noDeployTarget, lang: .en)?.lowercased() ?? ""
        XCTAssertTrue(en.contains("won't") || en.contains("no preview"),
                      "leaves the founder waiting for a preview that is never coming: \(en)")
        XCTAssertTrue(en.contains("diff") || en.contains("pr") || en.contains("pull"),
                      "does not say the actual deliverable is unaffected: \(en)")
    }

    func test_pendingIsNotTheSameNoAsNoDeployTarget() {
        // One means wait, the other means it will never happen. A single
        // "no preview" would send a founder to check back on nothing — which
        // is why `engPreview` makes a second GitHub call to tell them apart.
        XCTAssertFalse(ReviewPane.showsPreviewChip(.pending))
        XCTAssertNotEqual(ReviewPane.previewNote(.pending, lang: .en),
                          ReviewPane.previewNote(.noDeployTarget, lang: .en))
    }

    func test_aReadyPreviewGetsTheChipAndNoExplanation() {
        let state = EngPreviewState.ready(url: "https://codepet-abc.vercel.app")
        XCTAssertTrue(ReviewPane.showsPreviewChip(state))
        XCTAssertNil(ReviewPane.previewNote(state, lang: .en), "the chip already says it")
    }

    func test_anUnaskedPreviewClaimsNothingEitherWay() {
        // nil is "we have not looked". Rendering a note for it would invent a
        // state the backend never reported.
        XCTAssertFalse(ReviewPane.showsPreviewChip(nil))
        XCTAssertNil(ReviewPane.previewNote(nil, lang: .en))
    }

    func test_everyPreviewNoteHasBothLanguages() {
        for state: EngPreviewState in [.pending, .noDeployTarget] {
            let en = ReviewPane.previewNote(state, lang: .en)
            let vi = ReviewPane.previewNote(state, lang: .vi)
            XCTAssertNotNil(en); XCTAssertNotNil(vi)
            XCTAssertNotEqual(en, vi, "\(state) shows English to a Vietnamese founder")
        }
    }

    func test_previewDecodingSeparatesTheTwoKindsOfNo() {
        XCTAssertEqual(EngPreviewState.decode(["url": "https://x.vercel.app"]),
                       .ready(url: "https://x.vercel.app"))
        XCTAssertEqual(EngPreviewState.decode(["reason": "no_deploy_target"]), .noDeployTarget)
        XCTAssertEqual(EngPreviewState.decode(["reason": "pending"]), .pending)
        // An unrecognised reason is `pending`, not `noDeployTarget`: telling a
        // founder a preview is coming when we are unsure costs them a refresh,
        // telling them it never will costs them the feature.
        XCTAssertEqual(EngPreviewState.decode([:]), .pending)
    }
}

/// The ship control.
@MainActor
final class ReviewPaneShipTests: XCTestCase {

    private func makeStore(_ runner: MockEngineeringRunner) async -> EngineeringRunStore {
        let store = EngineeringRunStore(runner: runner)
        _ = await store.start(ask: "add stripe checkout")
        return store
    }

    func test_shipSaysOpenPRNotMerge() {
        // "Ship this" is the label; the action is a pull request. Nothing in
        // this codebase merges anything, and a founder who reads "merged"
        // believes their default branch changed — every decision they make
        // next is built on that.
        for lang: AppLanguage in [.en, .vi] {
            let shipped = ReviewPane.shippedLabel(42, lang: lang).lowercased()
            XCTAssertFalse(shipped.contains("merge"), "the ship confirmation implies a merge: \(shipped)")
            XCTAssertFalse(shipped.contains("gộp"), "the ship confirmation implies a merge: \(shipped)")
        }
        XCTAssertTrue(ReviewPane.shippedLabel(42, lang: .en).contains("42"),
                      "the founder is not told WHICH pull request")
    }

    func test_shipDisablesWhileInFlightSoTwoTapsCannotOpenTwoPRs() {
        XCTAssertTrue(ReviewPane.isShipping(.shipping))
        XCTAssertFalse(ReviewPane.isShipping(.idle))
        XCTAssertFalse(ReviewPane.isShipping(.shipped(EngShipResult(prNumber: 1, prUrl: ""))))
        // The label changes too — a disabled button that still reads "Ship
        // this" looks broken rather than busy.
        XCTAssertNotEqual(ReviewPane.shipLabel(shipping: true, lang: .en),
                          ReviewPane.shipLabel(shipping: false, lang: .en))
    }

    func test_asecondShipWhileOneIsInFlightIsRefusedByTheStoreToo() async {
        // The disabled button is the half the founder can see. This is the
        // half that matters: two in-flight calls would race two `ship`
        // assignments, and the loser could overwrite a real PR number.
        let runner = MockEngineeringRunner()
        let store = await makeStore(runner)

        async let first: Void = store.shipRun()
        async let second: Void = store.shipRun()
        _ = await (first, second)

        XCTAssertEqual(runner.shipCalls, 1, "two taps reached the backend twice")
        if case .shipped(let result) = store.ship {
            XCTAssertEqual(result.prNumber, 42)
        } else {
            XCTFail("expected a shipped state, got \(store.ship)")
        }
    }

    func test_aFailedShipDoesNotClaimAPRExists() async {
        let runner = MockEngineeringRunner()
        let store = EngineeringRunStore(runner: runner)
        // No runId — nothing was started, so there is nothing to ship.
        await store.shipRun()
        XCTAssertEqual(store.ship, .idle, "shipped a run that does not exist")
    }

    func test_aPullRequestInTheBodyBeatsTheStatus() {
        // `engShip` answers 503 `pr_write_failed` with `prNumber` and `prUrl`
        // in the body: the PR WAS opened and only Firestore's record of it
        // failed. Reading that as a failure would offer a retry for work that
        // already happened, and the retry would ask GitHub for a pull request
        // that already exists.
        let body: [String: Any] = ["error": "pr_write_failed", "prNumber": 7,
                                   "prUrl": "https://github.com/o/r/pull/7"]
        XCTAssertEqual(EngineeringClient.shipResult(from: body),
                       EngShipResult(prNumber: 7, prUrl: "https://github.com/o/r/pull/7"))
    }

    func test_anErrorBodyWithNoPRIsNotReadAsASuccess() {
        XCTAssertNil(EngineeringClient.shipResult(from: ["error": "github_unavailable"]))
        XCTAssertNil(EngineeringClient.shipResult(from: ["prNumber": 0]))
    }

    // MARK: - the 422 this shares with the connect flow

    func test_theTwoFourTwentyTwosAreDifferentProblems() {
        // Added an hour apart and nearly folded together. `no_default_branch`
        // is a repo the founder picked that has no commits; `run_not_shippable`
        // is a run of ours that recorded no branch. Mapping the status alone
        // told a founder whose run produced nothing that their repo was empty.
        XCTAssertEqual(EngineeringError.from(status: 422, code: "no_default_branch"), .repoUnusable)
        XCTAssertEqual(EngineeringError.from(status: 422, code: "run_not_shippable"), .nothingToShip)
    }

    func test_nothingToShipIsNeverWordedAsTheFoundersFault() {
        let en = EngineeringResultBar.message(for: .nothingToShip, lang: .en).lowercased()
        XCTAssertTrue(en.contains("this run"), "does not name the run as the subject: \(en)")
        XCTAssertFalse(en.contains("your repo"), "blames the founder's repo: \(en)")
        XCTAssertNotEqual(EngineeringResultBar.message(for: .nothingToShip, lang: .vi),
                          EngineeringResultBar.message(for: .nothingToShip, lang: .en))
    }
}

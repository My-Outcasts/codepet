// codepetTests/EngineeringWorkspaceRouteTests.swift
import XCTest
@testable import codepet

/// The routing decision behind the engineering workspace, tested as a pure
/// function so none of it needs the shell, a store, or the XCTest host that
/// crashes on `@MainActor ObservableObject` dealloc.
///
/// The property that matters is not "review shows the pane" — it is that the
/// DESTINATION is never mutated. That is what makes leaving review free: there
/// is nothing to restore because nothing was navigated away from.
final class EngineeringWorkspaceRouteTests: XCTestCase {

    func testWithNoRunUnderReviewTheDestinationRenders() {
        XCTAssertEqual(ShellLayout.contentSurface(destination: .roadmap, reviewingRunId: nil),
                       .destination(.roadmap))
    }

    func testReviewTakesOverTheContentArea() {
        XCTAssertEqual(ShellLayout.contentSurface(destination: .roadmap, reviewingRunId: "run_1"),
                       .engineeringReview(runId: "run_1"))
    }

    func testTheDestinationIsCarriedThroughUnchangedSoLeavingRestoresItself() {
        // The mechanism, stated as a test: entering review does not navigate, so
        // clearing the run id returns to exactly the surface that was there
        // before — no saved-and-restored previous destination to get wrong when
        // the founder collapses the dock or switches threads mid-review.
        for destination in [AppView.roadmap, .chat, .secondBrain] {
            let before = ShellLayout.contentSurface(destination: destination, reviewingRunId: nil)
            _ = ShellLayout.contentSurface(destination: destination, reviewingRunId: "run_1")
            let after = ShellLayout.contentSurface(destination: destination, reviewingRunId: nil)
            XCTAssertEqual(before, after, "leaving review changed the surface for \(destination)")
            XCTAssertEqual(after, .destination(destination))
        }
    }

    func testReviewIsRefusedOnADestinationWithNoCopilot() {
        // Review is half of a two-pane workspace; the other half is the dock. On
        // Library or Tasks there is no transcript to sit beside, so the pane
        // would be a full-window diff viewer — and a founder who navigated to
        // Library mid-run would find their page replaced by a diff.
        for destination in [AppView.company, .tasks, .library, .environment] {
            XCTAssertEqual(ShellLayout.contentSurface(destination: destination, reviewingRunId: "run_1"),
                           .destination(destination),
                           "review must not take over \(destination), which has no dock")
        }
    }

    func testEveryDestinationThatShowsTheCopilotCanShowReview() {
        // The converse of the above, so the two rules cannot drift apart: if a
        // destination has a dock, review is available there.
        for destination in AppView.allCases where ShellLayout.showsCopilot(in: destination) {
            XCTAssertEqual(ShellLayout.contentSurface(destination: destination, reviewingRunId: "run_1"),
                           .engineeringReview(runId: "run_1"),
                           "\(destination) shows the dock but refuses review")
        }
    }

    func testAnEmptyRunIdIsNotAReview() {
        // A blank id would render a pane that can fetch nothing and say nothing.
        XCTAssertEqual(ShellLayout.contentSurface(destination: .roadmap, reviewingRunId: ""),
                       .destination(.roadmap))
    }
}

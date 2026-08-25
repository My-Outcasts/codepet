// codepetTests/InspectorTabsTests.swift
import XCTest
@testable import codepet

/// Guards on the inspector's model — spec §5, which read "Not yet drawn" until now.
final class InspectorTabsTests: XCTestCase {

    private func review(_ id: String = "r1") -> InspectorTab {
        InspectorTab(id: id, kind: .review, title: "Review")
    }

    /// **One tab per output, not per run.** Re-opening the same output brings it
    /// forward; it does not stack a second tab the founder has to tell apart. A redo
    /// over the same files is the case that would break this.
    func testReopeningAnOutputDoesNotStackASecondTab() {
        var tabs = InspectorTabs()
        tabs.open(review())
        tabs.open(review())
        XCTAssertEqual(tabs.tabs.count, 1)
        XCTAssertEqual(tabs.activeId, "r1")
    }

    /// Comparing two outputs is what the tabs are FOR (§6: "comparing their results
    /// is what the inspector's tabs are for"), so distinct outputs must coexist.
    func testDistinctOutputsCoexist() {
        var tabs = InspectorTabs()
        tabs.open(review("a"))
        tabs.open(review("b"))
        XCTAssertEqual(tabs.tabs.count, 2)
        XCTAssertEqual(tabs.activeId, "b")
    }

    /// **A code change opens on the DIFF**, not on a summary. Spec §5: an output
    /// opens on the view carrying the decision. Opening a review on a file count
    /// would ask the founder to approve something they had not been shown.
    func testACodeChangeOpensOnTheDiff() {
        XCTAssertEqual(InspectorTab.openingView(for: .review), .source)
        XCTAssertEqual(review().view, .source)
    }

    /// The link flips the SAME panel rather than opening a second tab — a diff and
    /// what the diff did are one object seen two ways.
    func testFlippingChangesTheViewAndNotTheTabCount() {
        var tabs = InspectorTabs()
        tabs.open(review())
        tabs.flip()
        XCTAssertEqual(tabs.tabs.count, 1)
        XCTAssertEqual(tabs.active?.view, .result)
        tabs.flip()
        XCTAssertEqual(tabs.active?.view, .source)
    }

    /// Closing the active tab must land somewhere real, and closing the last one must
    /// leave nothing active — the panel collapses rather than framing an empty pane.
    func testClosingFallsBackAndThenEmpties() {
        var tabs = InspectorTabs()
        tabs.open(review("a"))
        tabs.open(review("b"))
        tabs.close("b")
        XCTAssertEqual(tabs.activeId, "a")
        tabs.close("a")
        XCTAssertTrue(tabs.isEmpty)
        XCTAssertNil(tabs.activeId)
    }

    /// Activating a tab that is not open must be a no-op, not a dangling selection
    /// that renders an empty body.
    func testActivatingAnUnknownTabIsIgnored() {
        var tabs = InspectorTabs()
        tabs.open(review("a"))
        tabs.activate("nope")
        XCTAssertEqual(tabs.activeId, "a")
    }

    /// **47% of the pane, collapsing below the dock's own threshold.** Spec §5 says
    /// to reuse that rule rather than invent a second one, because two thresholds for
    /// "too narrow for a side panel" would drift and a founder would learn neither.
    func testTheInspectorGeometryReusesTheDocksThreshold() {
        XCTAssertEqual(TwoModeLayout.inspectorFraction, 0.47)
        XCTAssertEqual(TwoModeLayout.inspectorMinWindowWidth, ShellLayout.dockExpandMinWidth)
        XCTAssertTrue(TwoModeLayout.inspectorCollapsed(forWidth: 800))
        XCTAssertFalse(TwoModeLayout.inspectorCollapsed(forWidth: 1400))
    }

    /// Never so narrow that the diff wraps into uselessness.
    func testTheInspectorHasAFloor() {
        XCTAssertGreaterThanOrEqual(TwoModeLayout.inspectorWidth(forWidth: 1000), 320)
    }
}

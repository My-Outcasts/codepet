// codepetTests/TwoModeLayoutTests.swift
import XCTest
@testable import codepet

/// Layout guards for the two-mode shell. In the HTML prototype the equivalent
/// rules produced two real clipping bugs — both found by asserting geometry, not
/// by looking at it — so the Swift shell gets the same treatment from the start.
final class TwoModeLayoutTests: XCTestCase {

    /// One threshold for "too narrow for a side panel", shared with the docked
    /// copilot. Two would drift, and the founder would learn neither.
    func testInspectorReusesTheDockCollapseThreshold() {
        XCTAssertEqual(TwoModeLayout.inspectorMinWindowWidth, ShellLayout.dockExpandMinWidth)
        XCTAssertTrue(TwoModeLayout.inspectorCollapsed(forWidth: ShellLayout.dockExpandMinWidth - 1))
        XCTAssertFalse(TwoModeLayout.inspectorCollapsed(forWidth: ShellLayout.dockExpandMinWidth))
        XCTAssertFalse(TwoModeLayout.inspectorCollapsed(forWidth: 1440))
    }

    /// The inspector may take its share, but never so much that the conversation
    /// stops being a conversation.
    func testInspectorNeverSquashesTheConversation() {
        for width in stride(from: 900.0, through: 2400.0, by: 60.0) {
            let inspector = TwoModeLayout.inspectorWidth(forWidth: width)
            let conversation = width - TwoModeLayout.railWidth - inspector
            XCTAssertGreaterThanOrEqual(inspector, 320, "inspector unusable at \(width)")
            XCTAssertGreaterThan(conversation, 240, "conversation squeezed at \(width)")
        }
    }

    /// The rule the system map turns on: work surfaces in chat; the five company
    /// pages are state you browse. So a destination replaces the conversation
    /// only while you are on one.
    func testConversationShowsOnChatAndNotOnCompanyPages() {
        XCTAssertTrue(TwoModeLayout.showsConversation(for: .chat))
        for surface in WorkspaceMode.workspaceSurfaces {
            XCTAssertFalse(TwoModeLayout.showsConversation(for: surface),
                           "\(surface) is a page you browse, not the conversation")
        }
    }

    /// `+ New` makes a conversation, so it must land on the surface that shows
    /// one — otherwise the founder creates a thread they cannot see.
    func testNewChatLandsOnTheChatSurface() {
        XCTAssertEqual(TwoModeLayout.newChatDestination, .chat)
        XCTAssertTrue(TwoModeLayout.showsConversation(for: TwoModeLayout.newChatDestination))
    }

    /// The wordmark carries Overview (founder call, Aug 6) — the two-mode rail
    /// keeps that rather than inventing a sixth destination for it.
    func testWordmarkStillGoesHomeToOverview() {
        XCTAssertEqual(AppView.home, .roadmap)
        XCTAssertTrue(WorkspaceMode.workspaceSurfaces.contains(AppView.home))
    }
}

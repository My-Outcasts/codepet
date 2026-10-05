// codepetTests/ChatSwitchingTests.swift
import XCTest
@testable import codepet

/// While a reply arrives, New and thread switches are refused by the store; the controls must
/// say so. The rail's looked live and did nothing, which read as the app freezing (5 Oct, #10).
@MainActor
final class ChatSwitchingTests: XCTestCase {
    func testLockedWhileAReplyArrives() {
        XCTAssertTrue(ChatSwitching.isLocked(isStreaming: true, isCompanionTyping: false))
        XCTAssertTrue(ChatSwitching.isLocked(isStreaming: false, isCompanionTyping: true))
        XCTAssertFalse(ChatSwitching.isLocked(isStreaming: false, isCompanionTyping: false))
    }

    func testTheHintSaysWhatToWaitFor() {
        XCTAssertTrue(ChatSwitching.waitHint(.en).lowercased().contains("wait"))
        XCTAssertFalse(ChatSwitching.waitHint(.vi).isEmpty)
    }

    /// The rule the controls show is the rule the store enforces: an idle store switches.
    func testAnIdleStoreSwitches() async {
        let s = CompanyStore(loader: { _ in .empty })
        await s.hydrate(companyId: "u")
        XCTAssertFalse(ChatSwitching.isLocked(isStreaming: s.isStreaming, isCompanionTyping: s.isCompanionTyping))
        let before = s.activeThreadId
        s.newChat()
        XCTAssertNotEqual(s.activeThreadId, before)
    }
}

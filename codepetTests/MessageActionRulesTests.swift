// codepetTests/MessageActionRulesTests.swift
import XCTest
@testable import codepet

/// The guard that keeps `retryReply`'s destructive `removeSubrange(askIndex...)` honest.
/// If `isLast` is dropped from the rule these go red — which is the point: retry on an
/// older reply silently deletes every turn after it.
final class MessageActionRulesTests: XCTestCase {

    func testRetryIsAllowedOnTheLastIdleReply() {
        XCTAssertTrue(MessageActionRules.canRetry(isLast: true, isTyping: false, isStreaming: false))
    }

    func testRetryIsRefusedOnAnOlderReply() {
        XCTAssertFalse(MessageActionRules.canRetry(isLast: false, isTyping: false, isStreaming: false),
                       "retryReply drops every turn after the ask — an older reply must not offer it")
    }

    func testRetryIsRefusedWhileTyping() {
        XCTAssertFalse(MessageActionRules.canRetry(isLast: true, isTyping: true, isStreaming: false))
    }

    func testRetryIsRefusedWhileStreaming() {
        XCTAssertFalse(MessageActionRules.canRetry(isLast: true, isTyping: false, isStreaming: true))
    }

    func testRetryIsRefusedOnAnOlderReplyEvenWhenIdle() {
        XCTAssertFalse(MessageActionRules.canRetry(isLast: false, isTyping: true, isStreaming: true))
    }
}

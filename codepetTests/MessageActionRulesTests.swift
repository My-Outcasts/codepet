// codepetTests/MessageActionRulesTests.swift
import XCTest
@testable import codepet

/// The guard that keeps `retryReply`'s destructive `removeSubrange(askIndex...)` honest and
/// mirrors its three-condition entry guard (`!isCompanionTyping, !isStreaming, !isFanningOut`).
/// If any one condition is dropped from the rule, the test named for it goes red — which is
/// the point: an offered-but-refused retry is a dead click, and an older reply that's retried
/// silently deletes every turn after it.
final class MessageActionRulesTests: XCTestCase {

    func testRetryIsAllowedOnTheLastIdleReply() {
        XCTAssertTrue(MessageActionRules.canRetry(isLast: true, isTyping: false, isStreaming: false, isFanningOut: false))
    }

    func testRetryIsRefusedOnAnOlderReply() {
        XCTAssertFalse(MessageActionRules.canRetry(isLast: false, isTyping: false, isStreaming: false, isFanningOut: false),
                       "retryReply drops every turn after the ask — an older reply must not offer it")
    }

    func testRetryIsRefusedWhileTyping() {
        XCTAssertFalse(MessageActionRules.canRetry(isLast: true, isTyping: true, isStreaming: false, isFanningOut: false))
    }

    func testRetryIsRefusedWhileStreaming() {
        XCTAssertFalse(MessageActionRules.canRetry(isLast: true, isTyping: false, isStreaming: true, isFanningOut: false))
    }

    func testRetryIsRefusedWhileFanningOut() {
        XCTAssertFalse(MessageActionRules.canRetry(isLast: true, isTyping: false, isStreaming: false, isFanningOut: true),
                       "retryReply's guard also checks isFanningOut — a fan-out in flight must not offer retry")
    }
}

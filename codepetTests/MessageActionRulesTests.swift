// codepetTests/MessageActionRulesTests.swift
import XCTest
@testable import codepet

/// The guard that keeps `retryReply`'s destructive `removeSubrange(askIndex...)` honest and
/// mirrors its three-condition entry guard (`!isCompanionTyping, !isStreaming, !isFanningOut`),
/// plus the `founderAsk` gate that keeps `isLast` from being read as "answers the founder's
/// last question" when it isn't. If any one condition is dropped from the rule, the test named
/// for it goes red — which is the point: an offered-but-refused retry is a dead click, an older
/// reply that's retried silently deletes every turn after it, and a reply with no founder ask
/// that's retried deletes whatever question actually preceded it, several turns back.
final class MessageActionRulesTests: XCTestCase {

    func testRetryIsAllowedOnTheLastIdleReplyWithAFounderAsk() {
        XCTAssertTrue(MessageActionRules.canRetry(isLast: true, isTyping: false, isStreaming: false,
                                                  isFanningOut: false, founderAsk: "how should I price the beta?"))
    }

    func testRetryIsRefusedOnAnOlderReply() {
        XCTAssertFalse(MessageActionRules.canRetry(isLast: false, isTyping: false, isStreaming: false,
                                                    isFanningOut: false, founderAsk: "how should I price the beta?"),
                       "retryReply drops every turn after the ask — an older reply must not offer it")
    }

    func testRetryIsRefusedWhileTyping() {
        XCTAssertFalse(MessageActionRules.canRetry(isLast: true, isTyping: true, isStreaming: false,
                                                    isFanningOut: false, founderAsk: "how should I price the beta?"))
    }

    func testRetryIsRefusedWhileStreaming() {
        XCTAssertFalse(MessageActionRules.canRetry(isLast: true, isTyping: false, isStreaming: true,
                                                    isFanningOut: false, founderAsk: "how should I price the beta?"))
    }

    func testRetryIsRefusedWhileFanningOut() {
        XCTAssertFalse(MessageActionRules.canRetry(isLast: true, isTyping: false, isStreaming: false,
                                                    isFanningOut: true, founderAsk: "how should I price the beta?"),
                       "retryReply's guard also checks isFanningOut — a fan-out in flight must not offer retry")
    }

    /// The Critical: a Roadmap "Run" proposal (or a finished draft, or a fan-out row) lands as
    /// the newest message with no founder ask before it. `isLast` alone would offer retry there
    /// — tapping it would walk back to whatever question preceded it, maybe several turns back,
    /// delete everything from there forward, and re-ask it, spending credits the founder never
    /// asked to spend. This must refuse even though every busy flag says the store is idle.
    func testRetryIsRefusedOnALastMessageWithNoFounderAsk() {
        XCTAssertFalse(MessageActionRules.canRetry(isLast: true, isTyping: false, isStreaming: false,
                                                    isFanningOut: false, founderAsk: nil),
                       "isLast is not the same as 'answers the founder's last ask' — a store-initiated " +
                       "reply (a run proposal, a draft, a fan-out row) has no founder ask and must not offer retry")
    }

    /// A blank string is not a founder ask either — `retryReply` itself guards on
    /// `!ask.isEmpty` after trimming, so a whitespace-only `founderAsk` must refuse here too,
    /// or the rule would offer a retry the store then silently refuses (a dead click).
    func testRetryIsRefusedOnAWhitespaceOnlyFounderAsk() {
        XCTAssertFalse(MessageActionRules.canRetry(isLast: true, isTyping: false, isStreaming: false,
                                                    isFanningOut: false, founderAsk: "   "))
    }

    /// The brand-new-install case named in the finding: byte's first-run greeting is the only
    /// message in the transcript, so it is trivially `isLast` — but it was never produced by a
    /// founder ask, so retry must stay refused.
    func testRetryIsRefusedOnTheFirstRunGreeting() {
        XCTAssertFalse(MessageActionRules.canRetry(isLast: true, isTyping: false, isStreaming: false,
                                                    isFanningOut: false, founderAsk: nil))
    }
}

// codepetTests/LiveAIModeTests.swift
import XCTest
@testable import codepet

/// Guards on the Amendment 4 (6 Sep) live-mode swap: `CODEPET_LIVE_AI` keeps every prototype
/// fixture (the board, the nine-question chain, the departments) but routes the chat/task/VC
/// TRANSPORT through `LocalTransportRouter` instead of `MockChat`'s canned replies.
///
/// **What these tests assert, and what they deliberately do not.** `MockChat.usesMockTransport`
/// is the ONE predicate `CompanyChatClient.send`/`.sendStream`, `RunTaskClient.run`, and both of
/// `CompanyStore`'s `vcRunner` assignments all check — see each site's comment. Testing this
/// predicate against every flag combination is therefore equivalent to testing the transport
/// CHOICE at every one of those sites, without EXERCISING any of them: nothing here calls
/// `LocalTransportRouter`, `ChatTransportRouter`, `LocalChatStreamer`, or anything that could
/// reach a subprocess, the network, or spend a token.
final class LiveAIModeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        clearAllFlags()
    }

    override func tearDown() {
        clearAllFlags()
        super.tearDown()
    }

    private func clearAllFlags() {
        PrototypeMode.store.removeObject(forKey: PrototypeMode.key)
        for k in PrototypeMode.launchKeys { PrototypeMode.store.removeObject(forKey: k) }
        PrototypeMode.store.removeObject(forKey: "CODEPET_LIVE_AI")
    }

    // MARK: - The guard

    /// **This is the guard.** The three flags that already imply one another must keep doing
    /// exactly that and nothing more: set alone, with `CODEPET_LIVE_AI` untouched, every one of
    /// them must still yield the MOCK transport. It must go red the moment something makes one
    /// of these three ALSO imply live mode — which is precisely the accident
    /// `PrototypeMode.launchKeys`' comment says must stay impossible by default.
    func testTheThreeExistingFlagsAloneStillYieldMockTransport() {
        for key in PrototypeMode.launchKeys {
            PrototypeMode.store.set(true, forKey: key)
            defer { PrototypeMode.store.removeObject(forKey: key) }

            XCTAssertFalse(PrototypeMode.liveAI,
                           "\(key) alone must not turn live mode on")
            XCTAssertTrue(MockChat.usesMockTransport,
                         "\(key) alone must still route chat/task/VC through the mock transport")
        }
    }

    /// All three together (the shape `-CODEPET_MOCK_AUTOPLAY` actually produces, since it
    /// implies the other two) — still mock, with `CODEPET_LIVE_AI` absent.
    func testAllThreeFlagsTogetherStillYieldMockTransportWithoutTheLiveFlag() {
        for key in PrototypeMode.launchKeys { PrototypeMode.store.set(true, forKey: key) }
        XCTAssertTrue(MockChat.enabled)
        XCTAssertFalse(PrototypeMode.liveAI)
        XCTAssertTrue(MockChat.usesMockTransport)
    }

    /// Nothing set at all: prototype mode itself is off, so there is no transport question to
    /// answer either way — `usesMockTransport` reads `false` (nothing to mock), not `true`.
    func testWithPrototypeModeOffTransportIsNotMockedEither() {
        XCTAssertFalse(MockChat.enabled)
        XCTAssertFalse(MockChat.usesMockTransport)
    }

    // MARK: - The swap

    /// With `CODEPET_LIVE_AI` set on top of a prototype flag, the transport predicate flips to
    /// live — the injected transports (`CompanyChatClient`, `RunTaskClient`, `CompanyStore`'s
    /// `vcRunner`) all read this exact value, so this is "the injected transports are the live
    /// ones" without exercising any of them.
    func testLiveAIFlagOnTopOfMockChatSwapsToLiveTransport() {
        PrototypeMode.store.set(true, forKey: "CODEPET_MOCK_CHAT")
        PrototypeMode.store.set(true, forKey: "CODEPET_LIVE_AI")

        XCTAssertTrue(MockChat.enabled, "the fixture DATA must stay on")
        XCTAssertTrue(PrototypeMode.liveAI)
        XCTAssertFalse(MockChat.usesMockTransport,
                       "with the live flag set, chat/task/VC must no longer route to the mock")
    }

    /// Same, for the autoplay flag specifically — the one the walkthrough actually launches
    /// with, and the one Amendment 4 is about.
    func testLiveAIFlagOnTopOfAutoplaySwapsToLiveTransport() {
        PrototypeMode.store.set(true, forKey: "CODEPET_MOCK_AUTOPLAY")
        PrototypeMode.store.set(true, forKey: "CODEPET_LIVE_AI")

        XCTAssertTrue(MockChat.enabled)
        XCTAssertTrue(MockChat.flowEnabled, "autoplay must still start at the cold open")
        XCTAssertFalse(MockChat.usesMockTransport)
    }

    /// `CODEPET_LIVE_AI` alone, with no prototype flag, does nothing — there is no fixture
    /// company to swap a transport under, and the flag's own comment says it is "meaningless
    /// with all three off".
    func testLiveAIFlagAloneWithNoPrototypeFlagChangesNothing() {
        PrototypeMode.store.set(true, forKey: "CODEPET_LIVE_AI")

        XCTAssertFalse(MockChat.enabled)
        XCTAssertFalse(MockChat.usesMockTransport)
    }

    // MARK: - launchKeys itself stays exactly three

    /// `CODEPET_LIVE_AI` must never join `launchKeys` — that is the literal guard the amendment
    /// opens deliberately rather than by loosening this rule.
    func testLiveAIIsNotAmongTheImplyingFlags() {
        XCTAssertFalse(PrototypeMode.launchKeys.contains("CODEPET_LIVE_AI"))
        XCTAssertEqual(Set(PrototypeMode.launchKeys),
                       ["CODEPET_MOCK_CHAT", "CODEPET_MOCK_FLOW", "CODEPET_MOCK_AUTOPLAY"])
    }
}

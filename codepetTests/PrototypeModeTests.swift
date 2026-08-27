// codepetTests/PrototypeModeTests.swift
import XCTest
@testable import codepet

/// Guards on the prototype switch.
///
/// The mode existed as three launch arguments; making it a button changed what can
/// go wrong. A flag you pass deliberately at launch is hard to be confused about. A
/// switch in a menu gets flipped while signed in with a real company, mid-session,
/// by someone who then forgets which way they left it — so the two things worth
/// testing are that fixture data cannot reach a real account, and that the flag and
/// the world it implies never disagree.
final class PrototypeModeTests: XCTestCase {

    /// The three flags mean one thing, so they resolve to one switch. Two flags where
    /// one is meaningless alone is a state you can get half-right — the codebase
    /// learned that when autoplay without fixtures would have driven the live Cloud
    /// Functions unattended.
    func testTheMockFlagsAllResolveToTheOneMode() {
        XCTAssertEqual(MockChat.enabled, PrototypeMode.isOn)
        XCTAssertEqual(MockChat.flowEnabled, PrototypeMode.isOn)
    }

    /// Every launch argument that forces the mode is declared, so a new one cannot be
    /// added that the switch does not know about — which would leave the UI offering
    /// to turn off something it cannot reach.
    func testEveryForcingLaunchArgumentIsDeclared() {
        XCTAssertEqual(Set(PrototypeMode.launchKeys),
                       ["CODEPET_MOCK_CHAT", "CODEPET_MOCK_FLOW", "CODEPET_MOCK_AUTOPLAY"])
    }

    /// **A locked switch must refuse, not lie.** `NSArgumentDomain` outranks every
    /// preference file, so when a launch argument holds the mode on, writing the
    /// preference cannot turn it off. `set` returns false so the UI can say why
    /// instead of rendering a control that appears to work and does nothing.
    func testSettingIsRefusedWhileLocked() {
        guard PrototypeMode.isLocked else {
            // The normal case for a test run: no flag was passed, so the switch is live.
            XCTAssertFalse(PrototypeMode.isLocked)
            return
        }
        XCTAssertFalse(PrototypeMode.set(false))
        XCTAssertTrue(PrototypeMode.isOn, "it reported a change it could not make")
    }
}

/// The store half: flipping the flag has to bring the whole app with it.
@MainActor
final class PrototypeModeStoreTests: XCTestCase {

    /// **Nothing may stay latched.** `codingRun` was a `lazy var` and `vcRunner` was a
    /// `let`, both resolved at init. Left that way, turning the mode ON leaves the real
    /// `claude` adapter and the live `virtualCompanyRun` behind a UI insisting
    /// everything is mocked — the second of those costs ~$0.20 a convened room.
    ///
    /// The old coordinator is held in a STRONG local on purpose. Comparing
    /// `ObjectIdentifier`s across the switch does not work: dropping the reference
    /// frees the object and the replacement is handed the same address, so the
    /// identifiers match and the test reports a latched runner that was in fact
    /// rebuilt. An identifier is unique only among LIVE objects — keeping the old one
    /// alive is what makes `!==` mean what it reads as.
    func testTheRunnersAreRebuiltAndNotLatched() async throws {
        let store = CompanyStore()
        let before = store.codingRun

        guard await store.setPrototypeMode(!PrototypeMode.isOn) else {
            throw XCTSkip("a launch argument has locked the mode for this run")
        }
        XCTAssertFalse(before === store.codingRun,
                       "the coding runner survived the switch — it is still the one "
                       + "built for the other mode")

        // Leave the preference as it was found; this writes `PrototypeMode.store` (a scratch
        // suite under XCTest — see PrototypeMode.store and issue #117).
        await store.setPrototypeMode(!PrototypeMode.isOn)
    }

    /// The published mirror must track the source of truth, or the switch shows one
    /// world while the app is in the other.
    func testThePublishedFlagTracksTheMode() async throws {
        let store = CompanyStore()
        XCTAssertEqual(store.prototypeModeOn, PrototypeMode.isOn)

        let target = !PrototypeMode.isOn
        guard await store.setPrototypeMode(target) else {
            throw XCTSkip("a launch argument has locked the mode for this run")
        }
        XCTAssertEqual(store.prototypeModeOn, target)
        XCTAssertEqual(store.prototypeModeOn, PrototypeMode.isOn)

        await store.setPrototypeMode(!target)
        XCTAssertEqual(store.prototypeModeOn, !target)
    }

    /// **The reason the button is safe to ship**, and the reason this test turns the
    /// mode ON to check it.
    ///
    /// The first version asserted `allowsCloudWrites != isOn` from whatever state the
    /// test run happened to be in — which is always OFF — so it exercised one side of
    /// a two-sided rule and passed unchanged when the gate was replaced with `true`.
    /// A test that survives the deletion of the code it guards is decoration. This one
    /// enters the state it is making a claim about.
    func testCloudWritesAreRefusedWhileTheModeIsOn() async throws {
        let store = CompanyStore()
        guard await store.setPrototypeMode(true) else {
            throw XCTSkip("a launch argument has locked the mode for this run")
        }
        XCTAssertFalse(PrototypeMode.allowsCloudWrites,
                       "fixture tasks, a fixture library and a fixture brief can reach "
                       + "companies/{uid} — a demo would overwrite a real company")

        await store.setPrototypeMode(false)
        XCTAssertTrue(PrototypeMode.allowsCloudWrites,
                      "the founder's own work would stop persisting")
    }

    /// Switching worlds must not carry a conversation across. A Developer session
    /// holding a branch on a real repo has no meaning inside the fixture company.
    func testTheConversationDoesNotSurviveTheSwitch() async throws {
        let store = CompanyStore()
        store.startCodeRun(ask: "something real")
        XCTAssertFalse(store.chatMessages.isEmpty)

        guard await store.setPrototypeMode(!PrototypeMode.isOn) else {
            throw XCTSkip("a launch argument has locked the mode for this run")
        }
        XCTAssertTrue(store.chatMessages.isEmpty, "a transcript crossed between worlds")
        XCTAssertTrue(store.threads.isEmpty)
        XCTAssertNil(store.activeProjectLink,
                     "the fixture world inherited a link to real code on disk")

        await store.setPrototypeMode(!PrototypeMode.isOn)
    }
}

// codepetTests/ApprovalTierTests.swift
import XCTest
@testable import codepet

/// Guards on how much rope a session gets — spec §8.2, and §8.3, which records
/// `Let it run` as an AMENDMENT to a written safety rail rather than a preference.
///
/// This control decides whether a machine writes to the founder's files without
/// showing them first. Every assertion here is about the gap between what a tier
/// SAYS and what the app actually does, because that gap is the only way a control
/// like this hurts anyone.
final class ApprovalTierTests: XCTestCase {

    /// **The default is the permissive middle.** Defaulting to `Ask me` ships the
    /// complaint as the default; defaulting to `Let it run` would hand out the
    /// amendment to people who never read it.
    func testTheDefaultIsTheMiddleTier() {
        XCTAssertEqual(ApprovalTier.standard, .worksOnItsOwn)
        XCTAssertTrue(ApprovalTier.standard.promptsBeforeCommit)
        XCTAssertFalse(ApprovalTier.standard.promptsEveryStep)
    }

    /// **Exactly one tier skips the commit gate**, and it is the one whose own copy
    /// says so. If a second tier ever stops prompting, this goes red before anyone's
    /// files do.
    func testOnlyLetItRunSkipsTheCommitGate() {
        let skipping = ApprovalTier.allCases.filter { !$0.promptsBeforeCommit }
        XCTAssertEqual(skipping, [.letItRun])
        XCTAssertTrue(ApprovalTier.letItRun.detail(.en).contains("commits to the session branch"),
                      "the tier that writes without asking must say so in its own description")
        XCTAssertTrue(ApprovalTier.letItRun.detail(.en).contains("not see the diff first"))
    }

    /// **The app must not offer a tier it cannot honour.** `Ask me` promises that
    /// every command prompts, and nothing in the app can deliver that — `CodeRunning`
    /// is one call that returns an outcome, and the real backend is `claude` running
    /// its own tool loop in a subprocess. Selecting "every command prompts" and
    /// getting a run that prompts for nothing is the most dangerous direction this
    /// control can be wrong in, so the tier carries its own unavailability.
    func testATierTheAppCannotKeepIsMarkedUnavailableWithAReason() {
        XCTAssertFalse(ApprovalTier.askMe.isHonoured)
        XCTAssertNotNil(ApprovalTier.askMe.unavailableReason(.en))
        XCTAssertNotNil(ApprovalTier.askMe.unavailableReason(.vi))

        for tier in ApprovalTier.allCases where tier.isHonoured {
            XCTAssertNil(tier.unavailableReason(.en),
                         "\(tier) is offered as working AND carries an excuse")
        }
        // Whatever else changes, a tier that promises step prompts cannot be honoured
        // until a runner can pause — so these two must move together.
        for tier in ApprovalTier.allCases {
            XCTAssertEqual(tier.isHonoured, !tier.promptsEveryStep)
        }
    }

    /// The ceiling is not a tier setting. It has one definition, quoted by the work
    /// pane and by the picker, and it names all five prohibitions — a ceiling that
    /// quietly lost "force-push" would still read like a ceiling.
    func testTheCeilingIsOneStringAndNamesEverything() {
        let ceiling = ApprovalTier.ceiling(.en)
        for forbidden in ["merge", "deploy", "delete", "force-push", "outside the folder"] {
            XCTAssertTrue(ceiling.contains(forbidden), "the ceiling no longer says \(forbidden)")
        }
        XCTAssertFalse(ApprovalTier.ceiling(.vi).isEmpty)
    }

    /// Every tier is nameable and described in both languages — a blank menu row is
    /// a control nobody can choose deliberately.
    func testEveryTierIsNamedAndExplainedInBothLanguages() {
        for tier in ApprovalTier.allCases {
            for lang in [AppLanguage.en, .vi] {
                XCTAssertFalse(tier.label(lang).trimmingCharacters(in: .whitespaces).isEmpty)
                XCTAssertFalse(tier.detail(lang).trimmingCharacters(in: .whitespaces).isEmpty)
            }
            XCTAssertFalse(tier.icon.isEmpty)
        }
        XCTAssertEqual(ApprovalTier.allCases.count, 3)
    }

    /// The prototype's own keys, so the two implementations can be compared without
    /// a translation table. A `data-t` mismatch is invisible until someone reads both
    /// by hand — which is how the last one was found.
    func testTheKeysMatchThePrototypes() {
        XCTAssertEqual(ApprovalTier.allCases.map(\.prototypeKey), ["ask", "own", "run"])
    }
}

/// The tier is per-SESSION, which is only true if something resets it.
@MainActor
final class SessionApprovalTierTests: XCTestCase {

    func testANewSessionStartsAtTheDefault() {
        let store = CompanyStore()
        store.sessionApprovalTier = .letItRun
        store.newChat()
        XCTAssertEqual(store.sessionApprovalTier, .standard,
                       "a new session inherited the last one's rope")
    }

    /// Spec §8.2: "per-session, not global — permissive on your own repo, cautious on
    /// a client's". Switching to another session must not carry the permissive choice
    /// into it.
    func testSwitchingSessionsDoesNotCarryTheTier() {
        let store = CompanyStore()
        store.switchWorkspace(to: .dev)
        store.startCodeRun(ask: "first session")
        let first = store.activeThreadId
        store.newChat()
        store.startCodeRun(ask: "second session")
        store.sessionApprovalTier = .letItRun

        store.switchThread(first!)
        XCTAssertEqual(store.sessionApprovalTier, .standard,
                       "`Let it run` followed the founder into a different session")
    }
}

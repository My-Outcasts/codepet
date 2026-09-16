import XCTest
@testable import codepet

// MARK: - How the grant reaches the readiness verdict

final class ClaudeCodeReadinessTests: XCTestCase {

    private func signedIn(authorised: Bool) -> CLIStatus {
        CLIStatus(
            install: .present(version: "2.1.241"),
            auth: .loggedIn(.init(email: "founder@example.com",
                                  authMethod: "claude.ai",
                                  apiProvider: "firstParty",
                                  subscriptionType: "team",
                                  orgName: "Example Co")),
            authorised: authorised
        )
    }

    func testSignedInButNotAuthorisedIsNotReady() {
        let status = signedIn(authorised: false)
        XCTAssertFalse(status.isReady)
        XCTAssertEqual(status.blocker, .notAuthorised)
    }

    func testSignedInAndAuthorisedIsReady() {
        let status = signedIn(authorised: true)
        XCTAssertTrue(status.isReady)
        XCTAssertNil(status.blocker)
    }

    /// Order is the sequence the founder must fix things in. Being asked to authorise
    /// software that is not installed is an instruction they cannot follow, so the
    /// install problem must surface first — even when the grant is also missing.
    func testNotInstalledOutranksNotAuthorised() {
        let status = CLIStatus(install: .missing, auth: .unknown, authorised: false)
        XCTAssertEqual(status.blocker, .notInstalled)
    }

    func testNotSignedInOutranksNotAuthorised() {
        let status = CLIStatus(install: .present(version: "2.1.241"),
                                     auth: .loggedOut,
                                     authorised: false)
        XCTAssertEqual(status.blocker, .notSignedIn)
    }

    /// A granted founder whose CLI is too old still cannot run, and the reason they
    /// are shown must be the CLI — not their grant, which is fine.
    func testVersionUnknownOutranksNotAuthorised() {
        let status = CLIStatus(install: .present(version: "2.1.241"),
                                     auth: .unknown,
                                     authorised: false)
        XCTAssertEqual(status.blocker, .versionUnknown)
    }

    /// The grant is Codepet's own gate, so it must not be mistaken for a Claude Code
    /// problem: an ungranted-but-otherwise-fine machine still reports its account.
    func testAnUngrantedStatusStillKnowsWhoIsSignedIn() {
        XCTAssertEqual(signedIn(authorised: false).account?.subscriptionType, "team")
    }
}

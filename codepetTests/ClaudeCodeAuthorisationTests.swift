import XCTest
@testable import codepet

/// The founder's grant: "Codepet may spend my Claude plan."
///
/// Every case builds its own defaults suite and tears it down, so nothing here
/// touches the real domain or leaks a grant into the next case.
final class ClaudeCodeAuthorisationTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "claude-auth-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func authorisation() -> ClaudeCodeAuthorisation {
        ClaudeCodeAuthorisation(
            isAuthorised: { [defaults] in
                defaults!.bool(forKey: ClaudeCodeAuthorisation.key($0))
            },
            setAuthorised: { [defaults] companyId, on in
                defaults!.set(on, forKey: ClaudeCodeAuthorisation.key(companyId))
            }
        )
    }

    /// The whole point of the toggle: nothing spends the founder's plan until they
    /// say so. A missing key must read as "not granted", never as "probably fine".
    func testGrantIsOffUntilItIsGiven() {
        XCTAssertFalse(authorisation().isAuthorised("company-a"))
    }

    func testGrantRoundTrips() {
        let auth = authorisation()
        auth.setAuthorised("company-a", true)
        XCTAssertTrue(auth.isAuthorised("company-a"))
    }

    func testGrantCanBeWithdrawn() {
        let auth = authorisation()
        auth.setAuthorised("company-a", true)
        auth.setAuthorised("company-a", false)
        XCTAssertFalse(auth.isAuthorised("company-a"))
    }

    /// Keyed per company, not per device — the same reasoning
    /// `VirtualCompanyInterviewFlag` records. One Mac has ONE Claude Code login, so a
    /// device-global grant would mean founder A's consent silently lets founder B
    /// spend the plan A signed in with. B never agreed to that, and B is the one who
    /// would never be asked.
    func testOneFoundersGrantDoesNotAuthoriseAnother() {
        let auth = authorisation()
        auth.setAuthorised("company-a", true)
        XCTAssertFalse(auth.isAuthorised("company-b"))
    }

    /// The key carries the `cp_` prefix so `AccountDataStore` snapshots it per uid on
    /// an account switch, and the company suffix keeps it correct even if some future
    /// switch path forgets to go through that vault.
    func testKeyIsPrefixedAndScopedToTheCompany() {
        let key = ClaudeCodeAuthorisation.key("company-a")
        XCTAssertTrue(key.hasPrefix("cp_"), "must be swept by AccountDataStore")
        XCTAssertTrue(key.contains("company-a"), "must not be device-global")
    }
}

// MARK: - How the grant reaches the readiness verdict

final class ClaudeCodeReadinessTests: XCTestCase {

    private func signedIn(authorised: Bool) -> ClaudeCodeStatus {
        ClaudeCodeStatus(
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
        let status = ClaudeCodeStatus(install: .missing, auth: .unknown, authorised: false)
        XCTAssertEqual(status.blocker, .notInstalled)
    }

    func testNotSignedInOutranksNotAuthorised() {
        let status = ClaudeCodeStatus(install: .present(version: "2.1.241"),
                                     auth: .loggedOut,
                                     authorised: false)
        XCTAssertEqual(status.blocker, .notSignedIn)
    }

    /// A granted founder whose CLI is too old still cannot run, and the reason they
    /// are shown must be the CLI — not their grant, which is fine.
    func testVersionUnknownOutranksNotAuthorised() {
        let status = ClaudeCodeStatus(install: .present(version: "2.1.241"),
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

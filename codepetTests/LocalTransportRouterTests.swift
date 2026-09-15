import XCTest
@testable import codepet

/// Which runner a NON-STREAMING model call takes — and, now that there is only one runner,
/// whether it can run at all. Every case here is a guard on that, not on a rendering detail.
///
/// The streaming twin is `ChatTransportRouterTests`; the two routers are deliberately
/// separate because availability is a different question (a different bundle on disk), and
/// deliberately identical in what they decide from the grant.
final class LocalTransportRouterTests: XCTestCase {

    private var granted: Set<String> = []

    /// A grant table in memory, so no case touches the real defaults domain or leaks a
    /// grant into the next one.
    private var authorisation: ClaudeCodeAuthorisation {
        ClaudeCodeAuthorisation(
            isAuthorised: { [self] in granted.contains($0) },
            setAuthorised: { [self] id, on in
                if on { granted.insert(id) } else { granted.remove(id) }
            }
        )
    }

    override func setUp() {
        super.setUp()
        granted = []
        LocalTransportRouter.apply(companyId: nil)
    }

    override func tearDown() {
        LocalTransportRouter.apply(companyId: nil)
        super.tearDown()
    }

    private func transport(
        companyId: String?,
        sidecar: Bool = true
    ) -> LocalTransportRouter.Transport {
        LocalTransportRouter.transport(
            companyId: companyId, authorisation: authorisation, sidecarAvailable: { sidecar })
    }

    // MARK: - The grant decides

    func testAGrantedFounderGoesLocal() {
        granted.insert("c1")
        XCTAssertEqual(transport(companyId: "c1"), .local)
    }

    /// One Mac has one Claude Code login, so a grant that was not keyed per company would
    /// let founder A's consent spend the plan on founder B's brief. B never agreed.
    func testOneFoundersGrantDoesNotRouteAnothersCall() {
        granted.insert("c1")
        XCTAssertEqual(transport(companyId: "c2"), .blocked(.notGranted))
    }

    /// An empty string is not a company id, so it cannot carry a grant. It used to route to
    /// the Cloud Function; it now says the same thing every ungranted call says.
    func testAnEmptyCompanyIdIsBlockedLikeNoCompanyId() {
        XCTAssertEqual(transport(companyId: ""), .blocked(.notGranted))
    }

    // MARK: - Never silently spend the key they said not to spend

    /// THE most important case in this file. A granted founder whose machine cannot run the
    /// local path must NOT be quietly served by the Cloud Function: that spends an API key
    /// they had just said should not be spent — and since the key was deleted, it would fail
    /// as an unexplained network error rather than an answerable one.
    func testAGrantedFounderWithNoSidecarIsBlockedWithTheSidecarReason() {
        granted.insert("c1")
        let t = transport(companyId: "c1", sidecar: false)
        XCTAssertEqual(t, .blocked(.sidecarMissing))
        guard case .blocked(let reason) = t else {
            return XCTFail("expected blocked, got \(t)")
        }
        XCTAssertFalse(reason.founderText.isEmpty, "the founder needs something to act on")
    }

    /// A missing sidecar does not change what an ungranted founder is told: the grant is the
    /// first thing to fix, and naming the runner instead would send her to the wrong screen.
    func testAMissingSidecarDoesNotChangeAnUngrantedFoundersReason() {
        XCTAssertEqual(transport(companyId: "c1", sidecar: false), .blocked(.notGranted))
    }

    // MARK: - The active-company mirror

    /// The clients that call these ops take no company id, so the router reads a mirror.
    /// Whoever knows the company sets it — `CompanyStore.hydrate`, the one place that already
    /// had to do this.
    func testTheMirrorIsWhatAnUnparameterisedCallReads() {
        granted.insert("c1")
        LocalTransportRouter.apply(companyId: "c1")
        XCTAssertEqual(LocalTransportRouter.activeCompanyId, "c1")
        XCTAssertEqual(
            LocalTransportRouter.transport(
                authorisation: authorisation, sidecarAvailable: { true }),
            .local)
    }

    /// Sign-out passes nil. Leaving the previous founder's id in place would route the next
    /// account's calls onto the plan the previous one signed in with.
    func testSigningOutClearsTheMirror() {
        LocalTransportRouter.apply(companyId: "c1")
        LocalTransportRouter.apply(companyId: nil)
        XCTAssertNil(LocalTransportRouter.activeCompanyId)
    }

    /// An empty string is not a company. Treating it as one would key a grant to "" and let
    /// it apply to whoever came next.
    func testAnEmptyCompanyIdIsNotAnActiveCompany() {
        LocalTransportRouter.apply(companyId: "")
        XCTAssertNil(LocalTransportRouter.activeCompanyId)
    }

    // MARK: - There is nowhere else to send a run

    /// **There is no hosted runner to fall back to.** This is a totality check rather than a
    /// behaviour one: it fails to compile the day someone adds a case that reaches a Cloud
    /// Function, which is the only moment the mistake is cheap to fix.
    func testTransportIsOnlyEverLocalOrBlocked() {
        let cases: [LocalTransportRouter.Transport] = [.local, .blocked(.notGranted)]
        for c in cases {
            switch c {
            case .local, .blocked: continue   // exhaustive: adding a case breaks the build
            }
        }
    }

    func testAnUngrantedCompanyIsBlockedRatherThanSentToTheCloud() {
        var auth = ClaudeCodeAuthorisation()
        auth.isAuthorised = { _ in false }
        let t = LocalTransportRouter.transport(companyId: "c1", authorisation: auth,
                                               sidecarAvailable: { true })
        XCTAssertEqual(t, .blocked(.notGranted))
    }

    func testAGrantedCompanyWithNoSidecarSaysSo() {
        var auth = ClaudeCodeAuthorisation()
        auth.isAuthorised = { _ in true }
        let t = LocalTransportRouter.transport(companyId: "c1", authorisation: auth,
                                               sidecarAvailable: { false })
        XCTAssertEqual(t, .blocked(.sidecarMissing))
    }

    /// No company id used to mean "cloud". It now means the same thing an ungranted one does.
    func testNoCompanyIdIsBlockedNotCloud() {
        let t = LocalTransportRouter.transport(companyId: nil, authorisation: ClaudeCodeAuthorisation(),
                                               sidecarAvailable: { true })
        XCTAssertEqual(t, .blocked(.notGranted))
    }
}

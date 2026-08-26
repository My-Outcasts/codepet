import XCTest
@testable import codepet

/// Which transport a NON-STREAMING model call takes — and therefore whose money pays for
/// it. Every case here is a guard on that, not on a rendering detail.
///
/// The streaming twin is `ChatTransportRouterTests`; the two routers are deliberately
/// separate because availability is a different question (a different bundle on disk), and
/// deliberately identical in what they decide from the grant.
final class OneShotTransportRouterTests: XCTestCase {

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
        OneShotTransportRouter.apply(companyId: nil)
    }

    override func tearDown() {
        OneShotTransportRouter.apply(companyId: nil)
        super.tearDown()
    }

    private func transport(
        companyId: String?,
        sidecar: Bool = true
    ) -> OneShotTransportRouter.Transport {
        OneShotTransportRouter.transport(
            companyId: companyId, authorisation: authorisation, sidecarAvailable: { sidecar })
    }

    // MARK: - The grant decides

    /// The default is unchanged for everyone who has not granted anything. A founder who has
    /// never opened the Claude Code panel keeps the onboarding they already had.
    func testAnUngrantedFounderStaysOnCloud() {
        XCTAssertEqual(transport(companyId: "c1"), .cloud)
    }

    func testAGrantedFounderGoesLocal() {
        granted.insert("c1")
        XCTAssertEqual(transport(companyId: "c1"), .local)
    }

    /// One Mac has one Claude Code login, so a grant that was not keyed per company would
    /// let founder A's consent spend the plan on founder B's brief. B never agreed.
    func testOneFoundersGrantDoesNotRouteAnothersCall() {
        granted.insert("c1")
        XCTAssertEqual(transport(companyId: "c2"), .cloud)
    }

    /// No company id means no grant can exist. That is an ungranted call, not a broken one —
    /// failing here would break the very first enrich of onboarding.
    func testNoCompanyIdIsACloudCallNotAFailure() {
        XCTAssertEqual(transport(companyId: nil), .cloud)
        XCTAssertEqual(transport(companyId: ""), .cloud)
    }

    // MARK: - Never silently spend the key they said not to spend

    /// THE most important case in this file. A granted founder whose machine cannot run the
    /// local path must NOT be quietly served by the Cloud Function: that spends an API key
    /// they had just said should not be spent, and `CloudAIBlock` may be refusing that host
    /// anyway — so the founder would get an unexplained network error instead of a reason.
    func testAGrantedFounderWithNoSidecarFailsRatherThanFallingBackToCloud() {
        granted.insert("c1")
        let t = transport(companyId: "c1", sidecar: false)
        XCTAssertNotEqual(t, .cloud, "must never silently fall back to the paid path")
        guard case .localUnavailable(let reason) = t else {
            return XCTFail("expected localUnavailable, got \(t)")
        }
        XCTAssertFalse(reason.isEmpty, "the founder needs something to act on")
    }

    func testAMissingSidecarDoesNotDisturbAnUngrantedFounder() {
        XCTAssertEqual(transport(companyId: "c1", sidecar: false), .cloud)
    }

    // MARK: - The active-company mirror

    /// The clients that call these ops take no company id, so the router reads a mirror.
    /// Whoever knows the company sets it — `CompanyStore.applyCloudAIBlock()`, the one place
    /// that already had to do this for `CloudAIBlock`.
    func testTheMirrorIsWhatAnUnparameterisedCallReads() {
        granted.insert("c1")
        OneShotTransportRouter.apply(companyId: "c1")
        XCTAssertEqual(OneShotTransportRouter.activeCompanyId, "c1")
        XCTAssertEqual(
            OneShotTransportRouter.transport(
                authorisation: authorisation, sidecarAvailable: { true }),
            .local)
    }

    /// Sign-out passes nil. Leaving the previous founder's id in place would route the next
    /// account's calls onto the plan the previous one signed in with.
    func testSigningOutClearsTheMirror() {
        OneShotTransportRouter.apply(companyId: "c1")
        OneShotTransportRouter.apply(companyId: nil)
        XCTAssertNil(OneShotTransportRouter.activeCompanyId)
    }

    /// An empty string is not a company. Treating it as one would key a grant to "" and let
    /// it apply to whoever came next.
    func testAnEmptyCompanyIdIsNotAnActiveCompany() {
        OneShotTransportRouter.apply(companyId: "")
        XCTAssertNil(OneShotTransportRouter.activeCompanyId)
    }
}

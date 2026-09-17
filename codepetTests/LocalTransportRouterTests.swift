import XCTest
@testable import codepet

/// Which runner a NON-STREAMING model call takes — and, now that there is only one runner,
/// whether it can run at all. Every case here is a guard on that, not on a rendering detail.
///
/// The streaming twin is `ChatTransportRouterTests`; the two routers are deliberately
/// separate because availability is a different question (a different bundle on disk), and
/// deliberately identical in what they decide from the grant.
final class LocalTransportRouterTests: XCTestCase {

    /// Claude Code grants. Named for the plan it spends, because the grant is now per
    /// PROVIDER — a founder who granted this one was never asked about Codex.
    private var granted: Set<String> = []
    /// Codex grants, kept separate so a case can hold one WITHOUT the other. A single table
    /// would make "a Codex grant does not route to Claude Code" unprovable here.
    private var codexGranted: Set<String> = []

    /// A grant table in memory, so no case touches the real defaults domain or leaks a
    /// grant into the next one.
    private var authorisation: ProviderAuthorisation {
        ProviderAuthorisation(
            isAuthorised: { [self] provider, id in
                switch provider {
                case .claudeCode: return granted.contains(id)
                case .codex:      return codexGranted.contains(id)
                }
            },
            setAuthorised: { [self] provider, id, on in
                switch provider {
                case .claudeCode: if on { granted.insert(id) } else { granted.remove(id) }
                case .codex:      if on { codexGranted.insert(id) } else { codexGranted.remove(id) }
                }
            }
        )
    }

    override func setUp() {
        super.setUp()
        granted = []
        codexGranted = []
        LocalTransportRouter.apply(companyId: nil)
    }

    override func tearDown() {
        LocalTransportRouter.apply(companyId: nil)
        super.tearDown()
    }

    private func transport(
        companyId: String?,
        prefer: AIProvider? = nil,
        sidecar: Bool = true
    ) -> LocalTransportRouter.Transport {
        LocalTransportRouter.transport(
            companyId: companyId, authorisation: authorisation, prefer: prefer,
            sidecarAvailable: { sidecar })
    }

    // MARK: - The grant decides

    func testAGrantedFounderGoesLocal() {
        granted.insert("c1")
        XCTAssertEqual(transport(companyId: "c1"), .local(.claudeCode))
    }

    /// **The transport now says WHICH of the founder's plans pays for the run.** It could not
    /// before: `.local` carried nothing, so a run that had already happened could not be
    /// credited to anything. The value is DERIVED here, never chosen — `ProviderAuthorisation`
    /// is the only grant that exists, and it grants Claude Code.
    func testAGrantedFoundersRunIsCreditedToClaudeCode() {
        granted.insert("c1")
        guard case .local(let provider) = transport(companyId: "c1") else {
            return XCTFail("expected local, got \(transport(companyId: "c1"))")
        }
        XCTAssertEqual(provider, .claudeCode)
        XCTAssertEqual(provider.displayName, "Claude Code")
    }

    /// A founder who granted only Codex is a first-class founder. This is the case that was
    /// impossible before, and the whole reason this phase exists.
    func testACodexOnlyFounderRoutesToCodex() {
        codexGranted.insert("c1")
        XCTAssertTrue(granted.isEmpty, "setup sanity: no Claude grant exists")
        XCTAssertEqual(transport(companyId: "c1"), .local(.codex))
    }

    /// Claude wins when both are granted — today's behaviour, preserved. The spec ships the
    /// run card's offer INSTEAD of a per-company default, so this precedence is the default.
    func testClaudeWinsWhenBothAreGranted() {
        granted.insert("c1")
        codexGranted.insert("c1")
        XCTAssertEqual(transport(companyId: "c1"), .local(.claudeCode))
    }

    /// "Re-run on Codex" is this: the caller names the provider, and it is honoured even
    /// though Claude would otherwise win.
    func testAnExplicitPreferenceOverridesThePrecedence() {
        granted.insert("c1")
        codexGranted.insert("c1")
        XCTAssertEqual(transport(companyId: "c1", prefer: .codex), .local(.codex))
    }

    /// A preference is not a grant. Asking for a provider the founder never authorised must
    /// block, not silently spend the other plan — a silent fallback makes "which plan paid
    /// for this" unanswerable, which is the question this whole phase exists to answer.
    func testAPreferenceForAnUngrantedProviderIsBlockedNotSubstituted() {
        granted.insert("c1")
        XCTAssertTrue(codexGranted.isEmpty, "setup sanity: no Codex grant")
        XCTAssertEqual(transport(companyId: "c1", prefer: .codex), .blocked(.notGranted))
    }

    func testNoGrantAtAllIsStillBlocked() {
        XCTAssertEqual(transport(companyId: "c1"), .blocked(.notGranted))
    }

    /// The mirror: the Claude grant still routes exactly as it did, with no Codex grant
    /// anywhere. The split must be invisible to a founder who only ever granted Claude.
    func testAClaudeGrantStillRoutesLocalWithNoCodexGrant() {
        granted.insert("c1")
        XCTAssertTrue(codexGranted.isEmpty, "setup sanity: no Codex grant exists")
        XCTAssertEqual(transport(companyId: "c1"), .local(.claudeCode))
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
            .local(.claudeCode))
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
        let cases: [LocalTransportRouter.Transport] = [.local(.claudeCode), .blocked(.notGranted)]
        for c in cases {
            switch c {
            case .local, .blocked: continue   // exhaustive: adding a case breaks the build
            }
        }
    }

    func testAnUngrantedCompanyIsBlockedRatherThanSentToTheCloud() {
        var auth = ProviderAuthorisation()
        auth.isAuthorised = { _, _ in false }
        let t = LocalTransportRouter.transport(companyId: "c1", authorisation: auth,
                                               sidecarAvailable: { true })
        XCTAssertEqual(t, .blocked(.notGranted))
    }

    func testAGrantedCompanyWithNoSidecarSaysSo() {
        var auth = ProviderAuthorisation()
        auth.isAuthorised = { _, _ in true }
        let t = LocalTransportRouter.transport(companyId: "c1", authorisation: auth,
                                               sidecarAvailable: { false })
        XCTAssertEqual(t, .blocked(.sidecarMissing))
    }

    /// No company id used to mean "cloud". It now means the same thing an ungranted one does.
    func testNoCompanyIdIsBlockedNotCloud() {
        let t = LocalTransportRouter.transport(companyId: nil, authorisation: ProviderAuthorisation(),
                                               sidecarAvailable: { true })
        XCTAssertEqual(t, .blocked(.notGranted))
    }

    // MARK: - `forVirtualCompany` is genuinely Claude-only (Critical 2)

    /// THE case that was broken: `forVirtualCompany` carried a doc comment saying meetings
    /// stay Claude-only, but — because it forwarded into the shared `transport(...)` helper,
    /// which picks freely via `chooseProvider` — a founder who granted only Codex resolved
    /// `.local(.codex)` here, and `vcSidecar.js` has no Codex adapter at all: it would have
    /// spawned `claude` anyway while silently crediting Codex's plan. This must now BLOCK.
    func testACodexOnlyFounderIsBlockedFromAMeeting() {
        codexGranted.insert("c1")
        XCTAssertTrue(granted.isEmpty, "setup sanity: no Claude grant exists")
        XCTAssertEqual(
            LocalTransportRouter.forVirtualCompany(companyId: "c1", authorisation: authorisation,
                                                    sidecarAvailable: { true }),
            .blocked(.notGranted))
    }

    /// The mirror: a founder who granted Claude Code must still be able to hold meetings
    /// exactly as before — this fix must not regress the working path.
    func testAClaudeGrantedFounderStillGetsAMeeting() {
        granted.insert("c1")
        XCTAssertEqual(
            LocalTransportRouter.forVirtualCompany(companyId: "c1", authorisation: authorisation,
                                                    sidecarAvailable: { true }),
            .local(.claudeCode))
    }

    /// Both granted: Claude still runs the meeting. Holding both plans must not make the
    /// meeting eligible for Codex, since `vcSidecar.js` cannot run it.
    func testBothGrantedStillRunsTheMeetingOnClaude() {
        granted.insert("c1")
        codexGranted.insert("c1")
        XCTAssertEqual(
            LocalTransportRouter.forVirtualCompany(companyId: "c1", authorisation: authorisation,
                                                    sidecarAvailable: { true }),
            .local(.claudeCode))
    }

    /// No grant at all blocks, same reason as the one-shot ops.
    func testNoGrantAtAllBlocksAMeeting() {
        XCTAssertEqual(
            LocalTransportRouter.forVirtualCompany(companyId: "c1", authorisation: authorisation,
                                                    sidecarAvailable: { true }),
            .blocked(.notGranted))
    }
}

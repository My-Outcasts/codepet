import XCTest
@testable import codepet

/// The local meeting transport's decidable parts. The subprocess itself is proven by running
/// the sidecar against a real `claude`; what is tested here is everything that decides
/// WHETHER to run it and what gets sent.
final class LocalVirtualCompanyStreamerTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!

    /// The TEST bundle, which never carries the sidecar — `.main` is the app bundle and,
    /// once `scripts/build-sidecar.sh` has run, genuinely does.
    private var emptyBundle: Bundle { Bundle(for: LocalVirtualCompanyStreamerTests.self) }

    override func setUp() {
        super.setUp()
        suiteName = "local-vc-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testNoSidecarAnywhereMeansUnavailable() {
        XCTAssertNil(LocalVirtualCompanyStreamer.resolveSidecarPath(
            defaults: defaults, bundle: emptyBundle, fileExists: { _ in false }))
        XCTAssertFalse(LocalVirtualCompanyStreamer.isAvailable(
            defaults: defaults, bundle: emptyBundle))
    }

    /// Three bundles now ship, built by one script but failing independently. Resolving the
    /// wrong one would feed a meeting payload to a sidecar that answers with one JSON object,
    /// so the room would sit empty with nothing explaining why.
    func testItResolvesOnlyItsOwnSidecar() {
        XCTAssertNil(LocalVirtualCompanyStreamer.resolveSidecarPath(
            defaults: defaults, bundle: emptyBundle,
            fileExists: { $0.hasSuffix("oneShotSidecar.js") || $0.hasSuffix("chatSidecar.js") }))
    }

    func testDevOverrideIsUsedWhenTheFileIsThere() {
        defaults.set("/tmp/vcSidecar.js", forKey: LocalVirtualCompanyStreamer.sidecarPathKey)
        XCTAssertEqual(
            LocalVirtualCompanyStreamer.resolveSidecarPath(
                defaults: defaults, bundle: emptyBundle,
                fileExists: { $0 == "/tmp/vcSidecar.js" }),
            "/tmp/vcSidecar.js")
    }

    func testAStaleOverrideIsIgnoredRatherThanReturned() {
        defaults.set("/tmp/gone.js", forKey: LocalVirtualCompanyStreamer.sidecarPathKey)
        XCTAssertNil(LocalVirtualCompanyStreamer.resolveSidecarPath(
            defaults: defaults, bundle: emptyBundle, fileExists: { _ in false }))
    }

    /// The packaging guard. Without it a resource that stops being copied would make local
    /// meetings quietly unavailable for every founder, with nothing saying why.
    func testTheBundledSidecarIsReachableWhenItHasBeenBuilt() throws {
        guard Bundle.main.path(forResource: "vcSidecar", ofType: "js") != nil else {
            throw XCTSkip("no bundled vc sidecar — run scripts/build-sidecar.sh")
        }
        let resolved = LocalVirtualCompanyStreamer.resolveSidecarPath(
            defaults: defaults, bundle: .main)
        XCTAssertTrue(resolved?.hasSuffix("vcSidecar.js") ?? false)
    }

    /// One DTO for both transports. The sidecar validates this body with the SAME validator
    /// the Cloud Function uses, so a field renamed on one side fails on both rather than
    /// silently degrading one.
    func testTheSidecarGetsTheCloudFunctionsOwnWireShape() throws {
        let req = VirtualCompanyRequest(
            request: "Should we charge $19 or $49?",
            language: "en",
            founder: VCFounder(profile: "solo founder", stage: "Private beta",
                               constraints: ["6 months runway"]),
            stressTest: false)
        let json = try JSONSerialization.jsonObject(
            with: LocalVirtualCompanyStreamer.encode(req)) as? [String: Any]
        XCTAssertEqual(json?["request"] as? String, "Should we charge $19 or $49?")
        XCTAssertEqual(json?["language"] as? String, "en")
        // snake_case, because that is what `validateRunPayload` reads.
        XCTAssertNotNil(json?["stress_test"])
        XCTAssertNotNil(json?["founder"])
    }
}

/// Which transport a MEETING takes. Separate from the one-shot cases because the two ask a
/// different availability question, and because a meeting is the most expensive thing Codepet
/// buys — the measured ~$0.20 against ~$0.005 for an ordinary turn.
final class VirtualCompanyTransportTests: XCTestCase {

    private var granted: Set<String> = []

    private var authorisation: ClaudeCodeAuthorisation {
        ClaudeCodeAuthorisation(
            isAuthorised: { [self] in granted.contains($0) },
            setAuthorised: { [self] id, on in
                if on { granted.insert(id) } else { granted.remove(id) }
            })
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

    func testAnUngrantedFounderKeepsTheCloudRoom() {
        XCTAssertEqual(
            LocalTransportRouter.transport(companyId: "c1", authorisation: authorisation,
                                           sidecarAvailable: { true }),
            .cloud)
    }

    func testAGrantedFounderConvenesTheRoomOnTheirOwnPlan() {
        granted.insert("c1")
        XCTAssertEqual(
            LocalTransportRouter.transport(companyId: "c1", authorisation: authorisation,
                                           sidecarAvailable: { true }),
            .local)
    }

    /// THE case that matters here. A silent fallback would spend the API key the grant exists
    /// to stop spending, on the single most expensive call the app makes.
    func testAMissingMeetingSidecarFailsRatherThanBillingTheKey() {
        granted.insert("c1")
        let t = LocalTransportRouter.transport(companyId: "c1", authorisation: authorisation,
                                               sidecarAvailable: { false })
        XCTAssertNotEqual(t, .cloud)
        guard case .localUnavailable(let reason) = t else {
            return XCTFail("expected localUnavailable, got \(t)")
        }
        XCTAssertFalse(reason.isEmpty)
    }

    /// The two local transports are asked separately, so one missing bundle cannot take the
    /// other down: a founder whose meeting bundle is absent should still get their roadmap.
    func testTheTwoLocalTransportsAreAskedSeparately() {
        granted.insert("c1")
        XCTAssertEqual(
            LocalTransportRouter.transport(companyId: "c1", authorisation: authorisation,
                                           sidecarAvailable: { true }),
            .local)
        guard case .localUnavailable = LocalTransportRouter.transport(
            companyId: "c1", authorisation: authorisation, sidecarAvailable: { false }) else {
            return XCTFail("a missing bundle must not read as available")
        }
    }
}

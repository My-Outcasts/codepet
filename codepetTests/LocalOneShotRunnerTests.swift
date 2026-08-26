import XCTest
@testable import codepet

/// The local one-shot transport's decidable parts. The subprocess itself is proven by
/// running the sidecar against a real `claude`; what is tested here is everything that
/// decides WHETHER to run it, what gets sent, and how a refusal is read back.
final class LocalOneShotRunnerTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!

    /// The TEST bundle, which never carries the sidecar — `.main` is the app bundle and,
    /// once `scripts/build-sidecar.sh` has run, genuinely does.
    private var emptyBundle: Bundle { Bundle(for: LocalOneShotRunnerTests.self) }

    override func setUp() {
        super.setUp()
        suiteName = "local-oneshot-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Finding the sidecar

    /// The bundle is build output and gitignored, so a fresh checkout has none. Returning nil
    /// rather than a guessed path is what lets the caller say "the local path is unavailable"
    /// instead of "the run failed" — two different messages, one of them actionable.
    func testNoSidecarAnywhereMeansUnavailable() {
        XCTAssertNil(LocalOneShotRunner.resolveSidecarPath(
            defaults: defaults, bundle: emptyBundle, fileExists: { _ in false }))
        XCTAssertFalse(LocalOneShotRunner.isAvailable(defaults: defaults, bundle: emptyBundle))
    }

    func testDevOverrideIsUsedWhenTheFileIsThere() {
        defaults.set("/tmp/oneShotSidecar.js", forKey: LocalOneShotRunner.sidecarPathKey)
        XCTAssertEqual(
            LocalOneShotRunner.resolveSidecarPath(
                defaults: defaults, bundle: emptyBundle,
                fileExists: { $0 == "/tmp/oneShotSidecar.js" }),
            "/tmp/oneShotSidecar.js")
    }

    /// A stale override is the normal state after a `git clean` or a branch switch. Handing it
    /// back would spawn `node` on nothing and surface a shell error instead of an honest
    /// "not built yet".
    func testAStaleOverrideIsIgnoredRatherThanReturned() {
        defaults.set("/tmp/gone.js", forKey: LocalOneShotRunner.sidecarPathKey)
        XCTAssertNil(LocalOneShotRunner.resolveSidecarPath(
            defaults: defaults, bundle: emptyBundle, fileExists: { _ in false }))
    }

    /// The chat sidecar and this one are separate bundles, and resolution must not cross:
    /// finding chat's would run a streaming turn for an op that expects one JSON body.
    func testItDoesNotResolveTheChatSidecar() {
        XCTAssertNil(LocalOneShotRunner.resolveSidecarPath(
            defaults: defaults, bundle: emptyBundle, fileExists: { $0.hasSuffix("chatSidecar.js") }))
    }

    /// The packaging guard. Without it a broken build script, or a resource that stops being
    /// copied, would make the local path quietly unavailable for every founder — the router
    /// would report localUnavailable forever and nothing would say why.
    ///
    /// Skips rather than fails when absent: a developer who has not run the build script yet
    /// has a legitimately incomplete bundle, and that step is not part of `xcodebuild test`.
    func testTheBundledSidecarIsReachableWhenItHasBeenBuilt() throws {
        guard Bundle.main.path(forResource: "oneShotSidecar", ofType: "js") != nil else {
            throw XCTSkip("no bundled one-shot sidecar — run scripts/build-sidecar.sh")
        }
        let resolved = LocalOneShotRunner.resolveSidecarPath(defaults: defaults, bundle: .main)
        XCTAssertTrue(resolved?.hasSuffix("oneShotSidecar.js") ?? false)
        XCTAssertTrue(LocalOneShotRunner.isAvailable(defaults: defaults, bundle: .main))
    }

    // MARK: - What gets sent

    /// One DTO for both transports: the body is the Cloud Function's own, wrapped with the
    /// op name. If the sidecar needed its own encoding there would be two definitions of the
    /// wire shape, and the local path would drift the moment a field was added.
    func testTheSidecarGetsTheOpNameAndTheCloudFunctionsOwnBody() throws {
        let body = try JSONEncoder().encode(
            EnrichBriefRequest(brief: CompanyBrief(projectName: "Codepet", oneLiner: "an app")))
        let wrapped = try LocalOneShotRunner.encodeRequest(op: "enrichBrief", body: body)
        let json = try JSONSerialization.jsonObject(with: wrapped) as? [String: Any]
        XCTAssertEqual(json?["op"] as? String, "enrichBrief")
        let inner = json?["body"] as? [String: Any]
        let brief = inner?["brief"] as? [String: Any]
        XCTAssertEqual(brief?["projectName"] as? String, "Codepet")
    }

    /// The body travels as JSON, not as a string containing JSON. A stringified body would
    /// reach the op as one opaque value and every field lookup in it would miss.
    func testTheBodyIsNestedAsJsonRatherThanStringified() throws {
        let wrapped = try LocalOneShotRunner.encodeRequest(
            op: "enrichBrief", body: Data(#"{"brief":{"projectName":"X"}}"#.utf8))
        let json = try JSONSerialization.jsonObject(with: wrapped) as? [String: Any]
        XCTAssertTrue(json?["body"] is [String: Any])
    }

    // MARK: - Reading a refusal

    /// The sidecar reports failure as `{"error", "detail"}` and success as the Cloud
    /// Function's body. Mistaking one for the other would either swallow a real failure or
    /// throw away a good answer.
    func testAnErrorObjectIsReadAsARefusalCarryingItsDetail() {
        let failure = LocalOneShotRunner.failure(
            in: Data(#"{"error":"unknown_op","detail":"no local runner for op 'x'"}"#.utf8))
        XCTAssertEqual(
            failure,
            .refused(error: "unknown_op", detail: "no local runner for op 'x'"))
        XCTAssertEqual(
            failure?.localizedDescription,
            "unknown_op: no local runner for op 'x'")
    }

    func testAResponseBodyIsNotARefusal() {
        XCTAssertNil(LocalOneShotRunner.failure(in: Data(#"{"brief":{"summary":"x"}}"#.utf8)))
        XCTAssertNil(LocalOneShotRunner.failure(
            in: Data(#"{"overview":"You are building X.","model":"m"}"#.utf8)))
    }

    /// Output that is not JSON at all is a broken runner, not an empty answer. Reporting it
    /// as a refusal is what stops a caller decoding garbage into a founder's brief.
    func testNonJsonOutputIsAFailureRatherThanAnAnswer() {
        XCTAssertEqual(LocalOneShotRunner.failure(in: Data("zsh: command not found: node".utf8)),
                       .malformedOutput)
    }

    // MARK: - Credential hygiene

    /// The local path spawns through a login shell, which sources the founder's profile. Both
    /// variables outrank their subscription and under `-p` a present key is always used, so
    /// an exported one would bill their API account for the work this whole design exists to
    /// put on the plan they already pay for. Stripped here AND again in the sidecar, because
    /// either process could be the one that spawns `claude`.
    func testTheTransportStripsTheSameCredentialsTheShellRunnerDoes() {
        let scrubbed = LoginShellRunner.scrubbedEnvironment([
            "PATH": "/usr/bin", "ANTHROPIC_API_KEY": "sk-ant-x", "ANTHROPIC_AUTH_TOKEN": "t"
        ])
        XCTAssertNil(scrubbed["ANTHROPIC_API_KEY"])
        XCTAssertNil(scrubbed["ANTHROPIC_AUTH_TOKEN"])
        XCTAssertEqual(scrubbed["PATH"], "/usr/bin")
    }
}

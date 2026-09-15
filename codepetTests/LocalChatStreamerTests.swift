import XCTest
@testable import codepet

/// The local chat transport's decidable parts. The subprocess itself is proven by running
/// the sidecar against a real `claude`; what is tested here is everything that decides
/// WHETHER to run it and what gets sent.
final class LocalChatStreamerTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!

    /// The TEST bundle, which never carries the sidecar — `.main` is the app bundle and,
    /// since packaging landed, genuinely does. Two cases here asserted "nothing anywhere"
    /// against `.main` and went red the moment the resource started shipping, which is the
    /// packaging working rather than a regression.
    private var emptyBundle: Bundle { Bundle(for: LocalChatStreamerTests.self) }

    override func setUp() {
        super.setUp()
        suiteName = "local-chat-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Finding the sidecar

    /// `functions/lib` is gitignored, so a fresh checkout has no sidecar until
    /// `npm run build` has run. Returning nil rather than a guessed path is what lets the
    /// caller say "the local path is unavailable" instead of "the run failed" — two
    /// different messages, and only one of them is actionable.
    func testNoSidecarAnywhereMeansUnavailable() {
        XCTAssertNil(LocalChatStreamer.resolveSidecarPath(
            defaults: defaults, bundle: emptyBundle, fileExists: { _ in false }))
        XCTAssertFalse(LocalChatStreamer.isAvailable(defaults: defaults, bundle: emptyBundle))
    }

    func testDevOverrideIsUsedWhenTheFileIsThere() {
        defaults.set("/tmp/chatSidecar.js", forKey: LocalChatStreamer.sidecarPathKey)
        let found = LocalChatStreamer.resolveSidecarPath(
            defaults: defaults, bundle: emptyBundle, fileExists: { $0 == "/tmp/chatSidecar.js" })
        XCTAssertEqual(found, "/tmp/chatSidecar.js")
    }

    /// An override pointing at a path that no longer exists is the normal state after a
    /// `git clean` or a branch switch. Handing it back would spawn `node` on nothing and
    /// surface a shell error instead of an honest "not built yet".
    func testAStaleOverrideIsIgnoredRatherThanReturned() {
        defaults.set("/tmp/gone.js", forKey: LocalChatStreamer.sidecarPathKey)
        XCTAssertNil(LocalChatStreamer.resolveSidecarPath(
            defaults: defaults, bundle: emptyBundle, fileExists: { _ in false }))
    }

    func testAnEmptyOverrideIsNotAPath() {
        defaults.set("", forKey: LocalChatStreamer.sidecarPathKey)
        XCTAssertNil(LocalChatStreamer.resolveSidecarPath(
            defaults: defaults, bundle: emptyBundle, fileExists: { _ in true }))
    }

    /// The packaging guard, and it exists BECAUSE two tests above broke when packaging
    /// started working. Without it, a broken `scripts/build-sidecar.sh` or a resource that
    /// stops being copied would make local chat quietly unavailable for every founder —
    /// the router would report localUnavailable forever and nothing would say why.
    ///
    /// Skips rather than fails when the resource is absent: a developer who has not run the
    /// build script yet has a legitimately incomplete bundle, and failing here would punish
    /// them for a step that is not part of `xcodebuild test`.
    func testTheBundledSidecarIsReachableWhenItHasBeenBuilt() throws {
        guard Bundle.main.path(forResource: "chatSidecar", ofType: "js") != nil else {
            throw XCTSkip("no bundled sidecar — run scripts/build-sidecar.sh")
        }
        let resolved = LocalChatStreamer.resolveSidecarPath(defaults: defaults, bundle: .main)
        XCTAssertNotNil(resolved, "the bundle has it, so resolution must find it")
        XCTAssertTrue(resolved?.hasSuffix("chatSidecar.js") ?? false)
        XCTAssertTrue(LocalChatStreamer.isAvailable(defaults: defaults, bundle: .main))
    }

    // MARK: - What gets sent

    private func request(_ message: String) -> CompanyChatRequest {
        CompanyChatRequest(
            companyId: "c1", language: "en", companionId: "byte",
            context: "ACME sells widgets.", history: [], userMessage: message,
            runnable: [], openTasks: [], envSetup: [],
            styleFragment: nil, enabledSkills: [], deptKey: nil, attachments: nil
        )
    }

    /// One DTO for both transports. If the sidecar needed its own encoding there would be
    /// two definitions of the wire shape, and the local path would drift the moment a
    /// field was added to the Cloud Function's body.
    func testTheSidecarGetsTheCloudFunctionsOwnWireShape() throws {
        let json = try JSONSerialization.jsonObject(
            with: LocalChatStreamer.encode(request("hello"))) as? [String: Any]
        XCTAssertEqual(json?["user_message"] as? String, "hello")
        // snake_case, because that is what the CF reads and companyChatCore parses.
        XCTAssertNotNil(json?["companion_id"])
        XCTAssertNotNil(json?["company_id"])
    }

    /// The zero-cost default has to stay observable on this path too: no key, no prompt
    /// section, no tokens. An encoder that emitted `"style_fragment": ""` would silently
    /// add a prompt section for every founder who never touched a knob.
    func testAnUnsetStyleFragmentIsOmittedEntirely() throws {
        let json = try JSONSerialization.jsonObject(
            with: LocalChatStreamer.encode(request("hi"))) as? [String: Any]
        XCTAssertNil(json?["style_fragment"])
    }

    // MARK: - Credential hygiene

    /// The local path spawns through a login shell, which sources the founder's profile.
    /// Both variables outrank their subscription and under `-p` a present key is always
    /// used, so an exported one would bill their API account for the work this whole design
    /// exists to put on the plan they already pay for. Stripped here AND again in the
    /// sidecar, because either process could be the one that spawns `claude`.
    func testTheTransportStripsTheSameCredentialsTheShellRunnerDoes() {
        XCTAssertEqual(
            Set(LoginShellRunner.strippedEnvironmentKeys),
            Set(["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"])
        )
        let scrubbed = LoginShellRunner.scrubbedEnvironment([
            "PATH": "/usr/bin", "ANTHROPIC_API_KEY": "sk-ant-x"
        ])
        XCTAssertNil(scrubbed["ANTHROPIC_API_KEY"])
        XCTAssertEqual(scrubbed["PATH"], "/usr/bin")
    }

    // MARK: - Frame decoding, shared with the cloud transport

    /// `handleStreamFrame` was made internal so both transports decode a frame the same
    /// way. These prove the local path inherits that behaviour rather than reimplementing
    /// it — including the part that matters most: a `done` frame carrying an action.
    func testASharedDeltaFrameYieldsText() async throws {
        let events = try await collect(frames: [
            SSEFrame(event: "delta", data: #"{"text":"Roadmap's"}"#),
            SSEFrame(event: "delta", data: #"{"text":" open."}"#),
        ])
        XCTAssertEqual(events, [.delta("Roadmap's"), .delta(" open.")])
    }

    func testASharedDoneFrameCarriesTheNavigateAction() async throws {
        let events = try await collect(frames: [
            SSEFrame(event: "done",
                     data: #"{"model":"claude-opus-5","cache_hit":false,"run_task_id":null,"nav":{"destination":"roadmap"}}"#)
        ])
        guard case .done(let model, let cacheHit, let action) = events.first else {
            return XCTFail("expected a done event, got \(events)")
        }
        XCTAssertEqual(model, "claude-opus-5")
        // The local path cannot reach prompt caching, so it reports false rather than
        // inventing a hit.
        XCTAssertFalse(cacheHit)
        XCTAssertEqual(action.nav?.destination, "roadmap")
    }

    /// A founder who has already watched half an answer arrive must still have it when the
    /// stream fails afterwards. The sidecar emits deltas and can then emit an `error` frame
    /// — `LocalChatStreamer.sendStream` decodes both through this same `handleStreamFrame`
    /// — so "it threw" and "what she had already read survived the throw" are two different
    /// promises, and only the first is covered above.
    ///
    /// This is the second assertion of the deleted `testChatStreamMidStreamErrorThrows`.
    /// Dropping it left the behaviour live and unwatched: a decoder that buffered deltas
    /// until `done` would pass every other case in this file and blank her screen here.
    func testDeltasAlreadyDeliveredSurviveAMidStreamError() async {
        var collected: [CompanyChatStreamEvent] = []
        do {
            try await collect(frames: [
                SSEFrame(event: "delta", data: #"{"text":"hi"}"#),
                SSEFrame(event: "error", data: #"{"error":"upstream_failure","detail":"claude exited 1"}"#)
            ], into: &collected)
            XCTFail("an error frame after a delta must not resolve quietly")
        } catch {
            // Expected — assertion one. Assertion two is below, and it is the one nothing
            // else in the suite makes.
        }
        XCTAssertEqual(
            collected, [.delta("hi")],
            "the delta the founder had already read was discarded when the stream threw")
    }

    func testASharedErrorFrameThrows() async {
        do {
            _ = try await collect(frames: [
                SSEFrame(event: "error", data: #"{"error":"upstream_failure","detail":"claude exited 1"}"#)
            ])
            XCTFail("an error frame must not resolve quietly")
        } catch {
            // The store shows an honest offline message; what matters is that it throws
            // rather than finishing with a half-written reply.
        }
    }

    /// Drive frames through the shared decoder the way the transport does, appending each
    /// event to `out` AS IT ARRIVES.
    ///
    /// The `inout` is the whole point. Returning the array meant a throwing run discarded
    /// everything it had collected, so no test could see what the founder had already read
    /// when the stream failed — the half of `testChatStreamMidStreamErrorThrows` that the
    /// error-frame case above does not cover.
    private func collect(
        frames: [SSEFrame], into out: inout [CompanyChatStreamEvent]
    ) async throws {
        let stream = AsyncThrowingStream<CompanyChatStreamEvent, Error> { continuation in
            do {
                for frame in frames {
                    try CompanyChatClient.handleStreamFrame(frame: frame, continuation: continuation)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        for try await event in stream { out.append(event) }
    }

    /// The same drive, for the cases that only care about a clean run's events.
    @discardableResult
    private func collect(frames: [SSEFrame]) async throws -> [CompanyChatStreamEvent] {
        var out: [CompanyChatStreamEvent] = []
        try await collect(frames: frames, into: &out)
        return out
    }
}

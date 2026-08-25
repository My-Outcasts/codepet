import XCTest
@testable import codepet

/// The local chat transport's decidable parts. The subprocess itself is proven by running
/// the sidecar against a real `claude`; what is tested here is everything that decides
/// WHETHER to run it and what gets sent.
final class LocalChatStreamerTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!

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
            defaults: defaults, bundle: .main, fileExists: { _ in false }))
        XCTAssertFalse(LocalChatStreamer.isAvailable(defaults: defaults, bundle: .main))
    }

    func testDevOverrideIsUsedWhenTheFileIsThere() {
        defaults.set("/tmp/chatSidecar.js", forKey: LocalChatStreamer.sidecarPathKey)
        let found = LocalChatStreamer.resolveSidecarPath(
            defaults: defaults, bundle: .main, fileExists: { $0 == "/tmp/chatSidecar.js" })
        XCTAssertEqual(found, "/tmp/chatSidecar.js")
    }

    /// An override pointing at a path that no longer exists is the normal state after a
    /// `git clean` or a branch switch. Handing it back would spawn `node` on nothing and
    /// surface a shell error instead of an honest "not built yet".
    func testAStaleOverrideIsIgnoredRatherThanReturned() {
        defaults.set("/tmp/gone.js", forKey: LocalChatStreamer.sidecarPathKey)
        XCTAssertNil(LocalChatStreamer.resolveSidecarPath(
            defaults: defaults, bundle: .main, fileExists: { _ in false }))
    }

    func testAnEmptyOverrideIsNotAPath() {
        defaults.set("", forKey: LocalChatStreamer.sidecarPathKey)
        XCTAssertNil(LocalChatStreamer.resolveSidecarPath(
            defaults: defaults, bundle: .main, fileExists: { _ in true }))
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

    /// Drive frames through the shared decoder the way the transport does.
    private func collect(frames: [SSEFrame]) async throws -> [CompanyChatStreamEvent] {
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
        var out: [CompanyChatStreamEvent] = []
        for try await event in stream { out.append(event) }
        return out
    }
}

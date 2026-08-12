// codepetTests/EngineeringClientTests.swift
import XCTest
@testable import codepet

/// Drives the real client against a canned byte stream, because the bugs worth
/// catching here are all about BYTES: a frame split across a chunk boundary, a
/// heartbeat landing mid-frame, a last frame with no trailing newline. None of
/// those are visible in a test that hands the client whole frames.
final class EngineeringClientTests: XCTestCase {

    // MARK: - a URLProtocol that emits a scripted body

    final class StubProtocol: URLProtocol {
        /// Set per test. `chunks` are delivered in order, so a test can split a
        /// frame wherever it likes.
        nonisolated(unsafe) static var status = 200
        nonisolated(unsafe) static var chunks: [String] = []
        nonisolated(unsafe) static var requests: [URLRequest] = []

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.requests.append(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: Self.status,
                httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            for chunk in Self.chunks {
                client?.urlProtocol(self, didLoad: Data(chunk.utf8))
            }
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private func makeClient() -> EngineeringClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return EngineeringClient(
            base: URL(string: "https://example.test")!,
            session: URLSession(configuration: config),
            idToken: { "test-token" }
        )
    }

    override func setUp() {
        super.setUp()
        StubProtocol.status = 200
        StubProtocol.chunks = []
        StubProtocol.requests = []
    }

    private func collect(_ chunks: [String]) async throws -> [EngineeringFrame] {
        StubProtocol.chunks = chunks
        var frames: [EngineeringFrame] = []
        try await makeClient().attach(runId: "run_1") { frames.append($0) }
        return frames
    }

    // MARK: - byte handling

    func testCarriesAFrameAcrossLinesAndChunks() async throws {
        // Uses `step`, NOT `message`. The first version of this test used
        // `message` and was worthless: `message` is SSEParser's default event
        // name, so a parser rebuilt per line still produced the right frame by
        // accident and the test stayed green under exactly the mutation it
        // existed to catch.
        //
        // With a non-default event name the two halves have to be carried
        // together — the `event:` line and its `data:` line are separate lines,
        // and a stateless parser loses the name.
        let frames = try await collect([
            "event: step\ndata: {\"id\":\"s1\",\"lab",
            "el\":\"read a.ts\",\"done\":false}\n\n"
        ])
        guard case .step(let step)? = frames.first else {
            return XCTFail("expected a step frame, got \(frames)")
        }
        XCTAssertEqual(step.id, "s1")
        XCTAssertEqual(step.label, "read a.ts")
    }

    func testCarriesAMultiLineDataFrame() async throws {
        // SSE joins repeated `data:` lines with a newline, and the halves below
        // are only valid JSON once joined. That is the point: the first version
        // of this test used two lines that were invalid either way and asserted
        // `frames.isEmpty`, which held whether the parser joined them or not —
        // it could not fail, so it tested nothing.
        let frames = try await collect([
            "event: message\ndata: {\"text\":\ndata: \"joined\"}\n\n"
        ])
        XCTAssertEqual(frames, [.message("joined")],
                       "two data lines must be joined into one frame, not dispatched separately")
    }

    func testAHeartbeatBetweenFramesIsNotDelivered() async throws {
        // The relay sends `: heartbeat` every few seconds. Treating one as a
        // frame would spam the transcript with empty rows.
        let frames = try await collect([
            ": heartbeat\n\n",
            "event: message\ndata: {\"text\":\"hi\"}\n\n",
            ": heartbeat\n\n"
        ])
        XCTAssertEqual(frames, [.message("hi")])
    }

    func testAHeartbeatArrivingMidFrameDoesNotCorruptIt() async throws {
        let frames = try await collect([
            "event: message\ndata: {\"text\":",
            "\"hi\"}\n\n: heartbeat\n\n"
        ])
        XCTAssertEqual(frames, [.message("hi")])
    }

    func testDeliversEveryFrameWhenSeveralArriveInOneChunk() async throws {
        let frames = try await collect([
            "event: message\ndata: {\"text\":\"a\"}\n\nevent: done\ndata: {\"stopReason\":\"end_turn\"}\n\n"
        ])
        XCTAssertEqual(frames, [.message("a"), .done(stopReason: "end_turn")])
    }

    func testAFinalFrameWithNoTrailingBlankLineIsStillDelivered() async throws {
        // A truncated connection must not swallow the last frame the relay did
        // manage to send.
        let frames = try await collect(["event: message\ndata: {\"text\":\"last\"}\n"])
        XCTAssertEqual(frames, [.message("last")])
    }

    func testAnUnreadableFrameDoesNotStopTheOnesAfterIt() async throws {
        // A paid run already in flight must survive one bad frame.
        let frames = try await collect([
            "event: step\ndata: not json\n\n",
            "event: message\ndata: {\"text\":\"still here\"}\n\n"
        ])
        XCTAssertEqual(frames, [.message("still here")])
    }

    // MARK: - the request itself

    func testTheStreamRequestCarriesTheRunIdAndAsksForEventStream() async throws {
        _ = try await collect(["event: done\ndata: {}\n\n"])
        let request = StubProtocol.requests.last
        XCTAssertEqual(request?.url?.query?.contains("runId=run_1"), true)
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Accept"), "text/event-stream")
    }

    func testTheTokenTravelsAsAnAuthorizationHeaderNotInTheURL() async throws {
        // A token in a URL lands in every access log on the path.
        _ = try await collect(["event: done\ndata: {}\n\n"])
        let request = StubProtocol.requests.last
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(request?.url?.absoluteString.contains("test-token"), false)
    }

    // MARK: - refusals the founder must be able to act on

    func testTheTwoFourOhNinesStayDistinct() async throws {
        // "Connect a repo" and "connect GitHub" need different fixes; the code
        // in the body is the only thing that separates them.
        StubProtocol.status = 409
        StubProtocol.chunks = [#"{"error":"no_repo_linked"}"#]
        var thrown: Error?
        do { try await makeClient().attach(runId: "r") { _ in } } catch { thrown = error }
        XCTAssertEqual(thrown as? EngineeringError, .noRepoLinked)

        StubProtocol.chunks = [#"{"error":"github_not_connected"}"#]
        do { try await makeClient().attach(runId: "r") { _ in } } catch { thrown = error }
        XCTAssertEqual(thrown as? EngineeringError, .gitHubNotConnected)
    }

    func testOutOfCreditsIsItsOwnRefusal() async throws {
        StubProtocol.status = 402
        StubProtocol.chunks = [#"{"error":"no_credits"}"#]
        var thrown: Error?
        do { try await makeClient().attach(runId: "r") { _ in } } catch { thrown = error }
        XCTAssertEqual(thrown as? EngineeringError, .noCredits)
    }

    func testNoFrameIsDeliveredOnANonTwoHundred() async throws {
        // The body of a refusal is JSON, not SSE. Parsing it as frames would
        // render an error as content.
        StubProtocol.status = 503
        StubProtocol.chunks = [#"{"error":"lookup_failed"}"#]
        var frames: [EngineeringFrame] = []
        do { try await makeClient().attach(runId: "r") { frames.append($0) } } catch {}
        XCTAssertTrue(frames.isEmpty)
    }

    func testAMalformedErrorBodyStillProducesTheRightKindOfRefusal() async throws {
        StubProtocol.status = 503
        StubProtocol.chunks = ["<html>gateway timeout</html>"]
        var thrown: Error?
        do { try await makeClient().attach(runId: "r") { _ in } } catch { thrown = error }
        XCTAssertEqual(thrown as? EngineeringError, .unavailable)
    }

    // MARK: - diff

    func testDiffSendsTheScopeAndDecodesTheSummary() async throws {
        StubProtocol.chunks = [#"""
        {"files":[{"file":"a.ts","path":"a.ts","additions":2,"deletions":0,"status":"added","patch":"@@"}],
        "additions":2,"deletions":0,"truncated":false,"scope":"branch","scopeFellBack":false}
        """#]
        let summary = try await makeClient().diff(runId: "run_1", scope: .branch)
        XCTAssertEqual(summary.files.count, 1)
        XCTAssertEqual(StubProtocol.requests.last?.url?.query?.contains("scope=branch"), true)
    }

    func testDiffSurfacesTruncationAndFallbackRatherThanSwallowingThem() async throws {
        StubProtocol.chunks = [#"""
        {"files":[],"additions":0,"deletions":0,"truncated":true,"scope":"branch","scopeFellBack":true}
        """#]
        let summary = try await makeClient().diff(runId: "run_1", scope: .turn)
        XCTAssertTrue(summary.truncated)
        XCTAssertTrue(summary.scopeFellBack)
    }

    // MARK: - sending a turn

    func testSendPostsTheTurnBodyWithTheRunId() async throws {
        StubProtocol.chunks = ["{\"ok\":true}"]
        try await makeClient().send(runId: "run_1", turn: .approve(toolUseId: "tu_1"))
        let request = StubProtocol.requests.last
        XCTAssertEqual(request?.httpMethod, "POST")
        // URLProtocol strips httpBody into httpBodyStream, so assert on the
        // URL and method here; the body shape is covered by
        // EngineeringTurnBodyTests against the same `body` used to build it.
        XCTAssertEqual(request?.url?.lastPathComponent, "engSendTurn")
    }
}

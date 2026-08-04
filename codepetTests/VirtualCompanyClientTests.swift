import XCTest
@testable import codepet

// Mirrors CompanyChatMockURLProtocol. VirtualCompanyClient is a plain enum with
// static functions (no actor isolation), so these tests need no @MainActor and
// dodge the Xcode 26.2 isolated-deinit teardown bug entirely.
final class VCMockURLProtocol: URLProtocol {
    static var responseStatus: Int = 200
    static var responseHeaders: [String: String] = ["Content-Type": "text/event-stream"]
    static var responseChunks: [Data] = []
    /// Set inside `stopLoading()` — proves the client tore down the connection
    /// (via `continuation.onTermination` cancelling the detached Task) rather
    /// than leaking it after the consumer walks away mid-stream.
    static var stopLoadingCalled = false

    static func reset() {
        responseStatus = 200
        responseHeaders = ["Content-Type": "text/event-stream"]
        responseChunks = []
        stopLoadingCalled = false
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!,
                                       statusCode: VCMockURLProtocol.responseStatus,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: VCMockURLProtocol.responseHeaders)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in VCMockURLProtocol.responseChunks {
            client?.urlProtocol(self, didLoad: chunk)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        VCMockURLProtocol.stopLoadingCalled = true
    }
}

final class VirtualCompanyClientTests: XCTestCase {

    private func mockedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [VCMockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func request() -> VirtualCompanyRequest {
        VirtualCompanyRequest(request: "Nên tăng giá hay ship team feature?",
                              language: "vi",
                              founder: VCFounder(profile: "p", stage: "s", constraints: []),
                              stressTest: false)
    }

    private func collect(_ session: URLSession) async throws -> [VirtualCompanyEvent] {
        var events: [VirtualCompanyEvent] = []
        for try await ev in VirtualCompanyClient.run(request(),
                                                    session: session,
                                                    authTokenProvider: { "fake" }) {
            events.append(ev)
        }
        return events
    }

    func testEscapeHatchStreamYieldsRoutingThenDone() async throws {
        VCMockURLProtocol.reset()
        VCMockURLProtocol.responseChunks = [
            "event: run_started\ndata: {\"run_id\":\"r1\"}\n\n".data(using: .utf8)!,
            ("event: routing\ndata: {\"decision\":\"single_agent\",\"agents\":[\"product\"],"
             + "\"real_question\":\"Which label?\",\"request_type\":\"DECISION\"}\n\n").data(using: .utf8)!,
            "event: telemetry\ndata: {\"tokens_per_agent\":{},\"cost_estimate_usd\":0.004}\n\n".data(using: .utf8)!,
            "event: done\ndata: {\"run_id\":\"r1\",\"unresolved\":false,\"skipped\":\"single_agent\"}\n\n".data(using: .utf8)!
        ]

        let events = try await collect(mockedSession())
        XCTAssertEqual(events.count, 4)
        guard case let .done(_, _, skipped) = events[3] else { return XCTFail("expected .done last") }
        XCTAssertEqual(skipped, "single_agent")
    }

    func testAbandoningTheStreamTearsDownTheConnection() async throws {
        VCMockURLProtocol.reset()
        VCMockURLProtocol.responseChunks = [
            "event: run_started\ndata: {\"run_id\":\"r1\"}\n\n".data(using: .utf8)!,
            "event: agent_start\ndata: {\"agent_id\":\"product\",\"department_key\":null}\n\n".data(using: .utf8)!,
            "event: agent_start\ndata: {\"agent_id\":\"finance\",\"department_key\":null}\n\n".data(using: .utf8)!,
            "event: agent_start\ndata: {\"agent_id\":\"eng\",\"department_key\":null}\n\n".data(using: .utf8)!
        ]

        for try await _ in VirtualCompanyClient.run(request(),
                                                    session: mockedSession(),
                                                    authTokenProvider: { "fake" }) {
            break // consume exactly one event, then walk away mid-stream
        }

        var torndown = VCMockURLProtocol.stopLoadingCalled
        var attempts = 0
        while !torndown && attempts < 50 {
            try await Task.sleep(nanoseconds: 20_000_000) // 20ms
            torndown = VCMockURLProtocol.stopLoadingCalled
            attempts += 1
        }
        XCTAssertTrue(torndown, "expected stopLoading() to be called after the stream was abandoned")
    }

    func testFrameSplitAcrossChunksStillParses() async throws {
        VCMockURLProtocol.reset()
        VCMockURLProtocol.responseChunks = [
            "event: run_star".data(using: .utf8)!,
            "ted\ndata: {\"run_".data(using: .utf8)!,
            "id\":\"r2\"}\n\n".data(using: .utf8)!
        ]
        let events = try await collect(mockedSession())
        XCTAssertEqual(events, [.runStarted(runId: "r2")])
    }

    func testUnknownFrameIsSkippedAndTheRestSurvives() async throws {
        VCMockURLProtocol.reset()
        VCMockURLProtocol.responseChunks = [
            "event: some_future_event\ndata: {}\n\n".data(using: .utf8)!,
            "event: run_started\ndata: {\"run_id\":\"r3\"}\n\n".data(using: .utf8)!
        ]
        let events = try await collect(mockedSession())
        XCTAssertEqual(events, [.runStarted(runId: "r3")])
    }

    func testNon200ThrowsTypedErrorCarryingTheBody() async {
        VCMockURLProtocol.reset()
        VCMockURLProtocol.responseStatus = 503
        VCMockURLProtocol.responseHeaders = ["Content-Type": "application/json"]
        VCMockURLProtocol.responseChunks = [
            #"{"error":"feature_disabled"}"#.data(using: .utf8)!
        ]
        do {
            _ = try await collect(mockedSession())
            XCTFail("expected a throw")
        } catch let error as VirtualCompanyRunError {
            guard case let .http(status, body) = error else { return XCTFail("expected .http") }
            XCTAssertEqual(status, 503)
            XCTAssertEqual(body?.error, "feature_disabled")
        } catch {
            XCTFail("expected VirtualCompanyRunError, got \(error)")
        }
    }

    func testRateLimitBodyDecodesResetAt() async {
        VCMockURLProtocol.reset()
        VCMockURLProtocol.responseStatus = 429
        VCMockURLProtocol.responseHeaders = ["Content-Type": "application/json"]
        VCMockURLProtocol.responseChunks = [
            #"{"error":"daily_limit_reached","reset_at":"2026-08-05T00:00:00Z","limit":100000}"#
                .data(using: .utf8)!
        ]
        do {
            _ = try await collect(mockedSession())
            XCTFail("expected a throw")
        } catch let error as VirtualCompanyRunError {
            guard case let .http(_, body) = error else { return XCTFail("expected .http") }
            XCTAssertEqual(body?.resetAt, "2026-08-05T00:00:00Z")
            XCTAssertEqual(body?.limit, 100_000)
        } catch {
            XCTFail("expected VirtualCompanyRunError, got \(error)")
        }
    }
}

// codepetTests/CompanyChatClientTests.swift
import XCTest
@testable import codepet

final class CompanyChatClientTests: XCTestCase {
    func testRequestEncodesSnakeCaseAndRoundTrips() throws {
        let req = CompanyChatRequest(companyId: "u1", language: "en", companionId: "byte",
                                     context: "ctx", history: [ChatTurnDTO(role: "me", text: "hi")],
                                     userMessage: "hello")
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["company_id"] as? String, "u1")
        XCTAssertEqual(json?["companion_id"] as? String, "byte")
        XCTAssertEqual(json?["user_message"] as? String, "hello")
        let back = try JSONDecoder().decode(CompanyChatRequest.self, from: data)
        XCTAssertEqual(back.history, req.history)
    }
    func testResponseDecodesWithRunTaskId() throws {
        let data = "{\"reply\":\"On it\",\"run_task_id\":\"t1\"}".data(using: .utf8)!
        let r = try JSONDecoder().decode(CompanyChatResponse.self, from: data)
        XCTAssertEqual(r.reply, "On it")
        XCTAssertEqual(r.runTaskId, "t1")
    }
    func testResponseDecodesWithoutRunTaskId() throws {
        let data = "{\"reply\":\"hi\"}".data(using: .utf8)!
        XCTAssertNil(try JSONDecoder().decode(CompanyChatResponse.self, from: data).runTaskId)
    }

    // MARK: - Streaming tests
    //
    // These exercise sendStream's SSE parsing offline via a mocked URLProtocol
    // (no network), the same technique ReflectionAPIClientTests uses for
    // chatSessionStream. CompanyChatClient is a plain enum with static
    // functions (no actor isolation), so — unlike ReflectionAPIClient, which
    // is @MainActor — none of these tests need @MainActor (Xcode 26.2
    // isolated-deinit teardown bug).

    func testSendStreamHappyPathEmitsDeltasAndDone() async throws {
        CompanyChatMockURLProtocol.reset()
        CompanyChatMockURLProtocol.responseChunks = [
            "event: delta\ndata: {\"text\":\"On it \"}\n\n".data(using: .utf8)!,
            "event: delta\ndata: {\"text\":\"boss\"}\n\n".data(using: .utf8)!,
            "event: done\ndata: {\"model\":\"claude-sonnet-5\",\"cache_hit\":true}\n\n".data(using: .utf8)!
        ]

        var collected: [CompanyChatStreamEvent] = []
        for try await ev in CompanyChatClient.sendStream(
            makeMinimalRequest(),
            session: mockedCompanyChatSession(),
            authTokenProvider: { "fake" }
        ) {
            collected.append(ev)
        }
        XCTAssertEqual(collected.count, 3, "expected 3 stream events, got \(collected.count)")
        guard collected.count == 3 else { return }
        XCTAssertEqual(collected[0], .delta("On it "))
        XCTAssertEqual(collected[1], .delta("boss"))
        if case let .done(model, cacheHit) = collected[2] {
            XCTAssertEqual(model, "claude-sonnet-5")
            XCTAssertTrue(cacheHit)
        } else {
            XCTFail("expected .done")
        }
    }

    func testSendStreamSplitChunkParsesCorrectly() async throws {
        CompanyChatMockURLProtocol.reset()
        CompanyChatMockURLProtocol.responseChunks = [
            "event: delta\ndata: {\"text\":\"He".data(using: .utf8)!,
            "llo\"}\n\nevent: done\ndata: {\"model\":\"m\",\"cache_hit\":false}\n\n".data(using: .utf8)!
        ]
        var collected: [CompanyChatStreamEvent] = []
        for try await ev in CompanyChatClient.sendStream(
            makeMinimalRequest(),
            session: mockedCompanyChatSession(),
            authTokenProvider: { "fake" }
        ) {
            collected.append(ev)
        }
        XCTAssertEqual(collected.first, .delta("Hello"))
    }

    func testSendStream401Throws() async {
        CompanyChatMockURLProtocol.reset()
        CompanyChatMockURLProtocol.responseStatus = 401
        CompanyChatMockURLProtocol.responseHeaders = ["Content-Type": "application/json"]
        CompanyChatMockURLProtocol.responseChunks = ["{\"error\":\"invalid_token\"}".data(using: .utf8)!]

        do {
            for try await _ in CompanyChatClient.sendStream(
                makeMinimalRequest(),
                session: mockedCompanyChatSession(),
                authTokenProvider: { "fake" }
            ) {}
            XCTFail("expected error")
        } catch CompanyChatStreamError.http(let status, let body) {
            XCTAssertEqual(status, 401)
            XCTAssertEqual(body?.error, "invalid_token")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testSendStreamMidStreamErrorThrows() async {
        CompanyChatMockURLProtocol.reset()
        CompanyChatMockURLProtocol.responseChunks = [
            "event: delta\ndata: {\"text\":\"hi\"}\n\nevent: error\ndata: {\"error\":\"upstream_failure\",\"detail\":\"boom\"}\n\n".data(using: .utf8)!
        ]
        var collected: [CompanyChatStreamEvent] = []
        do {
            for try await ev in CompanyChatClient.sendStream(
                makeMinimalRequest(),
                session: mockedCompanyChatSession(),
                authTokenProvider: { "fake" }
            ) {
                collected.append(ev)
            }
            XCTFail("expected error")
        } catch CompanyChatStreamError.http(let status, let body) {
            XCTAssertEqual(collected, [.delta("hi")])
            XCTAssertEqual(status, 502)
            XCTAssertEqual(body?.error, "upstream_failure")
            XCTAssertEqual(body?.detail, "boom")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testSendStreamNoTokenThrowsNotSignedIn() async {
        CompanyChatMockURLProtocol.reset()
        do {
            for try await _ in CompanyChatClient.sendStream(
                makeMinimalRequest(),
                session: mockedCompanyChatSession(),
                authTokenProvider: { throw CompanyChatStreamError.notSignedIn }
            ) {}
            XCTFail("expected error")
        } catch CompanyChatStreamError.notSignedIn {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    private func makeMinimalRequest() -> CompanyChatRequest {
        CompanyChatRequest(
            companyId: "u1",
            language: "en",
            companionId: "byte",
            context: "ctx",
            history: [],
            userMessage: "what's next?"
        )
    }
}

// MARK: - URLProtocol mock for SSE (own type — distinct from
// ReflectionAPIClientTests' MockURLProtocol so the two test files stay
// independent and don't share mutable static state).

final class CompanyChatMockURLProtocol: URLProtocol {
    static var responseStatus: Int = 200
    static var responseHeaders: [String: String] = ["Content-Type": "text/event-stream"]
    /// Each entry is a chunk delivered to the consumer. Useful for testing split-frame parsing.
    static var responseChunks: [Data] = []
    static var responseError: Error?

    static func reset() {
        responseStatus = 200
        responseHeaders = ["Content-Type": "text/event-stream"]
        responseChunks = []
        responseError = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let client = self.client
        let request = self.request
        if let err = CompanyChatMockURLProtocol.responseError {
            client?.urlProtocol(self, didFailWithError: err)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: CompanyChatMockURLProtocol.responseStatus,
            httpVersion: "HTTP/1.1",
            headerFields: CompanyChatMockURLProtocol.responseHeaders
        )!
        let chunks = CompanyChatMockURLProtocol.responseChunks
        // Deliver response headers synchronously, then deliver body chunks
        // asynchronously so URLSession's internal byte-stream iterator has a
        // chance to attach before data (and didFinishLoading) arrive.
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.01) {
            for chunk in chunks {
                client?.urlProtocol(self, didLoad: chunk)
            }
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

private func mockedCompanyChatSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [CompanyChatMockURLProtocol.self]
    return URLSession(configuration: config)
}

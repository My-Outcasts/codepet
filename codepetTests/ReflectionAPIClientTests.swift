import XCTest
@testable import codepet

final class ReflectionAPIClientTests: XCTestCase {

    func testRequestEncodingShape() throws {
        let payload = SummarizeTurnRequest(
            turnId: "s1:2026-05-05T09:00:00Z",
            sessionId: "s1",
            language: "vi",
            prompt: "fix",
            events: [
                .init(time: "09:00", tool: "Edit", path: "foo.swift", text: nil)
            ],
            rawSummary: "Edit foo.swift",
            petPersona: nil,
            userBrief: nil,
            petMemory: nil
        )
        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["turn_id"] as? String, "s1:2026-05-05T09:00:00Z")
        XCTAssertEqual(json["session_id"] as? String, "s1")
        XCTAssertEqual(json["language"] as? String, "vi")
        let events = json["events"] as! [[String: Any]]
        XCTAssertEqual(events.first?["tool"] as? String, "Edit")
        XCTAssertEqual(events.first?["path"] as? String, "foo.swift")
    }

    func testResponseDecodes() throws {
        let json = """
        {
          "turn_id": "s1:2026-05-05T09:00:00Z",
          "narrative": {
            "title": "T",
            "what_you_wanted": "w",
            "what_happened": "h",
            "lesson": "l"
          },
          "model": "claude-haiku-4-5-20251001",
          "cache_hit": false
        }
        """.data(using: .utf8)!

        let resp = try JSONDecoder().decode(SummarizeTurnResponse.self, from: json)
        XCTAssertEqual(resp.narrative.title, "T")
        XCTAssertEqual(resp.model, "claude-haiku-4-5-20251001")
        XCTAssertFalse(resp.cacheHit)
    }

    func testQuotaErrorDecodes() throws {
        let json = """
        {
          "error": "daily_limit_reached",
          "reset_at": "2026-05-06T00:00:00Z",
          "limit": 50
        }
        """.data(using: .utf8)!
        let err = try JSONDecoder().decode(SummarizeTurnError.self, from: json)
        XCTAssertEqual(err.error, "daily_limit_reached")
        XCTAssertEqual(err.limit, 50)
    }

    func testChatSessionRequestEncodesSnakeCase() throws {
        let request = ChatSessionRequest(
            sessionId: "s1",
            language: "vi",
            petPersona: SummarizeTurnRequest.PetPersonaDTO(
                id: "byte", name: "Byte", personality: "glitchy", domain: "Data",
                voiceGuide: "short fragments", lensGuide: "data flow",
                emotionalTriggers: "excited by patterns", metaphorFamily: "circuits",
                signatureEmojis: "⚡ 📡 🔮 💜"
            ),
            sessionContext: ChatSessionRequest.SessionContextDTO(
                userBrief: "building",
                summary: ChatSessionRequest.SessionContextDTO.SummaryDTO(
                    summary: "We worked.", lesson: "Stay focused."
                ),
                turns: [
                    ChatSessionRequest.SessionContextDTO.TurnDTO(
                        prompt: "fix",
                        whatYouWanted: "you wanted",
                        whatHappened: "you did",
                        lesson: "be patient",
                        durationMinutes: 12,
                        events: [SummarizeTurnRequest.EventDTO(
                            time: "09:00", tool: "Edit", path: "foo.swift", text: nil
                        )]
                    )
                ]
            ),
            history: [
                ChatSessionRequest.ChatMessageDTO(role: "user", text: "hi"),
                ChatSessionRequest.ChatMessageDTO(role: "pet", text: "hi back")
            ],
            userMessage: "what was tricky?"
        )

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["session_id"] as? String, "s1")
        XCTAssertEqual(json["language"] as? String, "vi")
        XCTAssertEqual(json["user_message"] as? String, "what was tricky?")

        let context = json["session_context"] as! [String: Any]
        XCTAssertEqual(context["user_brief"] as? String, "building")
        let turns = context["turns"] as! [[String: Any]]
        XCTAssertEqual(turns.first?["prompt"] as? String, "fix")
        XCTAssertEqual(turns.first?["what_you_wanted"] as? String, "you wanted")
        XCTAssertEqual(turns.first?["duration_minutes"] as? Int, 12)
        let history = json["history"] as! [[String: Any]]
        XCTAssertEqual(history.first?["role"] as? String, "user")
    }

    // MARK: - Streaming tests

    @MainActor
    func testChatStreamHappyPathEmitsDeltasAndDone() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.responseChunks = [
            "event: delta\ndata: {\"text\":\"Together \"}\n\n".data(using: .utf8)!,
            "event: delta\ndata: {\"text\":\"we kept \"}\n\n".data(using: .utf8)!,
            "event: done\ndata: {\"model\":\"claude-haiku-4-5-20251001\",\"cache_hit\":true}\n\n".data(using: .utf8)!
        ]

        let client = ReflectionAPIClient(session: mockedURLSession(), authTokenProvider: { "fake" })
        let request = makeMinimalChatRequest()
        var collected: [ChatStreamEvent] = []
        for try await ev in client.chatSessionStream(request) {
            collected.append(ev)
        }
        XCTAssertEqual(collected.count, 3, "expected 3 stream events, got \(collected.count)")
        guard collected.count == 3 else { return }
        XCTAssertEqual(collected[0], .delta("Together "))
        XCTAssertEqual(collected[1], .delta("we kept "))
        if case let .done(model, cacheHit) = collected[2] {
            XCTAssertEqual(model, "claude-haiku-4-5-20251001")
            XCTAssertTrue(cacheHit)
        } else {
            XCTFail("expected .done")
        }
    }

    @MainActor
    func testChatStreamSplitChunkParsesCorrectly() async throws {
        MockURLProtocol.reset()
        MockURLProtocol.responseChunks = [
            "event: delta\ndata: {\"text\":\"He".data(using: .utf8)!,
            "llo\"}\n\nevent: done\ndata: {\"model\":\"m\",\"cache_hit\":false}\n\n".data(using: .utf8)!
        ]
        let client = ReflectionAPIClient(session: mockedURLSession(), authTokenProvider: { "fake" })
        var collected: [ChatStreamEvent] = []
        for try await ev in client.chatSessionStream(makeMinimalChatRequest()) {
            collected.append(ev)
        }
        XCTAssertEqual(collected.first, .delta("Hello"))
    }

    @MainActor
    func testChatStream401Throws() async {
        MockURLProtocol.reset()
        MockURLProtocol.responseStatus = 401
        MockURLProtocol.responseHeaders = ["Content-Type": "application/json"]
        MockURLProtocol.responseChunks = ["{\"error\":\"invalid_token\"}".data(using: .utf8)!]

        let client = ReflectionAPIClient(session: mockedURLSession(), authTokenProvider: { "fake" })
        do {
            for try await _ in client.chatSessionStream(makeMinimalChatRequest()) {}
            XCTFail("expected error")
        } catch ReflectionAPIError.http(let status, _) {
            XCTAssertEqual(status, 401)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    @MainActor
    func testChatStream429ThrowsWithBody() async {
        MockURLProtocol.reset()
        MockURLProtocol.responseStatus = 429
        MockURLProtocol.responseHeaders = ["Content-Type": "application/json"]
        MockURLProtocol.responseChunks = [
            "{\"error\":\"daily_limit_reached\",\"reset_at\":\"2026-05-08T00:00:00Z\",\"limit\":50}".data(using: .utf8)!
        ]

        let client = ReflectionAPIClient(session: mockedURLSession(), authTokenProvider: { "fake" })
        do {
            for try await _ in client.chatSessionStream(makeMinimalChatRequest()) {}
            XCTFail("expected error")
        } catch ReflectionAPIError.http(let status, let body) {
            XCTAssertEqual(status, 429)
            XCTAssertEqual(body?.error, "daily_limit_reached")
            XCTAssertEqual(body?.limit, 50)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    @MainActor
    func testChatStreamMidStreamErrorThrows() async {
        MockURLProtocol.reset()
        MockURLProtocol.responseChunks = [
            "event: delta\ndata: {\"text\":\"hi\"}\n\nevent: error\ndata: {\"error\":\"upstream_failure\"}\n\n".data(using: .utf8)!
        ]
        let client = ReflectionAPIClient(session: mockedURLSession(), authTokenProvider: { "fake" })
        var collected: [ChatStreamEvent] = []
        do {
            for try await ev in client.chatSessionStream(makeMinimalChatRequest()) {
                collected.append(ev)
            }
            XCTFail("expected error")
        } catch ReflectionAPIError.http(let status, _) {
            XCTAssertEqual(collected, [.delta("hi")])
            XCTAssertEqual(status, 502)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    private func makeMinimalChatRequest() -> ChatSessionRequest {
        ChatSessionRequest(
            sessionId: "s1",
            language: "en",
            petPersona: nil,
            sessionContext: ChatSessionRequest.SessionContextDTO(
                userBrief: nil,
                summary: nil,
                turns: [
                    ChatSessionRequest.SessionContextDTO.TurnDTO(
                        prompt: "hi",
                        whatYouWanted: nil,
                        whatHappened: nil,
                        lesson: nil,
                        durationMinutes: nil,
                        events: []
                    )
                ]
            ),
            history: [],
            userMessage: "what?"
        )
    }
}

// MARK: - URLProtocol mock for SSE

final class MockURLProtocol: URLProtocol {
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
        if let err = MockURLProtocol.responseError {
            client?.urlProtocol(self, didFailWithError: err)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: MockURLProtocol.responseStatus,
            httpVersion: "HTTP/1.1",
            headerFields: MockURLProtocol.responseHeaders
        )!
        let chunks = MockURLProtocol.responseChunks
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

private func mockedURLSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

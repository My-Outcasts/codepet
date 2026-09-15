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

    // MARK: - Streaming
    //
    // Five tests used to sit here, driving the SSE bodies of `chatSessionStream` through a
    // stubbed `URLSession`. Those bodies are gone: the routing below them now fails closed,
    // which made every line after the switch unreachable — the compiler said so in three
    // `will never be executed` warnings — so the frame decoders they exercised
    // (`handleNarrativeFrame`, `handleSessionFrame`, `handle`) went with them.
    //
    // What happened to each is recorded in `.superpowers/sdd/task-3b-report.md`. The short
    // version: two were pure HTTP status mapping and are simply gone with the requests they
    // mapped; two decoded frames into events and had no subject left once the decoders were
    // deleted; and the fifth — a frame split across two reads — moved to
    // `SSEParserTests.testHoldsAFrameAcrossSeparateFeeds`, because `SSEParser` itself
    // survives this phase and `LocalChatStreamer` still parses the sidecar's SSE with it.

    // MARK: - Failing closed when the founder has not granted

    /// An ungranted founder must get the REASON, and must not have a request built on her
    /// behalf. `localStreamOp` used to answer nil for exactly this founder, meaning "carry
    /// on to the SSE path below" — a path that spends an Anthropic key Codepet no longer
    /// holds, so the only thing it could produce is a 401 she cannot act on.
    ///
    /// `CloudAIBlock` already refuses these three paths at the URL layer, so this was dead
    /// in production. That is not a reason to leave it written: "unreachable because
    /// something underneath says no" is the state this phase exists to remove.
    @MainActor
    func testUngrantedSummarizeTurnStreamFailsWithTheReasonAndIssuesNoRequest() async {
        MockURLProtocol.reset()
        LocalTransportRouter.apply(companyId: nil)
        defer { LocalTransportRouter.apply(companyId: nil) }

        let client = ReflectionAPIClient(session: mockedURLSession(), authTokenProvider: { "fake" })
        var collected: [NarrativeStreamEvent] = []
        do {
            for try await ev in client.summarizeTurnStream(makeMinimalTurnRequest()) {
                collected.append(ev)
            }
            XCTFail("an ungranted founder must not get a stream that completes")
        } catch ReflectionAPIError.blocked(let reason) {
            XCTAssertEqual(reason, .notGranted)
        } catch {
            XCTFail("expected .blocked(.notGranted), got \(error)")
        }
        XCTAssertEqual(collected, [], "a blocked call must yield nothing, not a started event")
        XCTAssertEqual(MockURLProtocol.attemptedRequests.count, 0,
                       "a blocked call still built an HTTP request: \(MockURLProtocol.attemptedRequests.compactMap { $0.url?.absoluteString })")
    }

    /// The sibling ops read the same grant through the same helper, so a fix that only
    /// reached `summarizeTurnStream` would leave two of the three routes open.
    @MainActor
    func testUngrantedSessionAndChatStreamsFailClosedToo() async {
        MockURLProtocol.reset()
        LocalTransportRouter.apply(companyId: nil)
        defer { LocalTransportRouter.apply(companyId: nil) }

        let client = ReflectionAPIClient(session: mockedURLSession(), authTokenProvider: { "fake" })

        do {
            for try await _ in client.summarizeSessionStream(makeMinimalSessionRequest()) {}
            XCTFail("summarizeSessionStream completed for an ungranted founder")
        } catch ReflectionAPIError.blocked(let reason) {
            XCTAssertEqual(reason, .notGranted)
        } catch {
            XCTFail("summarizeSessionStream: expected .blocked(.notGranted), got \(error)")
        }

        do {
            for try await _ in client.chatSessionStream(makeMinimalChatRequest()) {}
            XCTFail("chatSessionStream completed for an ungranted founder")
        } catch ReflectionAPIError.blocked(let reason) {
            XCTAssertEqual(reason, .notGranted)
        } catch {
            XCTFail("chatSessionStream: expected .blocked(.notGranted), got \(error)")
        }

        XCTAssertEqual(MockURLProtocol.attemptedRequests.count, 0,
                       "a blocked call still built an HTTP request")
    }

    /// The NON-streaming ops have to name her fix too, and they did not.
    ///
    /// `localOneShot` logged the real reason and then threw
    /// `LocalOneShotRunner.Failure.unavailable`, whose founder-facing text is "Codepet
    /// can't reach its local runner on this Mac. Reinstalling Codepet should restore it."
    /// So a founder whose only problem is an ungranted toggle was told to reinstall the
    /// app — the exact mis-routing `BlockReason` exists to stop, and the one
    /// `LocalTransportRouterTests.testAMissingSidecarDoesNotChangeAnUngrantedFoundersReason`
    /// guards one layer down. The reason reached the log and died there.
    @MainActor
    func testUngrantedOneShotTellsHerToGrantRatherThanToReinstall() async {
        MockURLProtocol.reset()
        LocalTransportRouter.apply(companyId: nil)
        defer { LocalTransportRouter.apply(companyId: nil) }

        let client = ReflectionAPIClient(session: mockedURLSession(), authTokenProvider: { "fake" })
        do {
            _ = try await client.summarizeTurn(makeMinimalTurnRequest())
            XCTFail("an ungranted founder must not get a summary")
        } catch {
            guard case ReflectionAPIError.blocked(let reason) = error else {
                let shown = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                return XCTFail("expected .blocked(.notGranted); the founder is told: \"\(shown)\"")
            }
            XCTAssertEqual(reason, .notGranted)
            XCTAssertTrue(reason.founderText.contains("Settings"),
                          "her fix is a toggle, so the copy has to point at it: \(reason.founderText)")
            XCTAssertFalse(reason.founderText.lowercased().contains("reinstall"),
                           "an ungranted founder was told to reinstall: \(reason.founderText)")
        }
        XCTAssertEqual(MockURLProtocol.attemptedRequests.count, 0,
                       "a blocked one-shot still built an HTTP request")
    }

    private func makeMinimalSessionRequest() -> SummarizeSessionRequest {
        SummarizeSessionRequest(
            sessionId: "s1",
            language: "en",
            turns: [],
            petPersona: nil,
            userBrief: nil,
            petMemory: nil
        )
    }

    private func makeMinimalTurnRequest() -> SummarizeTurnRequest {
        SummarizeTurnRequest(
            turnId: "s1:t1",
            sessionId: "s1",
            language: "en",
            prompt: "hi",
            events: [],
            rawSummary: "",
            petPersona: nil,
            userBrief: nil,
            petMemory: nil
        )
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
    /// Every request that reached the transport. A blocked call must leave this EMPTY —
    /// asserting on the events alone would pass just as well if the request went out and
    /// came back 401, which is the exact failure this phase removes.
    static var attemptedRequests: [URLRequest] = []

    static func reset() {
        responseStatus = 200
        responseHeaders = ["Content-Type": "text/event-stream"]
        responseChunks = []
        responseError = nil
        attemptedRequests = []
    }

    override class func canInit(with request: URLRequest) -> Bool {
        attemptedRequests.append(request)
        return true
    }
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
